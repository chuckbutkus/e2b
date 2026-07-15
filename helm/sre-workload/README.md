# sre-workload Helm chart

Deploys `ghcr.io/e2b-dev/sre-interview` to Kubernetes. Cloud-agnostic —
everything cloud-specific (pod identity annotation, StorageClass name,
ingress controller flavor) lives in `values-aws.yaml` / `values-gcp.yaml`,
never in `templates/`.

## Confirmed against the running image

Verified by running the container locally (`docker run --rm -p 18080:8080 -p 19090:9090 ...`):

- **Port 8080** is the app port. `/healthz`, `/readyz`, and even a nonexistent
  path (`/this-path-does-not-exist`) all return `200 ok` — this is a
  **catch-all**, not a differentiated health check. There's no meaningful
  distinction between liveness and readiness at the HTTP layer here; both
  probes just confirm the server is up and accepting connections. That's
  still a valid signal for Kubernetes (only the status code matters to a
  probe), just shallower than a "real" health check that verifies
  dependencies. Chart defaults (`service.port: 8080`, `probes.path: /healthz`,
  `probes.readyPath: /readyz`) are correct as originally guessed — no changes
  needed.
- **Port 9090** ("internal server", per the container's own startup log) is
  a real HTTP router — it returns proper `404`s rather than the 8080
  catch-all — but its purpose is unconfirmed: it isn't Prometheus `/metrics`
  and isn't the standard `net/http/pprof` mount either. **This port is
  intentionally not exposed anywhere in this chart** — no `Service` port, no
  `Ingress`, no `NetworkPolicy` allow rule. If its purpose becomes known
  later (check container docs/source, or `strings` the binary for route
  literals), it's a small addition: a second container port, a matching
  `Service` port, and a scoped `NetworkPolicy` egress/ingress rule rather
  than opening it broadly.

## Install

```bash
# AWS
helm install sre-workload . -f values.yaml -f values-aws.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN> \
  --set ingress.host=sre.customer-domain.example

# GCP
helm install sre-workload . -f values.yaml -f values-gcp.yaml \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL> \
  --set ingress.host=sre.customer-domain.example
```

## Testing locally with `kind`

`kind`'s default CNI (kindnet) does **not** enforce `NetworkPolicy` — using
it as-is would let the NetworkPolicy tests pass even if the policy were
broken. Use a Calico-enabled kind config:

```bash
cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
EOF
kind create cluster --config kind-config.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

Then install cluster prerequisites the chart assumes exist:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

# metrics-server needs --kubelet-insecure-tls on kind (self-signed certs)
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server -n kube-system \
  --set args={--kubelet-insecure-tls}
```

Lint and render before installing:

```bash
helm lint . -f values.yaml
helm template sre-workload . -f values.yaml --set ingress.enabled=false \
  | kubeconform -strict -summary
```

Install without a cloud overlay (plain `values.yaml` is enough for `kind`
smoke testing — no IRSA/Workload Identity annotations needed locally):

```bash
helm install sre-workload . -f values.yaml \
  --set ingress.enabled=true --set ingress.className=nginx \
  --set ingress.host=sre.local.test
```

Verify:

```bash
kubectl get pods -w                      # watch probes go Ready
kubectl get hpa                          # confirm HPA is reading metrics
kubectl describe pdb                     # confirm PDB is present
kubectl run scratch --rm -it --image=curlimages/curl -- \
  curl -m 3 http://sre-workload:8080/healthz   # NetworkPolicy allows in-cluster traffic
kubectl run scratch2 --rm -it --image=curlimages/curl -- \
  curl -m 3 http://some-other-service:1234     # (from a pod without the right labels, if testing stricter policies)
```

## Known scope limits (see `docs/CLOUD-DIFFERENCES.md` in the repo root)

- No live AWS/GCP deployment was performed for this assignment — validated
  via `kind` + `helm lint`/`template` + `kubeconform` only.
- IRSA / Workload Identity annotations are wired in but can't be functionally
  tested without a real cluster + real IAM.
- Assumes the workload is stateless (no PVC template yet).
- Port 9090 ("internal server") is unexposed and its purpose unconfirmed —
  see the note above.
