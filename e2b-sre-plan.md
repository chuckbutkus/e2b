# E2B SRE Assignment — Delivery Plan

**Goal:** Production-ready, multi-cloud Kubernetes deployment of `ghcr.io/e2b-dev/sre-interview:latest`, delivered as reusable Terraform + Helm, deployable into a customer's existing infra or provisioned fresh, on at least AWS + GCP (Azure as stretch).

---

## 1. Scope & Design Principles

- **Two-provider minimum**: AWS (EKS) + GCP (GKE) as primary targets. Azure (AKS) structured as a drop-in third module if time allows — same interface, so it's "cheap" to add later.
- **Bring-your-own vs create-for-me**: every layer (VPC, cluster, node pools) must support both "customer already has it, give me the IDs" and "provision it from scratch." This is the single hardest requirement and drives the module design below.
- **Cloud-agnostic workload layer**: everything above "kubeconfig" (the Deployment, HPA, ingress, secrets) is pure Kubernetes/Helm and has zero cloud-specific code. Cloud differences are isolated entirely to the Terraform networking/cluster layer and to a thin per-cloud "glue" module (ingress controller class, storage class, IAM-for-pods mechanism).
- **State isolation per customer/environment**: remote backend per cloud, one state per logical environment (not one giant state).
- **Everything idempotent and re-runnable**: `terraform plan` produces no diff on a clean apply; Helm release is declarative.

---

## 2. Repository Layout

```
e2b-sre-deployment/
├── terraform/
│   ├── modules/
│   │   ├── network/
│   │   │   ├── aws/            # VPC, subnets, NAT, route tables (create path)
│   │   │   ├── gcp/            # VPC, subnets, Cloud NAT
│   │   │   └── existing/       # data-source-only lookups for BYO-VPC path
│   │   ├── cluster/
│   │   │   ├── aws-eks/
│   │   │   ├── gcp-gke/
│   │   │   └── existing/       # data-source lookups for BYO-cluster path
│   │   ├── node-pool/
│   │   │   ├── aws-eks/        # managed node group + Karpenter option
│   │   │   └── gcp-gke/
│   │   ├── irsa-or-workload-identity/   # per-cloud pod-identity wiring
│   │   └── k8s-platform/       # cloud-agnostic: ingress-nginx, cert-manager,
│   │                           # metrics-server, cluster-autoscaler CRDs — installed via helm_release from TF
│   ├── envs/
│   │   ├── aws-fresh/          # example: create everything (VPC+EKS)
│   │   ├── aws-existing-vpc/   # example: BYO VPC, create EKS
│   │   ├── gcp-fresh/
│   │   ├── gcp-existing-cluster/  # example: BYO GKE, TF just configures workload identity + platform addons
│   │   └── azure-fresh/        # stretch
│   └── backend-config/         # per-env backend.hcl (S3+DynamoDB / GCS)
├── helm/
│   └── sre-workload/           # the actual app chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-aws.yaml     # storageClass, ingressClassName overrides
│       ├── values-gcp.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── hpa.yaml
│           ├── pdb.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── networkpolicy.yaml
│           ├── serviceaccount.yaml
│           └── servicemonitor.yaml   # if Prometheus Operator present
├── ci/
│   ├── terraform-plan.yml      # per-PR plan on all envs, tflint, checkov
│   ├── terraform-apply.yml     # manual-approval apply
│   └── helm-lint-test.yml      # helm lint + kubeconform + chart-testing
└── docs/
    ├── ARCHITECTURE.md
    ├── RUNBOOK.md
    ├── ONBOARDING.md           # "customer wants X" decision tree
    └── DR.md
```

---

## 3. Terraform Design (the multi-cloud part)

### 3.1 Interface pattern
Each `modules/network/*` and `modules/cluster/*` implementation exposes an **identical output contract** regardless of cloud:

```
outputs: vpc_id, subnet_ids (list), cluster_endpoint, cluster_ca_cert,
         cluster_name, cluster_oidc_issuer_url, region
```

The `envs/*` root modules are then just composition: pick network impl + cluster impl + node-pool impl based on a couple of booleans (`create_vpc`, `create_cluster`), pass outputs of one into inputs of the next. This is the standard "swap the module source, keep the interface" pattern — no dynamic provider selection needed since each env is its own root module with a fixed provider block. That keeps things boring and debuggable versus trying to build one root module that conditionally targets multiple clouds (fragile, hard to plan/read).

