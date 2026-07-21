# sre-workload Helm Chart ŌĆö Reference

**Chart path**: `helm/sre-workload`  
**Image**: `ghcr.io/e2b-dev/sre-interview:latest`

This document describes every Kubernetes object the chart produces, every significant values decision and why it was made, the template helpers, and the JSON schema validation. The chart's design philosophy is stated once here and not repeated per resource: all cloud-specific behaviour lives in values overlays (`values-aws.yaml` / `values-gcp.yaml`), never in templates.

---

## Values composition model

The chart is deployed with two or three values sources layered in order:

```bash
# AWS
helm install sre-workload . \
  -f values.yaml \
  -f values-aws.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ARN> \
  --set ingress.host=sre.example.com

# GCP
helm install sre-workload . \
  -f values.yaml \
  -f values-gcp.yaml \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL> \
  --set ingress.host=sre.example.com
```

Later sources override earlier ones for the same key. `values.yaml` establishes all defaults and is the single source of truth for every value the chart uses. `values-{cloud}.yaml` overrides only the fields that differ per cloud (the pod identity annotation key, the StorageClass name, ingress enablement, and the OS node selector). The `--set` flags supply values that are known only at deploy time (the IRSA ARN or GSA email comes from Terraform output, and the hostname is per-customer).

This model means:
- `values.yaml` alone is sufficient for local `kind` testing ŌĆö no cloud credentials or identity wiring needed.
- Cloud-specific fields are explicit and auditable in overlay files, not scattered through template conditionals.
- Adding a new cloud is a new overlay file, not a change to any template.

---

## Kubernetes objects produced

| Object | Kind | Always created | Condition |
|---|---|---|---|
| `ServiceAccount` | `v1` | if `serviceAccount.create=true` | default: yes |
| `Deployment` | `apps/v1` | Ō£ģ always | ŌĆö |
| `Service` | `v1` | Ō£ģ always | ŌĆö |
| `HorizontalPodAutoscaler` | `autoscaling/v2` | if `autoscaling.enabled=true` | default: yes |
| `PodDisruptionBudget` | `policy/v1` | if `podDisruptionBudget.enabled=true` | default: yes |
| `Ingress` | `networking.k8s.io/v1` | if `ingress.enabled=true` | default: no; standard cloud overlays enable it |
| `Gateway` | `gateway.networking.k8s.io/v1` | if `gateway.enabled=true` AND `gateway.createGateway=true` | default: no; gateway overlays enable it |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | if `gateway.enabled=true` | default: no; gateway overlays enable it |
| `Certificate` | `cert-manager.io/v1` | if `gateway.enabled=true` AND `gateway.tls.enabled=true` | default: no; gateway overlays enable it |
| `NetworkPolicy` | `networking.k8s.io/v1` | if `networkPolicy.enabled=true` | default: yes |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | if `serviceMonitor.enabled=true` | default: no |

The chart supports two mutually exclusive routing modes. With the standard cloud overlays (`values-aws.yaml` / `values-gcp.yaml`), it produces seven objects: ServiceAccount, Deployment, Service, HPA, PDB, Ingress, and NetworkPolicy. With the gateway overlays (`values-aws-gateway.yaml` / `values-gcp-gateway.yaml`), Ingress is replaced by Gateway + HTTPRoute + Certificate ŌĆö nine objects total when TLS is enabled.

---

## Confirmed image behaviour

Before describing the chart, the image's actual runtime behaviour:

**Port 8080** is the application port. Every path ŌĆö `/healthz`, `/readyz`, `/this-path-does-not-exist`, and all others ŌĆö returns `200 OK`. This is a catch-all router, not a differentiated health endpoint. Liveness and readiness probes both return `200` on every path; the probes are valid signals that the HTTP server is alive, but they do not verify that the workload is actually healthy in any deeper sense. All chart defaults (`service.port: 8080`, `probes.path: /healthz`, `probes.readyPath: /readyz`) reflect this confirmed behaviour.

**Port 9090** is a second HTTP server labelled "internal server" in the container's own startup log. Unlike port 8080, it returns proper `404` responses on unknown paths (it has a real router). Its purpose is unconfirmed: it is not a Prometheus `/metrics` endpoint and is not the standard `net/http/pprof` mount. This port is deliberately not exposed anywhere in the chart: no Service port, no Ingress rule, no NetworkPolicy allow rule.

**To investigate before enabling,** run the container and probe the port to enumerate live routes:

```bash
docker run --rm -d -p 18080:8080 -p 19090:9090 --name sre-probe ghcr.io/e2b-dev/sre-interview:latest
# Scan for known admin/metrics/debug path patterns
for path in /metrics /debug/pprof /debug/vars /healthz /readyz /admin /status /info /version; do
  echo -n "$path: "; curl -s -o /dev/null -w "%{http_code}" http://localhost:19090$path; echo
done
# Extract route strings from the binary if Go-based
docker exec sre-probe sh -c 'strings /proc/1/exe 2>/dev/null | grep -E "^/(metrics|debug|admin|pprof|status|api)" | sort -u'
docker rm -f sre-probe
```

Once the routes are confirmed, the addition is a second named port (`internal`) on the Service, a matching `containerPort`, and a scoped `NetworkPolicy` ingress rule rather than broadening the existing `from: []` rule.

---

## Objects in detail

### ServiceAccount

**Template**: `templates/serviceaccount.yaml`  
**Created when**: `serviceAccount.create = true` (default)

```yaml
# Rendered with defaults
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sre-workload          # generated by sre-workload.serviceAccountName helper
  labels: ...                 # standard chart labels
  annotations: {}             # empty in values.yaml; set by cloud overlay + --set
automountServiceAccountToken: false
```

The ServiceAccount is the Kubernetes identity the workload pods run as. Two properties matter most:

