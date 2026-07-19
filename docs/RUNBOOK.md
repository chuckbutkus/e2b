# sre-workload Runbook

Operational reference for the `sre-workload` Helm chart running on AWS EKS or GCP GKE.

---

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| `helm` | 3.x | Deploy / upgrade the chart |
| `kubectl` | matches cluster | Inspect and debug |
| `aws` CLI | 2.x | EKS kubeconfig, token fetch |
| `gcloud` CLI | latest | GKE kubeconfig |
| `terraform` | ≥ 1.5 | Infra changes |

**kubeconfig**: use the `configure_kubectl` Terraform output after provisioning:
```bash
# AWS
aws eks update-kubeconfig --name <cluster-name> --region <region>

# GCP
gcloud container clusters get-credentials <cluster-name> --region <region> --project <project-id>
```

---

## Deploy / Upgrade the Workload

```bash
# First install — AWS
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-aws.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN> \
  --set ingress.host=<your-hostname> \
  --namespace default \
  --wait --timeout 5m

# First install — GCP
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-gcp.yaml \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<GSA_EMAIL> \
  --set ingress.host=<your-hostname> \
  --namespace default \
  --wait --timeout 5m

# Upgrade (change --install to upgrade; same flags)
helm upgrade sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-aws.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN> \
  --set ingress.host=<your-hostname> \
  --namespace default \
  --wait --timeout 5m
```

`--wait` blocks until all pods are Ready and the rollout is complete. If the upgrade does not converge within the timeout, Helm marks it as failed but does **not** automatically roll back — see [Rollback](#rollback) below.

---

## Verify Deployment Health

```bash
# Pod status (should all be Running, all containers Ready)
kubectl get pods -l app.kubernetes.io/name=sre-workload

# Rollout status
kubectl rollout status deployment/sre-workload

# Endpoint reachability (from within the cluster)
kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://sre-workload:8080/healthz

# HPA state (TARGETS should be below the threshold, REPLICAS ≥ minReplicas)
kubectl get hpa sre-workload

# PodDisruptionBudget — DISRUPTIONS ALLOWED should be ≥ 1 if replicas > minAvailable
kubectl get pdb sre-workload

# Recent events (node scheduling, image pull, probe failures)
kubectl describe deployment sre-workload | tail -30
kubectl get events --sort-by=.metadata.creationTimestamp | grep sre-workload
```

---

## Scaling

### Horizontal pod autoscaling

HPA is on by default (CPU 70%, memory 80%). Current status:

```bash
kubectl get hpa sre-workload -w
```

To temporarily override the replica count (e.g. pre-scale before a known event):

```bash
kubectl patch hpa sre-workload -p '{"spec":{"minReplicas":5}}'
# restore afterwards
kubectl patch hpa sre-workload -p '{"spec":{"minReplicas":3}}'
```

To permanently change limits, update `values.yaml` and re-run `helm upgrade`.

### Node autoscaling (AWS — cluster-autoscaler)

```bash
# Check cluster-autoscaler logs for scaling decisions
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=50

# Check whether any pods are Pending (triggers scale-out)
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

### Node autoscaling (AWS — Karpenter, if enabled)

```bash
# Node provisioning activity
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50

# Nodes Karpenter has provisioned
kubectl get nodes -l karpenter.sh/nodepool=default
```

### Node autoscaling (GCP)

GKE's native node-pool autoscaler requires no separate controller. Monitor via:

```bash
gcloud container clusters describe <cluster-name> --region <region> \
  --format='value(nodePools[].autoscaling)'
```

---

## Rollback

### Helm rollback (application only)

```bash
# List release history
helm history sre-workload

# Roll back to the previous revision
helm rollback sre-workload

# Roll back to a specific revision
helm rollback sre-workload <REVISION>
```

Helm rollback re-applies the previous chart revision. Because `strategy.maxUnavailable = 0`, traffic is not interrupted while the rollback deploys.

### Terraform rollback (infrastructure)

Terraform is stateful — "rollback" means reverting the `.tf` source and re-applying:

```bash
git revert <bad-commit>
cd terraform/envs/<env>
terraform plan   # verify the diff is only the revert
terraform apply
```

For the Helm chart installed via `modules/k8s-platform`, use `helm rollback` (above) rather than re-applying Terraform, as Terraform tracks the Helm release by chart version, not by release history.

---

## Common Failure Modes

### `ImagePullBackOff`

The image `ghcr.io/e2b-dev/sre-interview:latest` is public. If this error appears:

1. Confirm network egress from nodes reaches `ghcr.io` (check NAT gateway / Cloud NAT logs).
2. If the image has been moved to a private registry, add an `imagePullSecrets` entry:
   ```bash
   kubectl create secret docker-registry ghcr-pull-secret \
     --docker-server=ghcr.io \
     --docker-username=<github-user> \
     --docker-password=<pat>
   helm upgrade sre-workload ... --set imagePullSecrets[0].name=ghcr-pull-secret
   ```

### Pods stuck in `Pending`

```bash
kubectl describe pod <pod-name> | grep -A10 Events
```

Common causes:
- **Insufficient node capacity**: cluster-autoscaler / Karpenter should add nodes within ~60 s. If not, check autoscaler logs (see Scaling section).
- **Topology spread unsatisfiable**: if `topologySpread.whenUnsatisfiable = DoNotSchedule` and fewer zones are available than pods, pods will stay Pending. Switch to `ScheduleAnyway` (the default) or reduce `minReplicas`.
- **PodDisruptionBudget blocking drain**: if a node drain is in progress, PDB may temporarily hold pods. This resolves automatically once new pods are Ready.

### Liveness probe failures / crashlooping

```bash
kubectl logs <pod-name> --previous   # logs from the crashed container
kubectl describe pod <pod-name>      # probe failure messages in Events
```

The liveness probe hits `GET /healthz` on port 8080. The running image returns 200 for all paths, so a probe failure means the process has hung or exited, not that the endpoint returned an error.

### HPA not scaling

```bash
kubectl describe hpa sre-workload
```

`<unknown>` in the TARGETS column means metrics-server is not running or not serving data for the deployment. Verify:

```bash
kubectl top pods -l app.kubernetes.io/name=sre-workload
```

If `kubectl top` fails, check that the `metrics-server` Helm release is healthy in `kube-system`.

### Ingress not routing traffic

```bash
kubectl get ingress sre-workload
kubectl describe ingress sre-workload
```

- Confirm `ingress-nginx` is running: `kubectl get pods -n ingress-nginx`
- Confirm the ingress class matches: `kubectl get ingressclass`
- On AWS, the `ingress-nginx` controller's LoadBalancer Service should have an external IP/hostname within 2–3 minutes of the Helm install. If not, check the AWS Load Balancer creation in the EC2 console and inspect `ingress-nginx` controller logs.

---

## Cluster / Node Upgrade Notes

EKS and GKE handle node upgrades differently:

**EKS managed node groups**: set `update_config.max_unavailable = 1` (already configured). Upgrade via Terraform by bumping `kubernetes_version` and applying. EKS drains nodes one at a time; the PodDisruptionBudget prevents the workload from going below `minAvailable` during drain.

**GKE node pools**: `management.auto_upgrade = true` (already configured). GKE schedules upgrades automatically within the release channel's maintenance window. The `upgrade_settings { max_surge = 1, max_unavailable = 0 }` block ensures zero workload downtime.

After any node upgrade, verify:
```bash
kubectl get nodes   # all nodes Ready, version matches target
kubectl get pods -l app.kubernetes.io/name=sre-workload  # all Running
```
