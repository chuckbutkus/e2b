# Terraform — Multi-cloud (AWS EKS + GCP GKE) module tree

## What's built vs. documented-only

| Scenario | Status |
|---|---|
| AWS: Fresh VPC + fresh EKS cluster | **Fully built** — `envs/aws-fresh` |
| AWS: Existing/BYO VPC + fresh EKS cluster | **Fully built** — `envs/aws-existing-vpc` |
| AWS: Existing VPC + existing/BYO EKS cluster | Module exists (`modules/cluster/aws-eks-existing`), no composed env yet — see below |
| GCP: Fresh VPC + fresh GKE cluster | **Fully built** — `envs/gcp-fresh` |
| GCP: Existing/BYO VPC or cluster | Modules exist (`modules/network/gcp-existing`, `modules/cluster/gcp-gke-existing`), no composed env yet — same status as the AWS BYO-cluster gap |
| Azure | Not started |

Being explicit about this rather than quietly shipping only the two envs and calling it "done": `modules/cluster/aws-eks-existing` is real code (data-source lookups + the assumed-existing-OIDC-provider documented in its own comments), just not yet composed into a full `envs/aws-existing-cluster` example. Wiring that up is mechanical — copy `envs/aws-existing-vpc`, swap `module "cluster"` to source `../../modules/cluster/aws-eks-existing`, drop the `node_pool` module entirely if the customer's existing node groups are already sized/managed, and skip straight to `k8s_platform`.

## Validation performed

**Migrated to Helm provider v3.** HashiCorp's v3 restructured `provider "helm" { kubernetes { ... } }` from a block into a nested object (`kubernetes = { ... }`, including its `exec` sub-config), and did the same to `set`/`set_list`/`set_sensitive` inside `helm_release` (now `set = [ { name = ..., value = ... }, ... ]` instead of repeated `set { }` blocks). All four `versions.tf`/`providers.tf` files now pin `hashicorp/helm` to `>= 3.0.0, < 4.0.0`, and every `helm_release` in `modules/k8s-platform` and `modules/node-pool/karpenter` was converted to the new syntax.

One thing I couldn't verify without a real provider install: the `exec` sub-attribute's conversion from block to nested object is inferred by analogy with the documented `kubernetes`/`registry`/`experiments` changes (HashiCorp's upgrade guide doesn't show an `exec` example explicitly). Worth confirming with `terraform validate` before trusting it fully — if `exec` turns out to still expect block syntax, that's a one-line fix (`exec { ... }` instead of `exec = { ... }`) in `envs/aws-fresh/providers.tf` and `envs/aws-existing-vpc/providers.tf`.


**No `terraform apply` was run against a real AWS account** (per the "no live cloud testing required" note). Validation in this environment was:
- Every `.tf` file's braces checked for balance (catches unclosed blocks).
- Every module's declared outputs cross-referenced against every `module.x.y` reference in the env root modules, by hand, to catch typos that would otherwise only surface at `terraform plan` time.
- No `terraform init`/`validate`/`plan` was run — this sandbox has no network access to download the `aws`/`kubernetes`/`helm`/`tls` providers. **Run these yourself before trusting this further:**

```bash
cd terraform/envs/aws-fresh
terraform init -backend-config=../../backend-config/aws-fresh.hcl
terraform validate
terraform plan   # will fail without real AWS credentials configured, but a
                  # clean plan (not a crash) confirms the graph is coherent
```

## Design notes worth knowing before you read the code