**`automountServiceAccountToken: false`** is set at both the ServiceAccount level and the pod spec level (see Deployment below). The Kubernetes default is `true` ŌĆö every pod receives a projected JWT for the in-cluster API server, mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`, even if the workload never calls the API server. For workloads that use AWS IRSA or GCP Workload Identity, this default token is unnecessary: IRSA injects its own projected token via the EKS pod identity webhook; GKE's metadata proxy issues tokens on demand. Having both a mounted API server token and a cloud-identity token in the same pod is redundant and slightly increases the blast radius if a pod is compromised. Setting both fields to `false` ensures the token is not mounted.

**`annotations`** is empty (`{}`) in both `values.yaml` and all cloud overlays. The cloud overlays no longer pre-seed the annotation key with an empty string — an empty-string annotation is written to the ServiceAccount object but creates no IAM binding, and creates the false impression that one exists. Supply the value only when the workload genuinely needs cloud API access:

- On AWS: `--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN>`. The EKS pod identity webhook reads this annotation and injects `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` into pods running under this ServiceAccount.
- On GCP: `--set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL>`. GKE's metadata proxy reads this annotation and issues GCP access tokens for the named Google Service Account when pods request credentials.

---

### Deployment

**Template**: `templates/deployment.yaml`  
**Always created**

```yaml
# Rendered with defaults (HPA enabled)
apiVersion: apps/v1
kind: Deployment
spec:
  # replicas field omitted ŌĆö HPA owns the count
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 25%
  template:
    spec:
      serviceAccountName: sre-workload
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: ...
      containers:
        - name: sre-workload
          image: ghcr.io/e2b-dev/sre-interview:latest
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          ports:
            - name: http
              containerPort: 8080
          startupProbe: ...
          readinessProbe: ...
          livenessProbe: ...
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 512Mi }
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

#### `replicas` and HPA ownership

When `autoscaling.enabled = true` (the default), the `replicas` field is omitted from the Deployment spec entirely. If `replicas` is present alongside an HPA, Kubernetes and the HPA controller can fight: Terraform/Helm might reset `replicas` to the Deployment's declared count on the next apply, and the HPA immediately overrides it back. Omitting the field entirely means the HPA is the sole authoritative source of replica count from the moment of installation. The initial `minReplicas = 3` from the HPA determines the starting count.

When `autoscaling.enabled = false`, the `replicas` field is rendered from `replicaCount` (default: 3), giving a fixed count.

#### Rollout strategy

```
maxUnavailable: 0
maxSurge: 25%
```

`maxUnavailable: 0` means capacity never drops below the current replica count during a rollout. No pod is removed until a replacement is Running and Ready. Combined with `maxSurge: 25%`, Kubernetes can run up to 25% more pods than the desired count during the transition ŌĆö at `minReplicas = 3`, that means one extra pod (3 ├Ś 25% = 0.75, rounded up to 1). The rollout pattern is: add one new pod, wait for it to pass readiness, remove one old pod, repeat. The `PodDisruptionBudget` (`minAvailable: 2`) is respected throughout because `maxUnavailable: 0` is stricter during rolling updates; the PDB governs concurrent node-level disruptions outside Deployment control.

#### Pod security context

```yaml
runAsNonRoot: true
runAsUser: 65532
fsGroup: 65532
seccompProfile:
  type: RuntimeDefault
```

`runAsNonRoot: true` is a Kubernetes admission control that rejects the pod if the image's user is UID 0 (root), even if the container securityContext doesn't explicitly set a user. The check happens before the container starts; it's a safety net against an image change that unexpectedly runs as root.

`runAsUser: 65532` and `fsGroup: 65532` use UID/GID 65532, which is the UID conventionally used in distroless and minimalist container images (it appears as `nonroot` in some base images). The image's filesystem permissions must allow this UID to read its own binaries; if a future image update changes the expected UID, these values need to be updated.

`seccompProfile: RuntimeDefault` enables the container runtime's default seccomp profile. Seccomp restricts the set of Linux system calls the container can make. The `RuntimeDefault` profile (maintained by containerd or CRI-O) blocks known-dangerous syscalls that have no legitimate use in a containerised application, such as `ptrace`, `keyctl`, and several others. It does not restrict normal application syscalls. Enabling it costs nothing at runtime and removes an entire class of kernel exploitation vectors.

#### Container security context

```yaml
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
```

`allowPrivilegeEscalation: false` prevents a process inside the container from gaining more privileges than its parent ŌĆö for example, by executing a `setuid` binary or calling `prctl(PR_SET_DUMPABLE)`. This applies even if the container's image contains such binaries.

`readOnlyRootFilesystem: true` mounts the container's root filesystem as read-only. Any attempt to write to a path outside an explicitly declared volume fails with a permission error. This prevents an attacker who achieves code execution from modifying the application binary, writing a cron job, or leaving persistence files. The tradeoff is that any path the application legitimately writes to must be declared as a volume mount.

`capabilities: drop: ["ALL"]` drops all Linux capabilities from the container's capability set. By default, containers retain a small set of capabilities (like `NET_BIND_SERVICE` for binding to ports below 1024). Dropping all of them removes the ability to perform any privileged kernel operation, even if the container runs as root (which it doesn't here). Since the workload listens on port 8080 (above 1024), `NET_BIND_SERVICE` is not needed.

**The `/tmp` volume.** Because `readOnlyRootFilesystem: true` prevents any writes, the template automatically adds an `emptyDir` volume mounted at `/tmp` whenever this setting is true. Many applications ŌĆö including Go's standard library for certain operations ŌĆö write temporary files to `/tmp`. Without this mount, such writes fail silently or with a cryptic error. `emptyDir` volumes are node-local, ephemeral, and not shared between pods; they are the correct choice for temporary scratch space.

#### Probes

```
startup:   GET /healthz, 5s period, 30 failures allowed  (150s total boot window)
readiness: GET /readyz,  10s period, 3 failures, 3s timeout
liveness:  GET /healthz, 15s period, 3 failures, 3s timeout
```

