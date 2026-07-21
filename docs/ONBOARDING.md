# Customer Onboarding Guide

This guide answers "which Terraform environment do I use?" and gives the minimum commands to get the workload running. For day-two operations, see [RUNBOOK.md](RUNBOOK.md).

---

## Step 1 — Pick your cloud provider

| Provider | Go to |
|---|---|
| AWS | [AWS paths](#aws-paths) |
| GCP | [GCP paths](#gcp-paths) |

---

## AWS Paths

### Do you already have a VPC?

```
Do you have a VPC with private subnets already tagged for EKS?
│
├── NO  →  [A] aws-fresh: create VPC + cluster
└── YES →
        Do you already have an EKS cluster?
        │
        ├── NO  →  [B] aws-existing-vpc: create cluster in your VPC
        └── YES →  [C] aws-existing-cluster: deploy addons only
```

---

### [A] AWS — fresh VPC + fresh cluster

**When**: new customer account, no existing infrastructure.

**Prerequisites**:
- AWS credentials with permissions to create VPC, EKS, IAM roles, and CloudWatch resources.
- An S3 bucket and DynamoDB table for Terraform state (create once per account):
  ```bash
  aws s3api create-bucket --bucket e2b-sre-tfstate-<account-id> --region us-east-1
  aws s3api put-bucket-versioning --bucket e2b-sre-tfstate-<account-id> \
    --versioning-configuration Status=Enabled
  aws dynamodb create-table --table-name e2b-sre-tflock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST --region us-east-1
  ```
- Update `terraform/backend-config/aws-fresh.hcl` with the bucket name.

**Deploy**:
```bash
cd terraform/envs/aws-fresh
terraform init -backend-config=../../backend-config/aws-fresh.hcl
terraform plan
terraform apply

# Point kubectl at the new cluster (from the Terraform output)
$(terraform output -raw configure_kubectl)
```

**Then deploy the workload** (see [Deploy the Workload](#deploy-the-workload)).

---

### [B] AWS — existing VPC + fresh cluster

**When**: customer has a VPC with private subnets but no EKS cluster yet.

**What you need from the customer**:
- VPC ID (e.g. `vpc-0abc123`)
- At least 2 private subnet IDs in different AZs (e.g. `["subnet-aaa", "subnet-bbb"]`)
- Public subnet IDs if internet-facing ingress is needed
- The subnets must carry EKS discovery tags — the module validates this and fails plan early with a clear error if they're missing. Required tags on private subnets:
  ```
  kubernetes.io/role/internal-elb = 1
  ```

**Deploy**:
```bash
cd terraform/envs/aws-existing-vpc

# Create terraform.tfvars with customer-specific values
cat > terraform.tfvars <<EOF
vpc_id             = "vpc-0abc123"
private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
public_subnet_ids  = ["subnet-ddd", "subnet-eee", "subnet-fff"]  # optional
EOF

terraform init -backend-config=../../backend-config/aws-existing-vpc.hcl
terraform plan
terraform apply

$(terraform output -raw configure_kubectl)
```

---

### [C] AWS — existing VPC + existing cluster

**When**: customer already has an EKS cluster and you just need to install the workload and platform addons (metrics-server, ingress-nginx).

**What you need from the customer**:
- EKS cluster name
- AWS region
- Confirmation that no cluster-autoscaler is already running (if you want to install one)

**Deploy**:
```bash
cd terraform/envs/aws-existing-cluster

cat > terraform.tfvars <<EOF
cluster_name = "customer-cluster"
region       = "us-east-1"
EOF

terraform init -backend-config=../../backend-config/aws-existing-cluster.hcl
terraform plan
terraform apply

$(terraform output -raw configure_kubectl)
```

> **Note**: `install_cluster_autoscaler` defaults to `false` for this path. If the customer's cluster has no autoscaler, add `install_cluster_autoscaler = true` to `terraform.tfvars`.

---

## GCP Paths

### Do you already have a VPC?

```
Do you have a VPC with a subnet and secondary IP ranges for pods/services?
│
├── NO  →  [D] gcp-fresh: create VPC + cluster
└── YES →  Contact the E2B team — gcp-existing env is in progress
            (modules exist; see terraform/README.md for the wiring pattern)
```

---

### [D] GCP — fresh VPC + fresh cluster

**When**: new customer GCP project, no existing infrastructure.

**Prerequisites**:
- GCP project with billing enabled.
- `gcloud auth application-default login` (or a service account key) with at minimum:
  - `roles/container.clusterAdmin`
  - `roles/compute.networkAdmin`
  - `roles/iam.serviceAccountAdmin`
- A GCS bucket for Terraform state:
  ```bash
  gcloud storage buckets create gs://e2b-sre-tfstate-<project-id> \
    --location=us-east1 --uniform-bucket-level-access
  ```
- Update `terraform/backend-config/gcp-fresh.hcl` with the bucket name.

**Deploy**:
```bash
cd terraform/envs/gcp-fresh

cat > terraform.tfvars <<EOF
project_id = "my-gcp-project"
region     = "us-east1"
EOF

terraform init -backend-config=../../backend-config/gcp-fresh.hcl
terraform plan
terraform apply

$(terraform output -raw configure_kubectl)
```

---

## Local Development (kind cluster)

For local testing with [kind](https://kind.sigs.k8s.io/), use the `kind-config.yaml` at the repo root. It maps node ports 80 and 443 to host ports 8080 and 8443 so `curl localhost:8080` works without an external load balancer.

> **None of the kind-specific steps below are required in production.** Cloud clusters provision a real `LoadBalancer` Service for NGF; the cloud provider assigns an external IP automatically. No `hostPort`, no `extraPortMappings`, no port conflicts.

### Create the cluster

```bash
kind create cluster --config kind-config.yaml
```

### Install the Gateway API CRDs and NGINX Gateway Fabric

NGF 2.x has a split architecture: a **controller** runs in the `nginx-gateway` namespace and a **separate nginx data-plane pod** is provisioned per-Gateway in the same namespace as the Gateway resource. They are distinct Deployments. The controller owns and continuously reconciles the nginx deployment — patching the nginx deployment directly with `kubectl` will be reverted within seconds.

```bash
# Gateway API CRDs (required before installing NGF)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# NGF — with hostPort so the kind port-mapping (node:80 → host:8080) carries traffic
helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.6.7 \
  --create-namespace -n nginx-gateway \
  --set nginx.service.type=ClusterIP \
  --set-json 'nginx.container.hostPorts=[{"port":80,"containerPort":80},{"port":443,"containerPort":443}]'
```

**`nginx.container.hostPorts`** is the correct helm value path for NGF 2.6.7. The following are silently ignored and have no effect:
- `nginxGateway.hostPort` (wrong key)
- `nginx.hostPorts` (missing the intermediate `container` level)

> **Port conflict**: if `ingress-nginx` is already installed in the cluster it will hold port 80 via its own `hostPort`, blocking NGF from scheduling. Either remove `ingress-nginx` first (`helm uninstall ingress-nginx -n ingress-nginx`) or use the port-forward alternative below.

### Deploy the workload in Gateway API mode

```bash
helm upgrade --install sre-workload ./helm/sre-workload \
  --namespace default \
  -f helm/sre-workload/values.yaml \
  --set ingress.enabled=false \
  --set gateway.enabled=true \
  --set gateway.className=nginx \
  --set gateway.host=sre.local \
  --set gateway.createGateway=true \
  --set gateway.tls.enabled=false \
  --set 'networkPolicy.allowedIngressNamespaces={ingress-nginx,nginx-gateway,default}'
```

**Why `default` in `allowedIngressNamespaces`?** In NGF 2.x the nginx data-plane pod is provisioned in the same namespace as the Gateway (here `default`). The NetworkPolicy must allow ingress from that namespace or traffic from NGF to the workload pods is silently dropped. In production the nginx pod and the Gateway typically share a dedicated namespace (e.g. `nginx-gateway`) which is already in the default allowlist, so this override is not needed.

### Verify

```bash
# Controller + data-plane pods should all be Running
kubectl get pods -A | grep -i nginx

# Gateway and HTTPRoute must show Accepted / Programmed
kubectl get gateway,httproute -n default

# Smoke-test the workload directly (bypasses NGF and NetworkPolicy)
kubectl run tmp --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://sre-workload.default.svc.cluster.local:8080/healthz

# Full end-to-end path through NGF
curl -H "Host: sre.local" http://localhost:8080/healthz
```

### Alternative: port-forward (when hostPort is unavailable)

If port 80 is already taken by another controller and removing it is not an option, skip the `hostPorts` flag and use `kubectl port-forward` instead:

```bash
# Install NGF without hostPort
helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.6.7 \
  --create-namespace -n nginx-gateway \
  --set nginx.service.type=ClusterIP

# In a separate terminal — forward the NGF-provisioned nginx service
kubectl -n default port-forward svc/sre-workload-nginx 8080:80

# Test
curl -H "Host: sre.local" http://localhost:8080/healthz
```

---

## Deploy the Workload

After any of the above Terraform paths succeed, deploy the Helm chart. The chart is cloud-agnostic; cloud-specific settings live in `values-aws.yaml` / `values-gcp.yaml`. Each cloud has two overlay files: one for Ingress mode and one for Gateway API mode.

### AWS — Ingress mode (ingress-nginx)

```bash
# The IRSA role ARN is an output from the Terraform step, or from the
# customer's existing cluster setup. Leave it empty if the workload
# doesn't need AWS API access.
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-aws.yaml \
  --set ingress.host=<your-hostname> \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName=sre-workload-tls \
  --namespace default \
  --wait --timeout 5m
```

### AWS — Gateway API mode (NGINX Gateway Fabric)

```bash
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-aws-gateway.yaml \
  --set gateway.host=<your-hostname> \
  --set gateway.tls.enabled=true \
  --namespace default \
  --wait --timeout 5m
```

### GCP — Ingress mode (ingress-nginx)

```bash
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-gcp.yaml \
  --set ingress.host=<your-hostname> \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName=sre-workload-tls \
  --namespace default \
  --wait --timeout 5m
```

### GCP — Gateway API mode (NGINX Gateway Fabric)

```bash
helm install sre-workload ./helm/sre-workload \
  -f helm/sre-workload/values.yaml \
  -f helm/sre-workload/values-gcp-gateway.yaml \
  --set gateway.host=<your-hostname> \
  --set gateway.tls.enabled=true \
  --namespace default \
  --wait --timeout 5m
```

### Verify

```bash
kubectl get pods -l app.kubernetes.io/name=sre-workload
kubectl get hpa sre-workload

# Ingress mode
kubectl get ingress sre-workload

# Gateway API mode
kubectl get gateway,httproute -n default
```

All pods should reach `Running/Ready` within 2 minutes. The HPA will show `TARGETS` and `REPLICAS` once metrics-server is fully up (~60 s after install).

---

## Changing Defaults

Common per-customer overrides to add to `terraform.tfvars` or as `--set` flags:

| What | Variable / flag | Default |
|---|---|---|
| Node instance type (AWS) | `node_instance_types = ["m6i.xlarge"]` | `m6i.large` |
| Node machine type (GCP) | `node_machine_type = "n2-standard-4"` | `e2-standard-4` |
| Min/max nodes | `node_min_size`, `node_max_size` | 2 / 6 |
| Enable Karpenter (AWS) | `enable_karpenter = true` | `false` |
| Replica count | `--set replicaCount=5` | 3 |
| HPA max replicas | `--set autoscaling.maxReplicas=20` | 10 |
| Disable ingress | `--set ingress.enabled=false` | `true` (in cloud overlays) |
| Enable ServiceMonitor | `--set serviceMonitor.enabled=true` | `false` |

---

## Getting Help

- For Helm chart issues: see [RUNBOOK.md](RUNBOOK.md)
- For Terraform issues: see [terraform/README.md](../terraform/README.md)
- For architecture decisions: see [ARCHITECTURE.md](ARCHITECTURE.md) _(in progress)_