### 3.2 BYO vs create-for-me
Handled via `create_vpc` / `create_network` and `create_cluster` variables per env:
- `create_vpc = true` → `modules/network/aws` (or gcp) provisions new VPC/subnets/NAT.
- `create_vpc = false` → `modules/network/existing` just does `data "aws_vpc"` / `data "google_compute_network"` lookups by ID/tag, validates required subnet tags (e.g., `kubernetes.io/role/elb`) exist, and fails plan early with a clear error if not.
- Same pattern for cluster: `create_cluster=false` uses `data "aws_eks_cluster"` / `data "google_container_cluster"` and skips straight to the platform-addons module.

This gives four realistic customer scenarios out of the same code, exercised as four `envs/` examples in the repo (not four copies of logic — envs are thin variable files).

### 3.3 State & backend
- AWS envs: S3 + DynamoDB lock, bucket per environment or key-prefixed, versioning + encryption on.
- GCP envs: GCS bucket with object versioning.
- One `backend-config/<env>.hcl` per environment, `terraform init -backend-config=...` — no hardcoded backend blocks (keeps modules reusable across customer accounts).
- Remote state outputs (cluster name, oidc issuer) consumed by CI to generate kubeconfig for the Helm stage — never by other Terraform state via `terraform_remote_state` across clouds (keeps blast radius contained).

### 3.4 Provider-specific concerns folded into the cluster module
- **AWS EKS**: managed node group by default; IRSA (IAM Roles for Service Accounts) via OIDC provider for pod-level AWS permissions (needed if the workload ever touches S3/Secrets Manager); aws-lb-controller if ALB ingress is chosen (default is ingress-nginx for portability, ALB documented as opt-in for customers who want native LB integration).
- **GCP GKE**: Workload Identity binding for pod-level GCP permissions; GKE Autopilot offered as an alternative env for customers who don't want to manage node pools at all (documented tradeoff: less control over autoscaling knobs, no DaemonSets for some agents).
- **Secrets**: External Secrets Operator with per-cloud backend (AWS Secrets Manager / GCP Secret Manager) — one Helm value flips the backend, workload never knows which cloud it's on.

### 3.5 IaC hygiene
- `tflint` + `checkov` (or `tfsec`) in CI, fail on high-severity.
- Every module has its own `README.md` (auto-generated with `terraform-docs`), `variables.tf` validated (`variable ... { validation {...} }` for things like CIDR format).
- Semantic versioning tags on the module repo if modules are consumed as a separate registry source later.

---

## 4. Kubernetes Workload Design

### 4.1 Deployment
- `strategy: RollingUpdate`, `maxUnavailable: 0`, `maxSurge: 25%` — zero-downtime by default given this is "shipped to a remote customer account" (safe default over speed).
- Resource `requests`/`limits` set (not left blank) — required for HPA and for the cluster autoscaler to size nodes correctly; values templated via `values.yaml`, sane defaults + documented sizing guidance in RUNBOOK.
- `securityContext`: non-root, read-only root filesystem where the image allows it, dropped capabilities, `seccompProfile: RuntimeDefault`.
- `topologySpreadConstraints` across zones (`topology.kubernetes.io/zone`) so a single-AZ/zone outage doesn't take the whole workload down.
- `PodDisruptionBudget` (`minAvailable: 1` or percentage) so cluster upgrades / node drains don't cause an outage.

### 4.2 Health checks
- `startupProbe` to protect slow-starting containers from being killed by liveness during boot.
- `readinessProbe` gates traffic (removes pod from Service endpoints).
- `livenessProbe` restarts hung containers.
- All three need real endpoints from the image — first implementation step is inspecting what `ghcr.io/e2b-dev/sre-interview:latest` actually exposes (HTTP port/path or exec-based check) rather than guessing; falls back to TCP socket probe if there's no HTTP health endpoint.