All three probes use the shared `sre-workload.probeSpec` helper (described below), which renders the correct probe type (HTTP/TCP/exec) based on `probes.type`. The default is `http`.

The **startup probe** runs first and blocks the readiness and liveness probes until it succeeds. It allows 30 failures at 5-second intervals ŌĆö a 150-second window before Kubernetes kills the container. This window protects slow-starting applications from being killed by a liveness probe that fires before they are ready. Once the startup probe succeeds, it stops running entirely and the other probes take over.

The **readiness probe** determines whether a pod receives traffic from the Service. A pod failing readiness is removed from the Service's endpoint list but is not killed. It is given three chances (over 30 seconds) to recover before being removed. The probe fires every 10 seconds; a pod that becomes unhealthy is removed from rotation within 30 seconds. Because the workload's `/readyz` is a catch-all that always returns 200, the probe currently measures only that the HTTP server is alive, not that the workload is actually ready to serve. This is noted as a known limitation.

The **liveness probe** determines whether a pod should be killed and replaced. It fires every 15 seconds and allows 3 failures (45 seconds of failure) before killing the container. The longer period compared to readiness is intentional: a transient failure should not immediately trigger a restart. The liveness probe path (`/healthz`) is the same catch-all as the readiness path; a liveness failure indicates the HTTP server is not responding at all, which is a stronger signal than a slow response.

#### Topology spread

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: <selector for this Deployment's pods>
```

This constraint asks Kubernetes to distribute the workload's pods evenly across availability zones. `maxSkew: 1` means the difference in pod count between the most-loaded and least-loaded zone may not exceed 1. With `minReplicas = 3` and three zones (both AWS `us-east-1` and GCP `us-east1` have three zones), the scheduler places one pod per zone in the steady state.

`whenUnsatisfiable: ScheduleAnyway` allows the scheduler to violate the constraint if it cannot be satisfied ŌĆö for example, on a single-node `kind` cluster where there is only one zone. The alternative, `DoNotSchedule`, would leave pods `Pending` indefinitely on clusters that cannot satisfy the zone spread. `ScheduleAnyway` makes the chart usable for local testing without changes, at the cost of a softer guarantee in production.

#### Resource requests and limits

```
requests: { cpu: 100m, memory: 128Mi }
limits:   { cpu: 500m, memory: 512Mi }
```

**Requests** are what the scheduler uses to decide where to place a pod and what the HPA uses to compute utilisation percentages. At 100m CPU and 128Mi memory, the workload's resource footprint is declared to be small. On an m6i.large (2 vCPU, 8 GiB), this allows up to 20 pods by CPU and 64 by memory before the node is saturated ŌĆö well above the HPA maximum of 10.

**Limits** cap the maximum resources the container can consume. At 500m CPU (half a core), the workload can burst up to five times its baseline during a spike without being throttled. At 512Mi memory, the container is killed by the OOM killer if it exceeds this value. The 4:1 ratio between limit and request (for both CPU and memory) is deliberately generous, reflecting that the workload's true steady-state consumption is unconfirmed against real traffic.

#### Graceful shutdown (`terminationGracePeriodSeconds` + `preStop`)

```
terminationGracePeriodSeconds: 30   (configurable via values.terminationGracePeriodSeconds)
lifecycle.preStop: sleep 5          (configurable via values.lifecycle.preStopSleepSeconds)
```

When a pod is evicted or replaced, Kubernetes sends `SIGTERM` to the container and simultaneously removes the pod's IP from the Service's endpoint list. However, kube-proxy and iptables propagation are not instantaneous — there is a window during which load balancers and other pods may still route new connections to the terminating pod. If the container stops immediately on `SIGTERM`, those in-flight requests receive connection resets.

The `preStop` hook runs **before** `SIGTERM` is delivered. The 5-second `sleep` gives kube-proxy time to finish propagating the endpoint removal to all nodes, so that by the time `SIGTERM` arrives, no new connections are being routed to this pod. Existing connections continue to drain during the remaining grace period.

`terminationGracePeriodSeconds: 30` is the total budget from the start of termination to `SIGKILL`. The timeline is: preStop hook starts (5s sleep) → SIGTERM delivered → workload performs its own graceful shutdown → SIGKILL if still running at 30s. The 30s budget must exceed `preStopSleepSeconds` plus the workload's own shutdown time; adjust both values if the workload takes longer to drain (e.g., long-lived WebSocket connections or slow connection draining).

---

### Service

**Template**: `templates/service.yaml`  
**Always created**

```yaml
apiVersion: v1
kind: Service
spec:
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: http   # resolved to containerPort 8080 by name
      protocol: TCP
      name: http
