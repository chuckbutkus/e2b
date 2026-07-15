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
- **Karpenter, canary rollout, and Azure are out of scope for this pass** — flagged as explicit `use_karpenter` variable (unimplemented) in the node-pool module rather than silently absent, consistent with how the assignment plan called these out as stretch items.
