# Terraform — AWS EKS module tree

## What's built vs. documented-only

| Scenario | Status |
|---|---|
| Fresh VPC + fresh EKS cluster | **Fully built** — `envs/aws-fresh` |
| Existing/BYO VPC + fresh EKS cluster | **Fully built** — `envs/aws-existing-vpc` |
| Existing VPC + existing/BYO EKS cluster | Module exists (`modules/cluster/existing`) and is wired to the same output contract, but **no env composing it is included yet** — see below |
| GCP (GKE) | Not started in this pass — same module pattern (`modules/network/gcp`, `modules/cluster/gcp-gke`) would follow, per the original plan |

Being explicit about this rather than quietly shipping only the two envs and calling it "done": `modules/cluster/existing` is real code (data-source lookups + the assumed-existing-OIDC-provider documented in its own comments), just not yet composed into a full `envs/aws-existing-cluster` example. Wiring that up is mechanical — copy `envs/aws-existing-vpc`, swap `module "cluster"` to source `../../modules/cluster/existing`, drop the `node_pool` module entirely if the customer's existing node groups are already sized/managed, and skip straight to `k8s_platform`.

## Validation performed

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

- **Output contract pattern**: `modules/network/aws` and `modules/network/existing` expose identical outputs (`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `azs`); same for `modules/cluster/aws-eks` and `modules/cluster/existing`. Envs pick which implementation to source without changing anything downstream.
- **BYO-VPC validation is fail-fast, not fail-silent**: `modules/network/existing` uses `postcondition` blocks on the subnet data sources to reject subnets missing the EKS discovery tags (`kubernetes.io/role/internal-elb`, etc.) or belonging to the wrong VPC, with an error message telling the operator exactly what's wrong — rather than a cryptic downstream EKS/LB failure minutes later.
- **API-mode access entries, not aws-auth ConfigMap**: the cluster module uses `access_config { authentication_mode = "API" }`, EKS's modern approach, so managed node groups get access entries auto-created without a chicken-and-egg Kubernetes-provider dependency on a cluster that isn't reachable yet.
- **`ignore_changes` on node group `desired_size`**: once cluster-autoscaler is running, it — not Terraform — owns replica count. Without this, every `terraform apply` would silently fight the autoscaler.
- **IRSA module is generic and reused twice**: once internally for cluster-autoscaler's own AWS permissions, and it's the same module a deployer would use to grant the *workload itself* AWS permissions if the image ever needs them (wire the resulting `role_arn` into the Helm chart's `serviceAccount.annotations."eks.amazonaws.com/role-arn"`, exactly like `values-aws.yaml` expects).
- **Karpenter, canary rollout, and Azure**: Azure and canary rollout remain out of scope for this pass. **Karpenter is now implemented** — see below.

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