```

The Service is `ClusterIP` ŌĆö it is reachable only from within the cluster, not from outside. External traffic enters through the Ingress controller, which routes HTTP/S requests to this Service, which forwards them to the pods. Using `ClusterIP` rather than `LoadBalancer` prevents the accidental creation of a cloud load balancer if the Ingress is disabled.

`targetPort: http` references the named port `http` declared in the Deployment's container spec (`containerPort: 8080, name: http`). Using named ports rather than numeric ones means the container port can be changed in one place (the Deployment) without updating the Service.

---

### HorizontalPodAutoscaler

**Template**: `templates/hpa.yaml`  
**Created when**: `autoscaling.enabled = true` (default)

```yaml
apiVersion: autoscaling/v2
spec:
  scaleTargetRef:
    kind: Deployment
    name: sre-workload
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
```

`autoscaling/v2` is the current API version; v1 supports only a single CPU metric. v2 enables both CPU and memory metrics simultaneously, and the `behavior` block for controlling scaling velocity.

**CPU target: 70%.** The HPA keeps average CPU utilisation across all pods below 70% of the declared CPU request (100m). When the average rises above 70m, the HPA adds pods. At 70% of a 100m request, each pod is using 70m CPU. With the 500m CPU limit, there is still significant headroom for the application to absorb additional load between HPA decisions. 70% is a common target ŌĆö low enough to provide headroom for traffic spikes during the time it takes to provision and start a new pod, high enough not to waste node capacity.

**Memory target: 80%.** Memory utilisation is a less dynamic signal than CPU ŌĆö it tends to grow and not shrink between garbage collection cycles. 80% of the 128Mi memory request (102Mi) is the trigger. Memory-based scaling works better when the workload's memory usage scales with load (e.g., per-request caches). For workloads with relatively stable memory use, the CPU metric is the primary driver and the memory metric acts as a backstop.

**Scale-down behavior.** `stabilizationWindowSeconds: 300` prevents scale-down for 5 minutes after the last scale-up event. This dampens the "flapping" pattern where bursty traffic causes rapid scale-up followed immediately by scale-down, which then fails to handle the next burst. The `Percent: 25, periodSeconds: 60` policy limits scale-down to removing at most 25% of pods per minute. With 10 pods, that is at most 2 pods per minute. Scale-down is conservative by design.

**Scale-up behavior.** `stabilizationWindowSeconds: 0` means scale-up is immediate ŌĆö as soon as the HPA computes that more replicas are needed, it requests them. The `Percent: 100, periodSeconds: 30` policy allows doubling the pod count every 30 seconds. With 3 pods, the sequence during sustained high load is: 3 ŌåÆ 6 ŌåÆ 10 (capped at maxReplicas). Scale-up is aggressive by design: the cost of over-provisioning during a spike is much lower than the cost of a degraded or unavailable service.

**`minReplicas: 3`.** With topology spread across three zones, 3 is the minimum that guarantees one pod per zone. Fewer than 3 would mean a zone has no pods, and requests routed to that zone by a cloud load balancer would fail before the session affinity mechanisms in ingress-nginx redirect them.

**`maxReplicas: 10`.** A soft cap on the total pod count. At 10 pods ├Ś 100m CPU request, the workload consumes 1 full vCPU of requested capacity ŌĆö easily accommodated on three m6i.large nodes. This cap should be revisited based on actual load patterns; the value is a starting point, not a permanent limit.

---

### PodDisruptionBudget

**Template**: `templates/pdb.yaml`  
**Created when**: `podDisruptionBudget.enabled = true` (default)

```yaml
apiVersion: policy/v1
spec:
  minAvailable: 2
  selector:
    matchLabels: <selector for this Deployment's pods>
```

A PodDisruptionBudget constrains voluntary disruptions ŌĆö operations initiated by humans or controllers, such as node drains, cluster upgrades, and Karpenter consolidations. The PDB does not protect against involuntary disruptions (node failures, OOM kills).

`minAvailable: 2` means at least two pods must remain Running at all times. During a node drain (whether from a cluster-autoscaler scale-in, a Karpenter consolidation, or a node group rolling upgrade), the eviction API checks all PDBs before evicting any pod. If evicting a pod would reduce the available count below `minAvailable`, the eviction is refused until a replacement pod becomes available elsewhere.

With `minReplicas: 3`, requiring 2 available at all times means at most 1 pod can be disrupted simultaneously. This prevents a scenario where two consecutive single-pod evictions could leave only 1 pod serving during overlapping drain operations. Node drains are serialised: the second eviction is blocked until the first pod has been rescheduled and reaches Ready — no deadlock occurs, just sequential progress. If the cluster needs to drain multiple nodes at once, the upgrade proceeds one pod at a time.

With `minReplicas: 3` and the RollingUpdate strategy's `maxUnavailable: 0`, the PDB is a secondary enforcement layer — the Deployment's update strategy already prevents capacity from dropping during rolling image updates. The PDB governs node-level disruptions (drains, consolidations, upgrades) that happen outside the Deployment controller's scope.

---

### Ingress

**Template**: `templates/ingress.yaml`  
**Created when**: `ingress.enabled = true` (default: false; cloud overlays set it to true)

```yaml
# Rendered with cloud overlay defaults
apiVersion: networking.k8s.io/v1
spec:
  ingressClassName: nginx
  rules:
    - host: <ingress.host>         # required; error at render time if absent
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sre-workload
                port:
                  number: 8080
```

The Ingress is disabled by default because `ingress.host` ŌĆö a per-customer, per-deployment value ŌĆö is required and there is no sensible default. The cloud overlays set `ingress.enabled: true` but leave `host` empty; the deployer must supply it via `--set ingress.host=...`. The template uses Helm's `required` function on both the `host` field and on the TLS `secretName`, which generates a clear error at render time if either is missing when it should be present.

`ingressClassName: nginx` routes the Ingress to the `ingress-nginx` controller installed by the k8s-platform module. The AWS overlay notes that `alb` is a valid alternative for customers who prefer native ALB integration. The GCP overlay similarly documents that GKE's Gateway API is an alternative.

`pathType: Prefix` with path `/` matches all requests and forwards them to the workload Service. The workload's catch-all router handles all paths, so no more specific path rules are needed.

**TLS.** When `ingress.tls.enabled = true`, a `tls:` block is added to the Ingress spec. The cloud overlays set `ingress.annotations["cert-manager.io/cluster-issuer"]: letsencrypt-prod` ŌĆö cert-manager watches Ingress resources for this annotation, creates a Certificate request to the named ClusterIssuer, completes the ACME HTTP-01 challenge through ingress-nginx, and writes the resulting certificate into the Secret named by `ingress.tls.secretName`. cert-manager is installed and the ClusterIssuers are created by the `modules/k8s-platform` Terraform module, not by this chart.

**Ingress vs Gateway API.** Ingress is the established routing mode supported by ingress-nginx (`ingressClassName: nginx`). The Gateway API mode (`gateway.enabled = true`) is the alternative for clusters running NGINX Gateway Fabric. The two modes are not run simultaneously ŌĆö the gateway overlays set `ingress.enabled: false`.

---

### Gateway

**Template**: `templates/gateway.yaml`  
**Created when**: `gateway.enabled = true` AND `gateway.createGateway = true`  
**Requires**: NGINX Gateway Fabric installed in the cluster (`install_nginx_gateway_fabric = true` in Terraform); Gateway API CRDs (installed automatically by the NGF Helm chart)

```yaml
# Rendered with gateway overlay + TLS defaults
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  gatewayClassName: nginx       # GatewayClass created by NGF
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      hostname: <gateway.host>  # required; error at render time if absent
      allowedRoutes:
        namespaces:
          from: Same
    - name: https               # only present when gateway.tls.enabled=true
      port: 443
      protocol: HTTPS
      hostname: <gateway.host>
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: <gateway.tls.secretName>  # cert-manager fills this
      allowedRoutes:
        namespaces:
          from: Same