- **Output contract pattern**: `modules/network/aws` and `modules/network/existing` expose identical outputs (`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `azs`); same for `modules/cluster/aws-eks` and `modules/cluster/aws-eks-existing`. Envs pick which implementation to source without changing anything downstream.
- **BYO-VPC validation is fail-fast, not fail-silent**: `modules/network/existing` uses `postcondition` blocks on the subnet data sources to reject subnets missing the EKS discovery tags (`kubernetes.io/role/internal-elb`, etc.) or belonging to the wrong VPC, with an error message telling the operator exactly what's wrong — rather than a cryptic downstream EKS/LB failure minutes later.
- **API-mode access entries, not aws-auth ConfigMap**: the cluster module uses `access_config { authentication_mode = "API" }`, EKS's modern approach, so managed node groups get access entries auto-created without a chicken-and-egg Kubernetes-provider dependency on a cluster that isn't reachable yet.
- **`ignore_changes` on node group `desired_size`**: once cluster-autoscaler is running, it — not Terraform — owns replica count. Without this, every `terraform apply` would silently fight the autoscaler.
- **IRSA module is generic and reused twice**: once internally for cluster-autoscaler's own AWS permissions, and it's the same module a deployer would use to grant the *workload itself* AWS permissions if the image ever needs them (wire the resulting `role_arn` into the Helm chart's `serviceAccount.annotations."eks.amazonaws.com/role-arn"`, exactly like `values-aws.yaml` expects).
- **Karpenter, canary rollout, and Azure**: Azure and canary rollout remain out of scope for this pass. **Karpenter is now implemented** — see below.

## GCP (GKE)

`envs/gcp-fresh` mirrors `envs/aws-fresh`'s composition pattern (network → cluster → node pool → workload identity → platform addons), but several things are genuinely different on GCP rather than forced into an artificial AWS-shaped mold:

- **Network module output contract is intentionally NOT identical to AWS's.** `modules/network/gcp` outputs `network_self_link`/`subnetwork_self_link`/`pods_range_name`/`services_range_name` rather than `vpc_id`/`public_subnet_ids`/`private_subnet_ids` — GCP's VPC-native GKE model is one regional subnet plus two named secondary IP ranges (pods, services), not per-AZ public/private subnet pairs. Reusing the AWS names here would have hidden a real structural difference rather than represented it.
- **No separate OIDC-provider-registration step.** AWS's IRSA needs an explicit `aws_iam_openid_connect_provider` resource before any ServiceAccount can assume a role. GKE's Workload Identity pool (`<project_id>.svc.id.goog`) is a fixed, always-present per-project resource — `modules/workload-identity` (the GCP equivalent of `modules/irsa`) is correspondingly simpler: one GSA, project IAM role grants, and a single `google_service_account_iam_member` binding. No cluster module needs to create/expose an OIDC provider ARN the way `modules/cluster/aws-eks` does.
- **Node-pool autoscaling is native, not a separate controller.** `modules/node-pool/gcp-gke`'s `autoscaling { min_node_count, max_node_count }` block *is* the autoscaler — there's no GCP equivalent of installing cluster-autoscaler as a workload. `modules/k8s-platform` (shared, cloud-agnostic) is called with `install_cluster_autoscaler = false` in `envs/gcp-fresh/main.tf` for exactly this reason; ingress-nginx and metrics-server still get installed the same way on both clouds.
- **Bottlerocket has no GCP equivalent.** It's an AWS-specific AMI project. `modules/node-pool/gcp-gke`'s `image_type` is `COS_CONTAINERD` (Google's Container-Optimized OS — the closer analogue in spirit: minimal, purpose-built, container-focused) or `UBUNTU_CONTAINERD`. Don't read the Bottlerocket toggle on the AWS side as something with a GCP parallel.
- **Cluster module creates a private, VPC-native, Workload-Identity-enabled regional cluster** with a throwaway default node pool immediately removed (`remove_default_node_pool = true`) — the standard Terraform+GKE pattern to keep all real node pool state in `modules/node-pool/gcp-gke` instead of fighting the cluster resource over it, mirroring why the AWS node pool is a separate module from the EKS cluster module.
- **Provider auth uses `google_client_config`'s access token**, refreshed on every plan/apply, rather than an exec plugin — GCP's ecosystem doesn't have as clean a `aws eks get-token`-style plugin in common use for this, so the token-data-source pattern is the standard approach instead.

**Not yet done, consistent with the AWS side's gaps:**
- `modules/cluster/gcp-gke-existing` and `modules/network/gcp-existing` are real code (data lookups + the same fail-fast tag/range validation approach as the AWS BYO-VPC module), but no composed `envs/gcp-existing-*` example exists yet — same status as `modules/cluster/aws-eks-existing` on the AWS side.
- No live GCP deployment was performed — same no-live-cloud-testing constraint as everything else in this tree. Validated the same way: brace-balance check across every file, plus manual cross-reference of every module output against every place it's consumed. Run a real `terraform init && validate` (and ideally `plan` against a real GCP project) before trusting this further.

## Bottlerocket


Drop-in change on the default managed-node-group path — set `node_ami_type = "BOTTLEROCKET_x86_64"` (or `_ARM_64` / `_x86_64_NVIDIA`) in `envs/aws-fresh/terraform.tfvars`. EKS handles Bottlerocket bootstrap for managed node groups automatically, so nothing else changes. Two operational notes:
- No shell/SSH on Bottlerocket — use the built-in admin/control container or SSM (SSM policy is attached, but the SSM agent only runs if the admin container is explicitly enabled — plain Bottlerocket nodes don't have it by default).
- Its root disk splits into an OS partition and a separate data partition for containerd/kubelet — `modules/node-pool/aws-eks` now provisions a launch template that sizes this explicitly (`bottlerocket_data_volume_size_gb`, default 50Gi) rather than relying on the small default.

## Karpenter

Opt-in via `enable_karpenter = true` in `envs/aws-fresh/terraform.tfvars`. What changes when enabled:

- The managed node group from `modules/node-pool/aws-eks` **shrinks to a small fixed-size "system" pool** (sized via `system_node_min_size`/`max`/`desired`, default 1/2/1) that runs only Karpenter itself, core add-ons, and ingress-nginx/metrics-server. It's labeled `karpenter.sh/controller=true`, and the Karpenter Helm release's `nodeSelector` pins the controller pod to that label — so Karpenter can never accidentally schedule its own controller onto a node it might later consolidate away.
- **cluster-autoscaler is automatically disabled** (`install_cluster_autoscaler = !var.enable_karpenter` in `main.tf`) — running both against the same node group would fight over desired capacity.
- **`modules/node-pool/karpenter`** provisions everything Karpenter itself needs:
  - A separate node IAM role + instance profile for nodes *Karpenter* launches (distinct from the system pool's role). Because these nodes bypass the managed-node-group path entirely, they do **not** get an EKS access entry auto-created under API auth mode — this module creates one explicitly (`aws_eks_access_entry`, type `EC2_LINUX`, which covers Bottlerocket too). Skipping this is the single most common way to end up with nodes that launch but never join.
  - An IRSA role for the Karpenter controller (broad EC2/IAM PassRole/pricing permissions — documented as broad-by-default in the module, matching AWS's own published getting-started policy rather than presenting an untested tightened version as verified).
  - An SQS queue + 4 EventBridge rules (spot interruption warning, rebalance recommendation, instance state-change, AWS Health event) so Karpenter can drain nodes gracefully on the ~2-minute spot interruption notice instead of pods being killed abruptly.
  - The Karpenter Helm release itself (OCI chart, `oci://public.ecr.aws/karpenter/karpenter`).
  - `EC2NodeClass` and `NodePool` custom resources, applied via `kubectl_manifest` (the `gavinbunney/kubectl` provider) rather than the official provider's `kubernetes_manifest` — the latter requires the CRD to already exist in the cluster at plan time, which breaks the ordinary case of installing Karpenter (which creates the CRDs) and its NodePool/EC2NodeClass in the same `apply`.
  - `EC2NodeClass.spec.amiFamily` defaults to `Bottlerocket` (set via `karpenter_ami_family`), with the same explicit data-volume sizing as the managed-node-group path.
  - Subnet/security-group selection uses explicit resource IDs (`subnetSelectorTerms`/`securityGroupSelectorTerms` by `id`) rather than tag-based discovery — more robust here since Terraform already has those IDs as module outputs, and it avoids needing to remember to tag subnets/SGs with `karpenter.sh/discovery` out of band.

**Not yet done / worth knowing before relying on this further:**
- Not validated against a real cluster (same no-live-cloud-testing caveat as the rest of this tree) — the YAML embedded in `kubectl_manifest.yaml_body` was hand-reviewed for schema correctness against Karpenter's v1 API (`karpenter.sh/v1`, `karpenter.k8s.aws/v1`) but not applied anywhere.
- The controller IAM policy is intentionally broad; tightening `ec2:RunInstances` etc. to tag/subnet-scoped conditions is a reasonable hardening pass before production use.
- `envs/aws-existing-vpc` hasn't been updated with the same toggle yet — the diff would be identical to what's in `envs/aws-fresh/main.tf` (add the `enable_karpenter`/`karpenter_ami_family` variables, the conditional sizing on `module.node_pool`, and the `module "karpenter"` block), just not yet copied over.