### 4.3 Autoscaling
- **HPA** on CPU/memory to start (`autoscaling/v2`), with a documented path to custom-metrics (Prometheus Adapter) if the workload's real bottleneck isn't CPU — I'd confirm this against the image's actual resource profile before committing to a metric.
- **Cluster/node autoscaling**: cluster-autoscaler (or Karpenter on AWS) so HPA scale-out isn't capped by static node count. This is provisioned by Terraform (module `k8s-platform`) since it needs cloud IAM permissions to call the provider API.

### 4.4 Rollout strategy beyond basic RollingUpdate
- Recommend **Argo Rollouts** (canary with automated analysis against a Prometheus SLO query, e.g., error-rate/latency) as the production-grade option, with plain `RollingUpdate` as the fallback for customers who don't want the extra CRDs/controller. Flag this as a scoping decision — I'd default to documenting both and shipping RollingUpdate as the baseline, canary as an add-on module, rather than forcing Argo Rollouts on every customer.

### 4.5 Networking / exposure
- `Service` (ClusterIP) + `Ingress` (ingress-nginx by default for portability across clouds; documented native alternatives: AWS ALB Ingress Controller, GCP `GCE`/Gateway API).
- `NetworkPolicy` default-deny ingress/egress with explicit allow rules — important since this is a customer-facing production workload, not a demo.
- TLS via cert-manager + customer-supplied issuer (ACME/Let's Encrypt or private CA), templated so BYO-cert customers can point to their own Secret instead.

### 4.6 Config & secrets
- `ConfigMap` for non-sensitive config, mounted or env-injected via Helm values.
- Secrets never in Helm values/state — External Secrets Operator pulling from cloud secret manager, as noted above.

---

## 5. Packaging / Product Considerations

Since this ships as part of the product offering, not a one-off:
- **Helm chart is the customer-facing unit** for the workload; Terraform modules are the customer-facing unit for infra. Both need semantic versioning and a CHANGELOG.
- **Decision tree in ONBOARDING.md**: a short flowchart customer-facing SEs can use — "Do you have a VPC? Do you have a cluster? Which cloud?" → which `envs/` example to copy and which vars to fill in.
- **Values schema validation** (`values.schema.json` on the Helm chart) so bad customer input fails fast with a clear message instead of a cryptic template error.
- **No hardcoded account IDs/project IDs/regions anywhere** — everything customer-specific is a variable with no default (forces explicit input rather than silently deploying to the wrong place).

---

## 6. Observability & Operations

- Metrics: `metrics-server` (HPA dependency) + optional Prometheus Operator `ServiceMonitor` in the chart, gated behind a values flag (don't force a Prometheus install on customers who have their own).
- Logging: stdout/stderr only from the container (12-factor), customer's existing log pipeline (CloudWatch/Cloud Logging/whatever they run) picks it up — documented, not built, since this is customer-environment-dependent.
- `RUNBOOK.md`: rollout/rollback commands, how to read HPA status, common failure modes (ImagePullBackOff against `ghcr.io` — note private registry auth via `imagePullSecrets` if the image isn't public), scaling procedure, DR/backup notes if the workload is stateful (needs confirming against the image).

---

## 7. Testing Strategy

**No live AWS/GCP testing required for this assignment** — validation is `kind` + static analysis, with a written "what changes on real cloud" section instead of an actual cloud run. This changes scope favorably: the Kubernetes/Helm layer can be fully built and verified, and Terraform validated for correctness/plan-ability, without ever needing cloud credentials or spend.

- **Terraform**: `terraform validate` + `terraform plan` against both AWS and GCP envs. Plans reviewed by inspection; structure modules so `fmt`/`tflint`/`checkov` catch correctness issues without a real backend or credentials. No `terraform apply` against a real account.
- **Kubernetes/Helm** — this is where testing is real and complete:
  - `helm lint` + `helm template` rendered against every `values-*.yaml` combination, checked with `kubeconform`/`kubeval`.
  - Actual `kind` cluster: install ingress-nginx, metrics-server, cert-manager (self-signed issuer), then `helm install` the chart for real.
  - Verify against `kind`: pod reaches Ready via the probes, Service/Ingress route traffic end-to-end, HPA object created and reporting metrics (scale-up forced with a synthetic load generator), PDB blocks a simulated `kubectl drain`, rolling update produces zero dropped requests under load during rollout.
  - `NetworkPolicy` behavior verified with a scratch pod confirming default-deny actually blocks unlisted traffic — note that `kind`'s default CNI (kindnet) does **not** enforce NetworkPolicy, so I'd swap in Calico for the `kind` cluster specifically to make this test meaningful, and call that out as a test-harness detail rather than a production concern.

### "What would be done differently on real AWS/GCP" — `docs/CLOUD-DIFFERENCES.md`
This becomes a first-class deliverable given the no-live-test constraint — it's where cloud-specific correctness reasoning lives that `kind` can't exercise directly:

- **Node-level identity**: IRSA (AWS) / Workload Identity (GCP) can't be exercised in `kind` — no real IAM. Document the OIDC trust policy shape and how it binds to the ServiceAccount.
- **LoadBalancer/Ingress**: `kind` has no cloud LB; ingress-nginx is exposed via NodePort/port-forward locally. Real clusters get an actual ALB/NLB (AWS) or Cloud Load Balancer (GCP) — different provisioning latency and health-check semantics to note.
- **StorageClass / PVs**: if the workload needs persistence, `kind` uses hostPath-backed dynamic provisioning; real clusters need `gp3`/`ebs-csi` (AWS) or `pd-ssd`/`pd-csi` (GCP), with different reattach behavior across AZs.
- **Cluster autoscaling**: `kind` is fixed-size — HPA scaling pods can be demonstrated, but node-level autoscale (cluster-autoscaler/Karpenter adding nodes for unschedulable pods) can only be described. Document expected behavior and required IAM permissions per cloud.
- **Multi-AZ / topology spread**: `kind` is effectively single-zone; real validation of `topologySpreadConstraints` and zonal PDB behavior needs an actual multi-AZ node group. Document expected node labels and how spread would be verified.
- **NetworkPolicy enforcement CNI**: production AWS (VPC CNI) and GCP (GKE Dataplane V2) enforce NetworkPolicy differently than vanilla `kind`; policy behavior should be re-verified post-deploy in each real environment.
- **Terraform apply blast radius**: plan-review substitutes for apply here; on a real account I'd run `apply` in an ephemeral/tagged sandbox first, with cost alerts and a teardown script, before ever touching a customer account.

---

## 8. Open Questions / First Steps

Before writing code, the two things that most change scope are:

1. **What does the image actually expose?** — port, health endpoint, statefulness, whether it needs persistent storage. I'd start by running the container locally and inspecting it rather than assuming.
2. **How rigorous does "at least two providers" need to be** — fully symmetric AWS+GCP with all four BYO/create permutations, or AWS as the fully-fleshed reference implementation with GCP as a thinner parallel? Given assignment time constraints, I'd default to: AWS fully implemented (all 2x2 create/existing permutations) + GCP implemented for the "create everything" path, with the BYO-GCP path stubbed/documented but not fully tested — and say so explicitly in the README rather than silently under-delivering.

### Suggested build order
1. Inspect the image; write the Helm chart and fully validate it against a local `kind` cluster (Calico-enabled, per the NetworkPolicy note above) — probes, HPA, PDB, rollout, ingress, all exercised for real here.
2. Build AWS network+cluster Terraform (fresh-VPC path) and validate with `plan`/`validate`/`tflint`/`checkov` — no apply.
3. Add AWS existing-VPC / existing-cluster variants (mostly `data` source swaps), same validation approach.
4. Port to GCP (network+cluster module), reuse the same Helm chart with `values-gcp.yaml`; same plan-only validation.
5. Write `docs/CLOUD-DIFFERENCES.md` alongside steps 2–4, capturing the specific things `kind` can't prove (IAM binding, LB provisioning, storage, node autoscale, multi-AZ) while the reasoning is fresh, not reconstructed later.
6. Write remaining docs (ARCHITECTURE, RUNBOOK, ONBOARDING) — they should reflect real decisions made in steps 1–5, not be reverse-engineered.
7. If time remains: Azure module, canary rollout add-on, custom-metrics HPA.

---

Want me to start on any piece of this concretely — e.g., the Helm chart templates, the AWS network/EKS Terraform module, or the ONBOARDING decision tree — or do a quick pass on how much time you actually have for this so I can help you prioritize the build order?