```

This chart follows the **per-workload Gateway** pattern: each Helm release owns its own Gateway resource rather than attaching to a shared cluster-level Gateway. This keeps cert rotation, listener configuration, and load balancer lifecycle scoped to the individual workload, which is appropriate for a product that deploys into customer accounts where the existing Gateway topology is unknown.

`allowedRoutes.namespaces.from = Same` on both listeners restricts attachment to HTTPRoutes in the same namespace as the Gateway. This is the minimum required scope for a single-namespace deployment and prevents cross-namespace route injection.

**`gateway.createGateway = false`** is the alternative when a shared Gateway already exists in the cluster. With this option the chart creates only the HTTPRoute (and Certificate, if TLS is enabled); the shared Gateway is managed by the platform team. Set `gateway.parentRef.name` and optionally `gateway.parentRef.namespace` to identify the pre-existing Gateway.

---

### HTTPRoute

**Template**: `templates/httproute.yaml`  
**Created when**: `gateway.enabled = true`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  parentRefs:
    - name: sre-workload        # the Gateway created by this chart
      namespace: <release namespace>
      sectionName: https        # "http" when gateway.tls.enabled=false
  hostnames:
    - <gateway.host>
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: sre-workload
          port: 8080
```

The HTTPRoute attaches to the Gateway via `parentRefs` and routes all traffic for `gateway.host` to the workload Service on port 8080. The `sectionName` field pins the route to a specific listener: `https` when TLS is enabled (so the route only receives traffic that has completed the TLS handshake at the Gateway), `http` when TLS is disabled.

When `gateway.createGateway = false`, `parentRefs` points to `gateway.parentRef.name` in `gateway.parentRef.namespace` (defaulting to the release namespace). `sectionName` is only included when `gateway.parentRef.sectionName` is set ŌĆö omitting it attaches the route to all matching listeners, which is correct for pre-existing shared Gateways where the operator controls listener selection.

**NetworkPolicy compatibility.** The existing NetworkPolicy allows ingress on port 8080 from `from: []` (any in-cluster source). NGF routes traffic from its own pods directly to the workload pods via the Service. Because NGF pods are in a different namespace (`nginx-gateway`), the `from: []` rule is what allows this ŌĆö no additional NetworkPolicy changes are needed for Gateway API mode.

---

### Certificate

**Template**: `templates/certificate.yaml`  
**Created when**: `gateway.enabled = true` AND `gateway.tls.enabled = true`  
**Requires**: cert-manager installed in the cluster with a ClusterIssuer or Issuer matching `gateway.tls.issuerName`

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
spec:
  secretName: <gateway.tls.secretName>  # defaults to <fullname>-tls
  issuerRef:
    name: letsencrypt-prod              # gateway.tls.issuerName
    kind: ClusterIssuer                 # gateway.tls.issuerKind
  dnsNames:
    - <gateway.host>
```

cert-manager watches Certificate resources, creates a CertificateRequest to the named ClusterIssuer, completes the ACME challenge, and writes the issued certificate into the named Secret. The Gateway's HTTPS listener references that same Secret in its `tls.certificateRefs`. This is the Gateway API equivalent of the Ingress annotation approach ŌĆö both result in cert-manager provisioning a Secret that serves the TLS connection, but the trigger is different: an explicit Certificate resource here rather than watching an annotation on the Ingress object.

**Why not the Ingress annotation approach for Gateway.** cert-manager's annotation-driven certificate provisioning (`cert-manager.io/cluster-issuer` on the resource) is stable for Ingress but requires an experimental feature gate on cert-manager for Gateway objects. The explicit Certificate resource works with any cert-manager version Ōēź 1.14 and does not require feature gate configuration.

**Local testing.** The `letsencrypt-prod` and `letsencrypt-staging` ClusterIssuers require a public endpoint for ACME HTTP-01 challenges. For local kind clusters, replace `issuerName` with a `selfSigned` ClusterIssuer (no challenge required, cert issues immediately). See the prerequisite instructions for the exact commands.

---

### NetworkPolicy

**Template**: `templates/networkpolicy.yaml`  
**Created when**: `networkPolicy.enabled = true` (default)

```yaml
apiVersion: networking.k8s.io/v1
spec:
  podSelector:
    matchLabels: <selector for this Deployment's pods>
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from: []          # any in-cluster source
      ports:
        - protocol: TCP
          port: 8080
    # + networkPolicy.extraIngress entries
  egress:
    - to: []            # any destination
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # + networkPolicy.extraEgress entries
```

Declaring both `policyTypes: [Ingress, Egress]` makes the NetworkPolicy fully bilateral: the default is deny for both ingress and egress, and only the explicitly listed rules are allowed.

**Ingress rule: `from: []` on port 8080.** An ingress rule with an empty `from` list matches all sources ŌĆö any pod in any namespace in the cluster can reach port 8080. The template comment notes this should be tightened: in a real deployment, you would restrict ingress to the ingress-nginx namespace using a `namespaceSelector`. The broad default is chosen so the chart does not silently break ingress routing on first install for customers who haven't planned their namespace topology. The `extraIngress` field lets operators narrow this without modifying the template.

**Egress rule: DNS on port 53.** Every pod needs DNS for service discovery (`kubernetes.default.svc.cluster.local`), for pulling images (though the kubelet handles that, not the pod), and for any external hostname the workload resolves. This rule allows UDP and TCP DNS to any destination. TCP DNS is included alongside UDP because DNS responses larger than 512 bytes fall back to TCP; omitting TCP DNS causes subtle failures with DNSSEC-enabled resolvers or large DNS responses.

The policy does **not** include a default egress rule for port 8080 back to the internet, for arbitrary database ports, or for any other application-specific traffic. Everything beyond DNS is denied by default. Operators add `extraEgress` rules for whatever the workload actually needs to reach (API calls, databases, cloud metadata servers, etc.).

**CNI requirement.** NetworkPolicy resources are only enforced by a CNI plugin that implements the Kubernetes NetworkPolicy spec. The default CNI on `kind` (kindnet) does not enforce NetworkPolicy ŌĆö policies exist in the API server but have no effect on actual traffic. The README documents using Calico on `kind` for local testing. On EKS with the VPC CNI, AWS VPC CNI Calico or Cilium can be installed for enforcement. On GKE, NetworkPolicy enforcement is built in when the feature is enabled on the cluster.

---

### ServiceMonitor

**Template**: `templates/servicemonitor.yaml`  
**Created when**: `serviceMonitor.enabled = true` (default: false)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  selector:
    matchLabels: <selector for this Deployment's pods>
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

The ServiceMonitor is a Prometheus Operator CRD. When enabled, Prometheus (configured by the Operator to watch ServiceMonitor resources) adds this endpoint to its scrape targets and collects metrics every 30 seconds.

This resource is opt-in because it requires the Prometheus Operator to be installed in the cluster. If enabled without the Operator, the manifest is accepted by the API server (if the CRD was ever installed) but has no effect. Neither the chart nor the k8s-platform module installs the Prometheus Operator.

The scrape path `/metrics` and port `http` (8080) are the correct configuration format. Two preconditions must hold before enabling:

1. **Prometheus Operator CRDs must be installed.** The `ServiceMonitor` CRD (`monitoring.coreos.com/v1`) does not exist in a cluster unless the Prometheus Operator (or kube-prometheus-stack) has been deployed. Applying the chart with `serviceMonitor.enabled = true` before the CRD exists fails with a "no matches for kind ServiceMonitor" error.
2. **The image must expose a real Prometheus `/metrics` endpoint.** The confirmed behaviour of the current image is that port 8080 is a catch-all returning HTTP 200 for every path — a scrape of `/metrics` succeeds but returns no Prometheus-format content. If the application exposes metrics on a dedicated port, add a second container port and point `serviceMonitor.port` at it before enabling.

---

## Template helpers (`_helpers.tpl`)

The helpers file defines five named templates used across all resource templates.

### `sre-workload.name`

Returns the chart name with an optional override via `nameOverride`. Truncated to 63 characters (Kubernetes label value limit) with trailing hyphens removed.

### `sre-workload.fullname`

Generates the name for all created resources. The logic prevents doubling:

- If `fullnameOverride` is set, use it directly.
- Otherwise, if the release name already contains the chart name (e.g., `helm install sre-workload .`), use just the release name.
- Otherwise, combine release name and chart name (`<release>-sre-workload`).

This prevents names like `sre-workload-sre-workload` when the release and chart names are identical.

### `sre-workload.labels`

Common labels applied to all resources:

| Label | Value | Purpose |
|---|---|---|
| `helm.sh/chart` | `sre-workload-0.1.0` | Chart identity for Helm tooling |
| `app.kubernetes.io/name` | `sre-workload` | Application name |
| `app.kubernetes.io/instance` | `<release-name>` | Release identity ŌĆö distinguishes multiple installs of the same chart |
| `app.kubernetes.io/version` | `latest` | Application version from `appVersion` |
| `app.kubernetes.io/managed-by` | `Helm` | Ownership marker |

### `sre-workload.selectorLabels`

A subset of common labels used in `selector.matchLabels` and `podSelector.matchLabels`:

```
app.kubernetes.io/name: sre-workload
app.kubernetes.io/instance: <release-name>
```

Selector labels are intentionally a **subset** of common labels ŌĆö the `version` label is excluded. If a version label were included in selectors, a chart upgrade that changes the `appVersion` would change the selector, which Kubernetes rejects: Deployment selectors are immutable after creation. Keeping version out of selectors means upgrades only update the pod template, not the selector.

### `sre-workload.serviceAccountName`

Returns the ServiceAccount name the Deployment should use:

1. If `serviceAccount.create = true` and `serviceAccount.name` is set, use `serviceAccount.name`.
2. If `serviceAccount.create = true` and `serviceAccount.name` is empty, use `sre-workload.fullname`.
3. If `serviceAccount.create = false` and `serviceAccount.name` is set, use `serviceAccount.name`.
4. If `serviceAccount.create = false` and `serviceAccount.name` is empty, use `"default"`.

### `sre-workload.probeSpec`

A shared helper that renders the probe mechanism block plus timing parameters. Called with:

```
(dict "probe" .Values.probes.<startup|readiness|liveness> "root" . "path" <path>)
```

The probe type is controlled by `probes.type`:
- `http` ŌåÆ renders `httpGet: { path: <path>, port: http }`
- `tcp` ŌåÆ renders `tcpSocket: { port: http }`
- `exec` ŌåÆ renders `exec: { command: ["/bin/sh", "-c", "exit 0"] }` (placeholder, intended to be replaced with a real command)

Centralising probe rendering in one helper means switching the probe mechanism for all three probes is a single values change (`probes.type: tcp`) rather than editing three separate YAML blocks in the Deployment. The timing parameters (`initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`) are rendered from the per-probe values, with optional fields (`initialDelaySeconds`, `timeoutSeconds`) only rendered when non-zero to avoid unnecessary YAML noise.

---

## JSON schema validation (`values.schema.json`)

Helm validates user-supplied values against this schema during `helm install`, `helm upgrade`, and `helm lint`. Errors are reported before any resources are applied to the cluster.

### Required fields

The schema declares three top-level objects as required: `image`, `service`, and `probes`. Within each:

- `image.repository` and `image.tag` must be non-empty strings.
- `service.port` and `service.targetPort` must be integers in the range 1ŌĆō65535.
- `probes.type`, `probes.path`, and `probes.readyPath` must be present.

### Enum constraints

- `image.pullPolicy` must be one of `Always`, `IfNotPresent`, `Never` ŌĆö the only values Kubernetes accepts.
- `service.type` must be one of `ClusterIP`, `NodePort`, `LoadBalancer`.
- `probes.type` must be one of `http`, `tcp`, `exec` ŌĆö the three mechanisms the helper renders.

### Conditional validation

```json
"if": { "properties": { "enabled": { "const": true } } },
"then": { "required": ["host"] }
```

The same conditional pattern applies to both `ingress` and `gateway`: when `enabled = true`, `host` becomes a required field. This is enforced at two levels — by the JSON schema at `helm lint` / `helm install` time, and by the `required` template function in the respective template at render time. Both guards produce errors before any resources are applied.

The `gateway.tls.issuerKind` field has an additional enum constraint: only `ClusterIssuer` and `Issuer` are accepted. These are the two cert-manager issuer resource types; any other value would be accepted by the Kubernetes API but silently ignored by cert-manager.

### `minLength: 1` on host fields

Both `ingress.host` and `gateway.host` carry a `minLength: 1` constraint in addition to the `required` conditional. The `required` keyword prevents the field from being absent when `enabled = true`, but without `minLength: 1` an empty string (`""`) passes schema validation and reaches the template, where it renders a structurally valid but functionally useless Ingress or HTTPRoute with a blank hostname. `minLength: 1` catches this at `helm lint` / `helm install` time before any resource is applied.

### `serviceAccount.automountToken`

Validated as a boolean. The schema does not enforce a default value ŌĆö that lives in `values.yaml` ŌĆö but it prevents non-boolean values (strings like `"false"`, integers) from silently passing through and being misinterpreted by the Kubernetes API.

---

## Cloud overlay reference

Four overlays are provided. The `values-aws.yaml` and `values-gcp.yaml` overlays use the Ingress routing mode (ingress-nginx). The `values-aws-gateway.yaml` and `values-gcp-gateway.yaml` overlays use the Gateway API routing mode (NGINX Gateway Fabric). Choose one pair per deployment.

### `values-aws.yaml`

```yaml
serviceAccount:
  # Supply via --set only if the workload needs AWS API access:
  #   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN>
  annotations: {}

storageClassName: gp3

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    enabled: true
    secretName: sre-workload-tls

nodeSelector:
  kubernetes.io/os: linux
```

**`serviceAccount.annotations`**: Empty by default. Set `eks.amazonaws.com/role-arn` at deploy time only when the workload needs AWS API access. The EKS pod identity webhook reads this annotation and injects `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` into all pods running under the ServiceAccount. The actual ARN comes from the Terraform `modules/irsa` output for the workload's IRSA role. An empty-string value for the annotation key is not pre-seeded in the overlay — it creates no IAM binding and gives a false impression that one exists.

**`cert-manager.io/cluster-issuer: letsencrypt-prod`**: cert-manager watches Ingress resources for this annotation. When found, it creates a CertificateRequest to the named ClusterIssuer, completes the ACME HTTP-01 challenge through ingress-nginx, and writes the resulting certificate into `sre-workload-tls`. The ClusterIssuers are created by `modules/k8s-platform` when `acme_email` is set. Use `letsencrypt-staging` to validate ACME configuration before switching to `letsencrypt-prod`.

**`storageClassName: gp3`**: Sets the storage class for any PersistentVolumeClaim the chart creates (currently none ŌĆö the workload is assumed stateless). Present to ensure that if a PVC is added in future, it uses gp3 rather than the older gp2 default.

**`nodeSelector: kubernetes.io/os: linux`**: Ensures pods are scheduled only on Linux nodes. Present because EKS clusters can have Windows node pools, and the container image is Linux-only.

### `values-gcp.yaml`

```yaml
serviceAccount:
  # Supply via --set only if the workload needs GCP API access:
  #   --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL>
  annotations: {}

storageClassName: standard-rwo

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    enabled: true
    secretName: sre-workload-tls

nodeSelector:
  kubernetes.io/os: linux
```

**`serviceAccount.annotations`**: Empty by default. Set `iam.gke.io/gcp-service-account` at deploy time only when the workload needs GCP API access. GKE's metadata proxy reads this annotation and issues GCP access tokens for the named Google Service Account to pods running under this ServiceAccount. The GSA email comes from the Terraform `modules/workload-identity` output. An empty-string value for the annotation key is not pre-seeded in the overlay — it creates no Workload Identity binding and gives a false impression that one exists.

**`storageClassName: standard-rwo`**: GKE's `standard-rwo` (Read-Write Once) storage class provisions `pd-ssd`-backed Persistent Disks with `ReadWriteOnce` access mode.

**`cert-manager.io/cluster-issuer`**: Same annotation-driven cert-manager flow as the AWS overlay. The ACME HTTP-01 challenge is completed through ingress-nginx identically on GKE.

### `values-aws-gateway.yaml`

```yaml
serviceAccount:
  # Supply via --set only if the workload needs AWS API access:
  #   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN>
  annotations: {}

storageClassName: gp3

ingress:
  enabled: false

gateway:
  enabled: true
  className: nginx
  host: ""           # set via --set gateway.host=sre.example.com
  createGateway: true
  tls:
    enabled: true
    secretName: ""   # defaults to <fullname>-tls
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer

nodeSelector:
  kubernetes.io/os: linux
```

Install with:
```bash
helm install sre-workload . \
  -f values.yaml -f values-aws-gateway.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ARN> \
  --set gateway.host=sre.example.com
```

**`ingress.enabled: false`**: Disables the Ingress resource so both routing modes are not active simultaneously.

**`gateway.className: nginx`**: Matches the `GatewayClass` named `nginx` created by NGINX Gateway Fabric (`install_nginx_gateway_fabric = true` in Terraform). The Gateway API CRDs are installed automatically by the NGF Helm chart.

**`gateway.tls.issuerName: letsencrypt-prod`**: The chart creates an explicit `cert-manager.io/v1 Certificate` resource (not an annotation on the Gateway). cert-manager provisions the TLS Secret directly; the Gateway's HTTPS listener references that Secret in `tls.certificateRefs`.

### `values-gcp-gateway.yaml`

```yaml
serviceAccount:
  # Supply via --set only if the workload needs GCP API access:
  #   --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL>
  annotations: {}

storageClassName: standard-rwo

ingress:
  enabled: false

gateway:
  enabled: true
  className: nginx
  host: ""
  createGateway: true
  tls:
    enabled: true
    secretName: ""
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer

nodeSelector:
  kubernetes.io/os: linux
```

Install with:
```bash
helm install sre-workload . \
  -f values.yaml -f values-gcp-gateway.yaml \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL> \
  --set gateway.host=sre.example.com
```

**GKE-native Gateway controller.** GKE ships its own Gateway API implementation (`gke-l7-global-external-managed` GatewayClass) which integrates with Google Cloud Load Balancers natively. To use it instead of NGINX Gateway Fabric, set `gateway.className` to the appropriate GKE GatewayClass name — no other chart changes are required. The NGF-based overlay is the default to keep routing behaviour consistent between AWS and GCP deployments.

---

## Default values reference

| Key | Default | Overlay (AWS) | Overlay (GCP) |
|---|---|---|---|
| `image.repository` | `ghcr.io/e2b-dev/sre-interview` | ŌĆö | ŌĆö |
| `image.tag` | `latest` | ŌĆö | ŌĆö |
| `image.pullPolicy` | `IfNotPresent` | ŌĆö | ŌĆö |
| `replicaCount` | `3` | ŌĆö | ŌĆö |
| `service.type` | `ClusterIP` | ŌĆö | ŌĆö |
| `service.port` | `8080` | ŌĆö | ŌĆö |
| `probes.type` | `http` | ŌĆö | ŌĆö |
| `probes.path` | `/healthz` | ŌĆö | ŌĆö |
| `probes.readyPath` | `/readyz` | ŌĆö | ŌĆö |
| `probes.startup.failureThreshold` | `30` | ŌĆö | ŌĆö |
| `probes.startup.periodSeconds` | `5` | ŌĆö | ŌĆö |
| `probes.readiness.periodSeconds` | `10` | ŌĆö | ŌĆö |
| `probes.liveness.periodSeconds` | `15` | ŌĆö | ŌĆö |
| `resources.requests.cpu` | `100m` | ŌĆö | ŌĆö |
| `resources.requests.memory` | `128Mi` | ŌĆö | ŌĆö |
| `resources.limits.cpu` | `500m` | ŌĆö | ŌĆö |
| `resources.limits.memory` | `512Mi` | ŌĆö | ŌĆö |
| `autoscaling.enabled` | `true` | ŌĆö | ŌĆö |
| `autoscaling.minReplicas` | `3` | ŌĆö | ŌĆö |
| `autoscaling.maxReplicas` | `10` | ŌĆö | ŌĆö |
| `autoscaling.targetCPUUtilizationPercentage` | `70` | ŌĆö | ŌĆö |
| `autoscaling.targetMemoryUtilizationPercentage` | `80` | ŌĆö | ŌĆö |
| `podDisruptionBudget.minAvailable` | `2` | ŌĆö | ŌĆö |
| `rollout.maxUnavailable` | `0` | ŌĆö | ŌĆö |
| `rollout.maxSurge` | `25%` | ŌĆö | ŌĆö |
| `topologySpread.topologyKey` | `topology.kubernetes.io/zone` | ŌĆö | ŌĆö |
| `topologySpread.whenUnsatisfiable` | `ScheduleAnyway` | ŌĆö | ŌĆö |
| `serviceAccount.automountToken` | `false` | ŌĆö | ŌĆö |
| `serviceAccount.annotations` | `{}` | `{}` (supply ARN via `--set` only when needed) | `{}` (supply GSA email via `--set` only when needed) |
| `podSecurityContext.runAsUser` | `65532` | ŌĆö | ŌĆö |
| `securityContext.readOnlyRootFilesystem` | `true` | ŌĆö | ŌĆö |
| `networkPolicy.enabled` | `true` | — | — |
| `ingress.enabled` | `false` | `true` | `true` |
| `ingress.className` | `nginx` | `nginx` | `nginx` |
| `ingress.tls.enabled` | `false` | `true` | `true` |
| `ingress.tls.secretName` | `""` | `sre-workload-tls` | `sre-workload-tls` |
| `gateway.enabled` | `false` | `false` (gateway overlay: `true`) | `false` (gateway overlay: `true`) |
| `gateway.className` | `nginx` | — | — |
| `gateway.createGateway` | `true` | — | — |
| `gateway.tls.enabled` | `false` | — (gateway overlay: `true`) | — (gateway overlay: `true`) |
| `gateway.tls.issuerName` | `letsencrypt-prod` | — | — |
| `gateway.tls.issuerKind` | `ClusterIssuer` | — | — |
| `storageClassName` | `""` | `gp3` | `standard-rwo` |
| `nodeSelector` | `{}` | `kubernetes.io/os: linux` | `kubernetes.io/os: linux` |
| `serviceMonitor.enabled` | `false` | — | — |
