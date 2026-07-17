# AWS Fresh Install вҖ” Resource Reference

**Environment**: `terraform/envs/aws-fresh`

This document describes every resource created by each Terraform module in the fresh AWS install path, what each resource does, and why it matters. Modules are documented in dependency order вҖ” each section's outputs become the next section's inputs.

---

## 1. Network (`modules/network/aws`)

**Source**: `terraform/modules/network/aws`

This module builds everything that has to exist before an EKS cluster can be created: the VPC, subnets, internet and NAT gateways, and the route tables that connect them. None of the higher-level modules (cluster, node pool, platform addons) can run until this module's outputs are available.

---

### Resource inventory

With the default configuration in `envs/aws-fresh` вҖ” three availability zones, `single_nat_gateway = false` вҖ” the module creates 22 AWS resources:

| Resource type | Count | Names (defaults) |
|---|---|---|
| `aws_vpc` | 1 | `e2b-sre-fresh` |
| `aws_internet_gateway` | 1 | `e2b-sre-fresh-igw` |
| `aws_subnet` (public) | 3 | `e2b-sre-fresh-public-us-east-1{a,b,c}` |
| `aws_subnet` (private) | 3 | `e2b-sre-fresh-private-us-east-1{a,b,c}` |
| `aws_eip` | 3 | `e2b-sre-fresh-nat-eip-{0,1,2}` |
| `aws_nat_gateway` | 3 | `e2b-sre-fresh-nat-{0,1,2}` |
| `aws_route_table` (public) | 1 | `e2b-sre-fresh-public-rt` |
| `aws_route` (public internet) | 1 | *(default route вҶ’ IGW)* |
| `aws_route_table_association` (public) | 3 | *(one per public subnet)* |
| `aws_route_table` (private) | 3 | `e2b-sre-fresh-private-rt-us-east-1{a,b,c}` |
| `aws_route` (private NAT) | 3 | *(one default route per private RT вҶ’ local NAT GW)* |
| `aws_route_table_association` (private) | 3 | *(one per private subnet)* |

---

### Network topology

```
                         Internet
                            в”Ӯ
                 в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ
                 в”Ӯ   Internet Gateway  в”Ӯ
                 в”Ӯ   e2b-sre-fresh-igw в”Ӯ
                 в””в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”¬в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ
                            в”Ӯ
          в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ
          в”Ӯ                 в”Ӯ                 в”Ӯ
в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ
в”Ӯ  Public Subnet   в”Ӯ в”ӮPublic Subnet в”Ӯ в”ӮPublic Subnet в”Ӯ
в”Ӯ  us-east-1a      в”Ӯ в”Ӯus-east-1b    в”Ӯ в”Ӯus-east-1c    в”Ӯ
в”Ӯ  10.0.128.0/20   в”Ӯ в”Ӯ10.0.144.0/20 в”Ӯ в”Ӯ10.0.160.0/20 в”Ӯ
в”Ӯ  [NAT GW + EIP]  в”Ӯ в”Ӯ[NAT GW + EIP]в”Ӯ в”Ӯ[NAT GW + EIP]в”Ӯ
в””в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”¬в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ в””в”Җв”Җв”Җв”Җв”Җв”Җв”¬в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ в””в”Җв”Җв”Җв”Җв”Җв”Җв”¬в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ
          в”Ӯ  (outbound only)в”Ӯ                 в”Ӯ
в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ в”Ңв”Җв”Җв”Җв”Җв”Җв”Җв–јв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”җ
в”Ӯ  Private Subnet  в”Ӯ в”ӮPrivate Subnetв”Ӯ в”ӮPrivate Subnetв”Ӯ
в”Ӯ  us-east-1a      в”Ӯ в”Ӯus-east-1b    в”Ӯ в”Ӯus-east-1c    в”Ӯ
в”Ӯ  10.0.0.0/20     в”Ӯ в”Ӯ10.0.16.0/20  в”Ӯ в”Ӯ10.0.32.0/20  в”Ӯ
в”Ӯ  [EKS nodes]     в”Ӯ в”Ӯ[EKS nodes]   в”Ӯ в”Ӯ[EKS nodes]   в”Ӯ
в””в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ в””в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ в””в”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”Җв”ҳ
```

Traffic can enter the private subnets from the internet only through a load balancer sitting in a public subnet. Nodes in the private subnets can initiate outbound connections (to pull container images, call AWS APIs, etc.) through the NAT gateway in the same AZ, but nothing on the internet can reach a node directly.

---

### Resources in detail

#### VPC (`aws_vpc`)

```
cidr_block:           10.0.0.0/16   (65,536 addresses)
enable_dns_support:   true
enable_dns_hostnames: true
```

The VPC is the private network boundary for the entire deployment. Everything вҖ” EKS control plane ENIs, worker nodes, load balancers вҖ” lives inside it.

The `/16` block is large enough to carve out multiple `/20` subnets (4,096 addresses each) per tier per AZ without address space running short. The default layout uses only a fraction:

```
10.0.0.0/20    private, us-east-1a   (4,094 usable)
10.0.16.0/20   private, us-east-1b
10.0.32.0/20   private, us-east-1c
...            (10.0.48.0 вҖ“ 10.0.127.255 unallocated, available for future use)
10.0.128.0/20  public,  us-east-1a
10.0.144.0/20  public,  us-east-1b
10.0.160.0/20  public,  us-east-1c
...            (10.0.176.0 вҖ“ 10.0.255.255 unallocated)
```

**`enable_dns_support = true`** turns on the Route 53 Resolver inside the VPC. Without it, hostnames don't resolve at all вҖ” pods couldn't reach `s3.amazonaws.com`, AWS service endpoints, or each other by DNS name.

**`enable_dns_hostnames = true`** gives EC2 instances public DNS hostnames (e.g. `ec2-54-x-x-x.compute-1.amazonaws.com`). For EKS specifically this also enables VPC DNS resolution for the cluster API endpoint, which is how `kubectl` and the kubelet both reach the control plane. EKS will refuse to create the cluster if this flag is off.

---

#### Internet Gateway (`aws_internet_gateway`)

```
attached to: aws_vpc.this
```

An Internet Gateway is the single point through which a VPC exchanges traffic with the public internet. It performs no address translation вҖ” it maps public Elastic IPs to private addresses and passes packets between them.

The IGW is required even in a deployment where worker nodes are entirely private. It serves two purposes here:

1. **Outbound path for NAT gateways.** NAT gateways sit in public subnets. Their route tables point to this gateway for outbound traffic. Without the IGW, NAT gateways would have nowhere to send packets, and private-subnet nodes couldn't reach the internet.
2. **Public load balancer termination.** When `ingress-nginx` or the AWS Load Balancer Controller creates an internet-facing load balancer, that load balancer gets a public IP in a public subnet. Traffic from the internet arrives at the VPC through this gateway and is forwarded to the load balancer's ENI.

The `depends_on = [aws_internet_gateway.this]` on the NAT gateway resource enforces that the IGW exists before NAT gateways are created, because a NAT gateway in a public subnet can't route outbound traffic until the IGW is attached.

---

#### Public Subnets (`aws_subnet.public`, Г—3)

```
count:                    3  (one per AZ)
availability_zones:       us-east-1a, us-east-1b, us-east-1c
cidr_blocks:              10.0.128.0/20, 10.0.144.0/20, 10.0.160.0/20
map_public_ip_on_launch:  true
```

Public subnets are the internet-facing tier. Resources placed in them receive a public IP address automatically and are reachable from the internet (subject to security group rules). Three things live here:

- **NAT gateways** (one per AZ). A NAT gateway must be in a public subnet because it needs a route to the IGW for outbound traffic. It's the exit ramp for all outbound internet traffic from the private subnets.
- **Internet-facing load balancers.** When `ingress-nginx` creates a LoadBalancer-type Service on EKS, the resulting AWS NLB is provisioned in these subnets. The AWS Load Balancer Controller discovers them using subnet tags (described below).
- **Public EC2 instances**, if ever needed (e.g., a bastion host). Worker nodes are never placed here.

**`map_public_ip_on_launch = true`** means any EC2 instance launched in these subnets gets a public IP automatically. NAT gateways also use this path (via their associated Elastic IP).

**Subnet tags applied:**

```
kubernetes.io/role/elb            = "1"
kubernetes.io/cluster/e2b-sre-fresh = "shared"
```

These tags are required for internet-facing load balancers to work. The AWS Load Balancer Controller queries AWS for subnets with `kubernetes.io/role/elb = 1` to decide where to place a public-facing NLB or ALB. Without this tag, the load balancer creation will fail with a "no subnets found" error. The `kubernetes.io/cluster/<name>` tag restricts discovery to subnets that belong to this cluster (`shared` means multiple clusters may share the subnet; `owned` would grant this cluster exclusive management rights over it).

---

#### Private Subnets (`aws_subnet.private`, Г—3)

```
count:                    3  (one per AZ)
availability_zones:       us-east-1a, us-east-1b, us-east-1c
cidr_blocks:              10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
map_public_ip_on_launch:  false  (the default; not set explicitly)
```

Private subnets are where all EKS worker nodes run. Nodes here have no public IP address and are unreachable from the internet directly вҖ” the only inbound path is through a load balancer in a public subnet. Outbound traffic (pulling images, calling AWS APIs) goes through the NAT gateway in the same AZ.

Keeping nodes private is the standard EKS security posture. A node with a public IP is a direct attack surface; a node behind a NAT gateway is not. Even with restrictive security groups, the defence-in-depth principle strongly favours private nodes.

**Subnet tags applied:**

```
kubernetes.io/role/internal-elb       = "1"
kubernetes.io/cluster/e2b-sre-fresh   = "shared"
```

The `kubernetes.io/role/internal-elb = 1` tag serves the same role as the public subnet's `elb` tag, but for *internal* load balancers. When a Kubernetes Service of type `LoadBalancer` is created with the `internal: true` annotation (or when the ingress controller is configured for internal routing), the AWS Load Balancer Controller looks for subnets tagged with `internal-elb` to place the NLB. EKS also reads this tag when it needs to create control-plane ENIs in the VPC.

The `modules/network/existing` module вҖ” used when a customer brings their own VPC вҖ” validates that these tags are present on the supplied subnets before the plan proceeds, producing a clear error rather than a silent failure minutes later during cluster creation.

---

#### Elastic IPs (`aws_eip`, Г—3)

```
count:   3  (one per AZ, because single_nat_gateway = false)
domain:  "vpc"
```

An Elastic IP is a static public IPv4 address in your AWS account. NAT gateways require one: it's the source IP address that all outbound traffic from the private subnets appears to come from when it exits to the internet.

The practical significance of a static IP is that it can be added to external allowlists. If the workload calls a third-party API that restricts access by IP, the customer gives the vendor the EIP addresses (one per AZ, three in this configuration) once, and the list never changes even when nodes are replaced or autoscaled.

EIPs are created separately from NAT gateways (`aws_eip` вҶ’ `aws_nat_gateway` via `allocation_id`) because AWS bills for them independently and their lifecycle is separate: if a NAT gateway is destroyed and recreated, the EIP address can be preserved.

---

#### NAT Gateways (`aws_nat_gateway`, Г—3)

```
count:          3  (one per AZ, because single_nat_gateway = false)
placement:      one per public subnet
allocation_id:  bound to the matching aws_eip
```

A NAT (Network Address Translation) gateway lets resources in a private subnet initiate outbound connections to the internet while remaining unreachable from it. It replaces the source IP of the outgoing packet with the Elastic IP, forwards the packet out through the Internet Gateway, and reverses the translation for the reply.

**Why nodes need this.** EKS worker nodes must be able to reach:
- AWS APIs (EC2, ECR, S3, CloudWatch, STS) to register with the cluster and report metrics.
- Container image registries (ghcr.io, docker.io, ECR) to pull workload images.
- Any external dependencies the workload itself calls.

None of this is possible from a private subnet without a NAT gateway (or VPC endpoints as an alternative вҖ” see note below).

**Why one per AZ, not one shared.** A NAT gateway is an Availability Zone-scoped resource. It is not replicated across AZs. If `us-east-1a` suffers a partial outage and the single NAT gateway happens to be there, every private subnet in every AZ loses outbound internet access simultaneously вҖ” the cluster's nodes can no longer reach ECR or AWS APIs, new pod scheduling stalls, and the workload degrades across all AZs, not just the affected one.

With one NAT gateway per AZ, an AZ-level event affects only the nodes in that AZ. The nodes in `us-east-1b` and `us-east-1c` continue routing through their own gateways, unaffected. This is why `single_nat_gateway = false` is the production default, even though it triples the NAT gateway cost (~$0.045/hour per gateway, plus data processing charges).

`single_nat_gateway = true` is available for cost-sensitive non-production environments and can be set in `terraform.tfvars`.

> **VPC Endpoints as an alternative.** For clusters with very high outbound data volumes, replacing NAT gateway traffic with VPC Interface Endpoints (for ECR, S3, EC2, STS, CloudWatch, etc.) can reduce both cost and latency, since traffic stays on the AWS network rather than exiting through the IGW. This is a post-initial-deployment hardening step, not a day-one requirement, and is out of scope for this module.

---

#### Public Route Table and Routes

```
aws_route_table.public         (1 table, shared by all 3 public subnets)
aws_route.public_internet      destination 0.0.0.0/0  вҶ’  Internet Gateway
aws_route_table_association    (3 associations, one per public subnet)
```

A route table is the routing policy attached to a subnet. All three public subnets share a single route table because their routing is identical: local VPC traffic stays local, everything else goes to the Internet Gateway.

| Destination | Target | Added by |
|---|---|---|
| `10.0.0.0/16` | local | AWS (automatic, always present) |
| `0.0.0.0/0` | `igw-...` | `aws_route.public_internet` |

The local route (`10.0.0.0/16 вҶ’ local`) is injected automatically by AWS and cannot be deleted. It ensures that traffic destined for any address inside the VPC stays inside the VPC rather than being sent out through the IGW.

The default route (`0.0.0.0/0 вҶ’ IGW`) makes a subnet "public": any traffic that doesn't match a more specific route is forwarded to the Internet Gateway. Resources in a public subnet can initiate and receive internet connections through it.

---

#### Private Route Tables and Routes

```
aws_route_table.private        (3 tables, one per AZ)
aws_route.private_nat          destination 0.0.0.0/0  вҶ’  NAT Gateway (per-AZ)
aws_route_table_association    (3 associations, one per private subnet)
```

Each private subnet gets its own route table rather than sharing one, so each can route outbound traffic to the NAT gateway in its own AZ.

| Destination | Target | Added by |
|---|---|---|
| `10.0.0.0/16` | local | AWS (automatic) |
| `0.0.0.0/0` | `nat-...` (same AZ) | `aws_route.private_nat` |

**Why per-AZ route tables matter.** If all three private subnets shared one route table pointing to a single NAT gateway, traffic from a node in `us-east-1b` to the internet would travel cross-AZ to reach the gateway in `us-east-1a`, incur cross-AZ data transfer charges, and add latency. More importantly, it reintroduces the single-NAT-gateway failure mode at the routing level even if three NAT gateways exist. Per-AZ route tables ensure each subnet's traffic stays within the AZ for as long as possible before exiting.

When `single_nat_gateway = true`, all three private route tables are created but each points to the single shared NAT gateway вҖ” the structure is the same, only the target changes.

---

### Module outputs

```hcl
vpc_id             вҶ’ consumed by modules/cluster/aws-eks (vpc_config block)
private_subnet_ids вҶ’ consumed by modules/cluster/aws-eks (control-plane ENIs)
                     and modules/node-pool/aws-eks (node launch subnets)
public_subnet_ids  вҶ’ available for load balancer subnet references
azs                вҶ’ available for downstream AZ-aware resources
```

The output contract (`vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `azs`) is identical to the one exposed by `modules/network/existing`, which looks up a customer's pre-existing VPC instead of creating one. The `envs/` root modules compose against this shape regardless of which implementation is behind it вҖ” swapping from fresh to existing is a one-line source change with no downstream edits required.

---

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| `enable_dns_hostnames = false` | EKS cluster creation rejected; kubelet can't resolve the API endpoint |
| Missing `kubernetes.io/role/internal-elb` tag on private subnets | Internal load balancers silently fail to provision; Service stays in `Pending` |
| Missing `kubernetes.io/role/elb` tag on public subnets | Internet-facing load balancers fail; ingress controller errors |
| Single NAT gateway in production | AZ outage kills all outbound internet access across the cluster |
| Private subnets in fewer than 2 AZs | Terraform validation error before any resources are created (enforced by `var.azs` validation block) |
| Private subnets in only 1 AZ | EKS API rejects the cluster; EKS requires control-plane ENIs in at least 2 AZs |

---

## 2. EKS Cluster (`modules/cluster/aws-eks`)

**Source**: `terraform/modules/cluster/aws-eks`  
**Receives from network module**: `vpc_id`, `private_subnet_ids`

This module creates the EKS control plane and every piece of IAM and logging infrastructure the control plane depends on. It also registers the cluster's OIDC issuer with AWS IAM, which is the prerequisite for the IRSA pattern used by the cluster autoscaler, Karpenter, and any workload that needs AWS API access without static credentials.

### Resource inventory

| Resource type | Count | Name (default) |
|---|---|---|
| `aws_iam_role` | 1 | `e2b-sre-fresh-eks-cluster` |
| `aws_iam_role_policy_attachment` | 1 | *(attaches `AmazonEKSClusterPolicy`)* |
| `aws_cloudwatch_log_group` | 1 | `/aws/eks/e2b-sre-fresh/cluster` |
| `aws_eks_cluster` | 1 | `e2b-sre-fresh` |
| `aws_iam_openid_connect_provider` | 1 | *(OIDC issuer URL as the identifier)* |

The module also uses two **data sources** that do not create resources but are required for correct resource configuration: `data.aws_partition.current` and `data.tls_certificate.eks`.

### Resources in detail

#### IAM Role — cluster control plane (`aws_iam_role.cluster`)

```
name:                  e2b-sre-fresh-eks-cluster
assume_role_policy:    eks.amazonaws.com  →  sts:AssumeRole
```

EKS's managed control plane runs entirely inside AWS's own account, not inside the customer's. When the control plane needs to act in the customer's account — creating ENIs so nodes can communicate with the API server, managing the cluster security group, updating load balancers — it must assume a role in the customer's account to do so. This role is that entry point.

The trust policy restricts assumption to the `eks.amazonaws.com` service principal, which means no other service or human IAM entity can assume it. The EKS service itself assumes this role automatically during cluster operations; the customer never calls `sts:AssumeRole` on it directly.

Without this role, the EKS cluster creation API call fails immediately — AWS requires the `role_arn` to be present and correctly trusted before it will accept the `CreateCluster` request.

`data.aws_partition.current` is used wherever a managed policy ARN is constructed (`arn:${partition}:iam::aws:policy/...`). In standard commercial AWS, the partition is `aws`, but in GovCloud it is `aws-us-gov` and in China it is `aws-cn`. Using the data source instead of hardcoding `aws` makes the module portable across partitions without change.

#### IAM Role Policy Attachment — `AmazonEKSClusterPolicy`

```
role:        aws_iam_role.cluster
policy_arn:  arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

This attachment grants the cluster role the permissions EKS's control plane actually exercises in the customer's account. The managed policy covers several distinct capability areas:

**Network management.** `ec2:CreateNetworkInterface`, `ec2:AttachNetworkInterface`, `ec2:DeleteNetworkInterface` — EKS creates cross-account ENIs in the customer's private subnets. These ENIs are what make the private API endpoint reachable from inside the VPC without traffic leaving AWS's network. The control plane also needs `ec2:DescribeSubnets`, `ec2:DescribeVpcs`, and `ec2:DescribeSecurityGroups` to validate the networking configuration at creation time and to make decisions about where to place ENIs during scaling.

**Security group management.** `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:AuthorizeSecurityGroupEgress` — EKS automatically creates and manages the cluster security group (the one returned in the `cluster_security_group_id` output). This group is attached to both the control plane ENIs and every managed node group node, enabling control plane-to-node communication without requiring any customer-managed security group rules.

**Load balancer management.** `elasticloadbalancing:*` — When a Kubernetes Service of type `LoadBalancer` is created, EKS's built-in controller provisions and manages the underlying AWS load balancer. These permissions are what that controller uses. (The more modern AWS Load Balancer Controller add-on replaces this built-in behaviour, but the permissions still need to be present on the cluster role as a fallback.)

**KMS and CloudWatch.** Permissions to encrypt secrets at rest if a KMS key is configured, and to emit metrics to CloudWatch.

One managed policy covers all of this. Using a managed policy rather than an inline policy means AWS can update its contents when EKS adds new required permissions, without requiring a Terraform change.

#### CloudWatch Log Group (`aws_cloudwatch_log_group.cluster`)

```
name:               /aws/eks/e2b-sre-fresh/cluster
retention_in_days:  90
```

EKS does not send control plane logs anywhere by default. Enabling them requires both an explicit log group and a list of log types on the cluster resource. The log group must exist before the cluster is created — enforced by the `depends_on = [aws_cloudwatch_log_group.cluster]` on `aws_eks_cluster.this`.

The name `/aws/eks/<cluster-name>/cluster` is the path EKS expects. Using any other name would cause the log delivery to fail silently.

**Why 90-day retention.** Without an explicit retention policy, CloudWatch log groups default to "never expire." A cluster generating continuous control plane logs with no expiry accrues storage costs indefinitely. 90 days provides a generous window for incident investigation and compliance needs without unbounded accumulation. Adjust to match the customer's retention requirements.

**The five log types** set in `enabled_cluster_log_types`:

| Log type | What it captures | Primary use |
|---|---|---|
| `api` | Every request to the API server: method, path, response code, latency | Traffic volume analysis, detecting unexpected API clients, rate-limit debugging |
| `audit` | The Kubernetes audit trail: every API call with the calling user/group, verb, object reference, and decision | Security investigation, compliance, RBAC debugging — the authoritative record of "who did what to which resource" |
| `authenticator` | IAM-to-Kubernetes authentication decisions: which IAM ARN was mapped to which k8s username/groups, and whether the mapping succeeded | Diagnosing "Unauthorized" errors, verifying access entry configuration is correct |
| `scheduler` | Pod scheduling decisions: which node each pod was assigned to and why | Debugging pods stuck in `Pending`, understanding affinity/taint/resource constraint effects |
| `controllerManager` | Controller reconciliation events: Deployments creating ReplicaSets, ReplicaSets creating Pods, etc. | Understanding why the cluster's desired state isn't being reached |

All five types are enabled by default. Omitting any of them creates blind spots that are difficult to recover from after the fact. The `audit` log in particular is the primary evidence source for any security incident involving the API server.

#### EKS Cluster (`aws_eks_cluster.this`)

```
name:               e2b-sre-fresh
version:            1.31
role_arn:           aws_iam_role.cluster.arn
subnet_ids:         module.network.private_subnet_ids  (3 subnets)
endpoint_public_access:   true
endpoint_private_access:  true
public_access_cidrs:      ["0.0.0.0/0"]
authentication_mode:      API
enabled_cluster_log_types: [api, audit, authenticator, scheduler, controllerManager]
```

This is the EKS cluster resource itself. AWS uses it to provision and manage the Kubernetes control plane (API server, etcd, scheduler, controller manager) as a fully managed service. The customer is responsible for the data plane (nodes) and what runs on it; AWS is responsible for the control plane's availability and patching.

**`subnet_ids` — private subnets only.** The cluster module receives `module.network.private_subnet_ids` from the network module, not a combined list of public and private subnets. EKS places cross-account ENIs into these subnets to bridge the control plane (running in AWS's account) with the customer's VPC. Using only private subnets keeps control-plane-to-node traffic entirely within the VPC. If public subnets were included, EKS could place an ENI there, which is unnecessary and slightly increases the attack surface.

**`endpoint_public_access = true`.** The Kubernetes API server is reachable at a public DNS name (e.g. `https://XXXXXXXX.gr7.us-east-1.eks.amazonaws.com`). This is what allows `kubectl` commands from an operator's laptop or a CI runner outside the VPC. Without it, the API endpoint is reachable only from within the VPC, which requires every operator and every pipeline to have VPN or VPC access — often impractical at the start of a deployment.

**`endpoint_private_access = true`.** Nodes inside the VPC also reach the API server via a private endpoint that resolves to a private IP within the VPC. This means kubelet node registration, pod status updates, and any in-cluster traffic to the API server stays on the AWS private network rather than exiting through the NAT gateway to reach the public endpoint. Both endpoints can be active simultaneously; cluster-internal traffic uses the private path automatically.

**`public_access_cidrs = ["0.0.0.0/0"]`.** This is the default and it is deliberately permissive. It allows any IP address to reach the public API endpoint. The API server still requires a valid client certificate or token — unauthenticated requests are rejected — so this is not a direct security hole, but it does expose the API surface to the internet. In production, restricting this to the operator's IP range or corporate VPN CIDR is a sensible hardening step. The variable exists precisely for this purpose: set `public_access_cidrs = ["10.x.x.x/y"]` in `terraform.tfvars`.

**`authentication_mode = "API"` — and why this matters.**

The legacy approach (`authentication_mode = "CONFIG_MAP"`) managed IAM-to-Kubernetes identity mappings in a Kubernetes ConfigMap called `aws-auth` in the `kube-system` namespace. This created a chicken-and-egg problem: the ConfigMap had to be applied via `kubectl`, which required the Terraform `kubernetes` provider, which required a reachable cluster endpoint, which required the Terraform apply to have already completed far enough for the cluster to be accessible. If the cluster had a private endpoint and the Terraform runner was outside the VPC, the apply would partially complete and then fail with a connection timeout.

`authentication_mode = "API"` moves these mappings to AWS-managed Access Entries — IAM ARNs mapped to Kubernetes groups, stored on the AWS side and enforced by the EKS API itself. There is no ConfigMap to apply and no Kubernetes provider dependency at cluster-creation time. EKS also automatically creates Access Entries for managed node group roles in API mode, so nodes can join the cluster the moment the node group is created, without any out-of-band ConfigMap editing.

**`bootstrap_cluster_creator_admin_permissions = true`.** The IAM entity that runs `terraform apply` automatically receives a `cluster-admin` Access Entry for the new cluster. Without this, Terraform's `kubernetes` and `helm` providers — which are used by the `k8s-platform` module to install metrics-server, ingress-nginx, and cluster-autoscaler — would be refused by the cluster's RBAC immediately after creation. The access entry is permanent unless explicitly deleted; for a handoff to a customer, the expected cleanup is to remove this entry and replace it with access entries scoped to the team's actual IAM roles.

**`depends_on` ordering.** The cluster resource explicitly depends on both the IAM role policy attachment and the CloudWatch log group:

```hcl
depends_on = [
  aws_iam_role_policy_attachment.cluster_policy,
  aws_cloudwatch_log_group.cluster,
]
```

The IAM dependency matters because AWS validates the trust policy and policy attachments on the cluster role before accepting the `CreateCluster` call. Without `depends_on`, Terraform might submit the cluster creation request before the policy attachment has propagated through IAM, causing a sporadic race-condition failure. The log group dependency ensures the destination exists before EKS starts delivering logs.

#### OIDC Provider (`data.tls_certificate.eks` + `aws_iam_openid_connect_provider.eks`)

```
url:             https://oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ID>
client_id_list:  ["sts.amazonaws.com"]
thumbprint_list: [sha1 of the issuer's TLS certificate]
```

Every EKS cluster has an OIDC issuer — an endpoint that issues signed JWTs (JSON Web Tokens) for Kubernetes ServiceAccounts. Pods receive these tokens automatically via a projected volume and can present them to AWS STS to assume an IAM role, without any static AWS credentials mounted in the pod. This is the IRSA (IAM Roles for Service Accounts) pattern.

EKS creates the OIDC issuer automatically as part of `aws_eks_cluster.this`, but it does not register it as an IAM Identity Provider. That is a separate, explicit step — and without it, STS refuses every `AssumeRoleWithWebIdentity` call from the cluster's pods, because AWS has no record that this cluster's JWTs should be trusted.

`aws_iam_openid_connect_provider.eks` is that registration step. Once it exists, IAM trust policies can reference the cluster's OIDC issuer with a condition like:

```json
"Condition": {
  "StringEquals": {
    "oidc.eks.us-east-1.amazonaws.com/id/XXXX:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
    "oidc.eks.us-east-1.amazonaws.com/id/XXXX:aud": "sts.amazonaws.com"
  }
}
```

This binds a specific IAM role to a specific Kubernetes ServiceAccount in a specific namespace — so only that ServiceAccount can assume the role, and no other pod can use its credentials.

**The TLS thumbprint.** AWS requires a SHA1 fingerprint of the OIDC endpoint's TLS certificate as part of the provider registration. This is a standard OIDC security check: it prevents a malicious party from substituting a different signing endpoint at the same URL. `data.tls_certificate.eks` fetches the certificate chain from the OIDC issuer URL and extracts `certificates[0].sha1_fingerprint`, which is then passed to `thumbprint_list`. This runs at every `terraform plan`/`apply`, ensuring the thumbprint stays current if the certificate is ever rotated.

**`client_id_list = ["sts.amazonaws.com"]`.** When a pod uses its JWT to call `AssumeRoleWithWebIdentity`, the token's `aud` (audience) claim must match an entry in this list. The EKS pod identity webhook injects `sts.amazonaws.com` as the audience when mounting projected service account tokens. Only tokens with this audience claim are accepted by the IAM role trust policies created by the `modules/irsa` module.

### Module outputs

```hcl
cluster_name               → modules/node-pool/aws-eks, modules/k8s-platform, modules/node-pool/karpenter,
                              kubernetes and helm providers (exec args)
cluster_endpoint           → kubernetes and helm providers (host), modules/node-pool/karpenter
cluster_ca_certificate     → kubernetes and helm providers (cluster_ca_certificate)  [sensitive]
cluster_version            → informational
cluster_oidc_issuer_url    → modules/irsa (trust policy condition), modules/node-pool/karpenter
oidc_provider_arn          → modules/irsa (federated principal), modules/node-pool/karpenter
cluster_security_group_id  → modules/node-pool/karpenter (EC2NodeClass securityGroupSelectorTerms)
```

`cluster_ca_certificate` is marked `sensitive = true` — it does not appear in `terraform output` without `--raw` or `-json`, and it is redacted in plan output. It is a base64-encoded PEM certificate that the kubernetes and helm providers use to verify the API server's TLS certificate, preventing man-in-the-middle attacks between Terraform and the cluster.

The `cluster_endpoint` and `cluster_ca_certificate` outputs are what allow the kubernetes and helm providers in `providers.tf` to connect to the newly created cluster without storing any credentials in Terraform state — they use the exec-based `aws eks get-token` plugin to fetch a short-lived token at runtime.

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| Cluster role missing `AmazonEKSClusterPolicy` | `CreateCluster` API call fails with an IAM error |
| `depends_on` for policy attachment removed | Sporadic IAM propagation race: cluster creation fails ~10% of the time, passes otherwise |
| `enable_dns_hostnames = false` on the VPC (network module) | Cluster creates but nodes can never resolve the API endpoint hostname; they fail to register |
| `subnet_ids` pointing to public subnets | Control-plane ENIs land in public subnets; cross-AZ ENI traffic is unnecessary and increases cost |
| `endpoint_private_access = false` | Nodes reach the API server via the public endpoint, routing out through NAT gateways and back in — adds latency and NAT cost, breaks if `public_access_cidrs` is restricted to exclude the node CIDR |
| `public_access_cidrs = ["0.0.0.0/0"]` in hardened env | Public API endpoint exposed to internet; acceptable for initial setup, should be restricted for production |
| `authentication_mode = "CONFIG_MAP"` | Chicken-and-egg: `aws-auth` ConfigMap can't be applied until cluster is reachable, cluster isn't useful until ConfigMap is applied; particularly bad with private-endpoint-only clusters |
| OIDC provider not created | All `AssumeRoleWithWebIdentity` calls from pods fail with "No OpenIDConnect provider found"; cluster-autoscaler, Karpenter, and any IRSA-backed workload lose their AWS access |
| CloudWatch log group not pre-created | Log delivery to CloudWatch silently fails for the first few minutes until EKS auto-creates the group (with no retention policy, leading to unbounded log accumulation) |

---

## 3. Node Pool (`modules/node-pool/aws-eks`)

**Source**: `terraform/modules/node-pool/aws-eks`  
**Receives from network module**: `private_subnet_ids`  
**Receives from cluster module**: `cluster_name`

This module creates the EC2 data plane — the worker nodes that run pods. The EKS control plane created by the previous module manages the cluster; this module provides the capacity the control plane schedules work onto. Without at least one node group, the cluster exists but has nowhere to run pods.

The module always creates one managed node group. When Karpenter is enabled, this group shrinks to a small fixed-size pool that hosts only cluster infrastructure; Karpenter provisions separate nodes for workloads on demand. When Karpenter is disabled, this group scales to carry the full workload.

### Resource inventory

| Resource type | Count | Name (default) |
|---|---|---|
| `aws_launch_template` | 1 | `e2b-sre-fresh-` *(name_prefix, AWS appends a random suffix)* |
| `aws_iam_role` | 1 | `e2b-sre-fresh-eks-node` |
| `aws_iam_role_policy_attachment` | 4 | *(one per managed policy; see below)* |
| `aws_eks_node_group` | 1 | `e2b-sre-fresh-default` |

The module also uses `data.aws_partition.current` to construct partition-portable managed policy ARNs, and a local `is_bottlerocket` boolean that switches disk configuration between the two supported AMI families.

### Resources in detail

#### Launch Template (`aws_launch_template.this`)

```
name_prefix:   e2b-sre-fresh-
volume (AL2023):       /dev/xvda  50 GiB  gp3  encrypted
volume (Bottlerocket): /dev/xvdb  50 GiB  gp3  encrypted
http_tokens:   required   (IMDSv2 only)
http_put_response_hop_limit:  2
```

The launch template is the mechanism through which the managed node group applies configuration that EKS's node group resource does not directly expose. The node group references the template by ID and version, so the node group resource itself stays clean.

**Disk configuration.**

AL2023 uses a single root volume at `/dev/xvda`. Bottlerocket uses a two-partition layout: a read-only OS partition at `/dev/xvda` (managed by AWS and not configurable) and a separate data partition at `/dev/xvdb` where containerd, kubelet, and pod image layers live. The default size of the Bottlerocket data volume is small — not enough for a workload that pulls multiple container images — so the module sizes it explicitly to 50 GiB (configurable via `bottlerocket_data_volume_size_gb`).

Both AMI families use `gp3` rather than `gp2`. The gp3 volume type delivers 3,000 IOPS and 125 MB/s throughput at baseline regardless of volume size, whereas gp2 baseline IOPS scales with size (3 IOPS/GiB, so a 50 GiB gp2 delivers only 150 IOPS). For a Kubernetes node pulling and layering container images, the difference in disk I/O throughput is directly visible in pod startup latency.

`encrypted = true` applies the account's default KMS key to the volume. If a physical disk is decommissioned in an AWS data centre or an EBS snapshot is inadvertently shared, the data is unreadable without the key. This is defence in depth — the contents of a worker node disk (image layers, temporary files, potential log data) should not be recoverable outside AWS.

`delete_on_termination = true` ensures EBS volumes are deleted when the node instance is terminated. Without it, every node replacement — whether from an autoscaler action, a rolling update, or a manual termination — would leave an orphaned encrypted volume accumulating storage charges indefinitely.

**IMDSv2 enforcement.**

The Instance Metadata Service (IMDS) is an HTTP endpoint at `169.254.169.254` that every EC2 instance can reach. It serves instance identity documents, IAM role credentials, user data, and other node-level information. IMDSv1 accepted unauthenticated GET requests — any process on the node could call it and retrieve the node's IAM credentials. This made SSRF (Server-Side Request Forgery) vulnerabilities on the instance particularly dangerous: a web application that could be tricked into making an outbound HTTP request could be used to steal the node's IAM credentials by fetching `http://169.254.169.254/latest/meta-data/iam/security-credentials/`.

`http_tokens = "required"` disables IMDSv1 entirely. IMDSv2 requires a two-step process: the caller must first make an authenticated PUT request to obtain a session token, then present that token in subsequent GET requests. Ordinary SSRF attacks use GET requests and cannot complete the IMDSv2 handshake, so stolen instance credentials via SSRF are no longer possible.

`http_put_response_hop_limit = 2` controls how many network hops the IMDSv2 PUT response can traverse before it is discarded. Each veth interface (the virtual Ethernet pair connecting a container to the host network) counts as one hop.

- Hop limit 1: Only processes running directly on the EC2 host can complete the IMDSv2 handshake. Container processes — including DaemonSet pods — are blocked, because they sit one veth hop away from the host.
- Hop limit 2: Processes on the host (hop 0) and processes in containers directly on the host (hop 1, i.e., DaemonSet pods such as the VPC CNI and kube-proxy) can reach IMDS. Containers nested within other containers cannot.

Hop limit 2 is the correct setting for EKS because node-level DaemonSets (VPC CNI, kube-proxy, and the SSM agent on AL2023) need IMDS to function. The VPC CNI uses IMDS to discover the node's primary private IP and ENI information during pod network setup. Without it, pod IP assignment fails. Setting hop limit to 1 would block these DaemonSets. Setting it higher than 2 would unnecessarily expose IMDS to application containers, which should use IRSA tokens rather than node credentials for any AWS API access they need.

#### Node IAM Role (`aws_iam_role.node`)

```
name:                  e2b-sre-fresh-eks-node
assume_role_policy:    ec2.amazonaws.com  →  sts:AssumeRole
```

This is the EC2 instance profile role — the IAM identity that the node itself assumes when making AWS API calls. It is distinct from the pod-level roles created by the IRSA module: pods use their own projected service account tokens to assume workload-specific roles with scoped permissions, and never touch this node role. The node role covers only infrastructure-level node operations.

The trust policy restricts assumption to `ec2.amazonaws.com`. When EKS launches an instance, it attaches this role as the instance profile, and the AWS SDK running on the node (in kubelet, the VPC CNI, and the SSM agent) retrieves short-lived credentials for it from IMDS.

In API authentication mode — set by the cluster module — EKS automatically creates an Access Entry mapping this role's ARN to the `system:nodes` and `system:bootstrappers` Kubernetes RBAC groups. This is what allows nodes to register with the API server without any manual `aws-auth` ConfigMap editing. The Access Entry is created when the node group is created and deleted when the node group is deleted, entirely managed by EKS.

#### Node Policy Attachments (`aws_iam_role_policy_attachment.node_policies`, ×4)

Four managed policies are attached to the node role. Each covers a distinct area of node functionality:

**`AmazonEKSWorkerNodePolicy`**

Grants the permissions the kubelet needs to participate in the cluster: `ec2:DescribeInstances`, `ec2:DescribeRouteTables`, `ec2:DescribeSecurityGroups`, `ec2:DescribeSubnets`, and `ec2:DescribeVolumes` among others. The kubelet calls these APIs to discover the node's network topology, validate its placement, and self-report the node's capacity (CPU, memory, allocatable pods) to the API server. Without this policy, the kubelet can start but cannot successfully register the node.

**`AmazonEKS_CNI_Policy`**

Grants the VPC CNI DaemonSet permission to manage Elastic Network Interfaces on the node: `ec2:CreateNetworkInterface`, `ec2:AttachNetworkInterface`, `ec2:DetachNetworkInterface`, `ec2:DeleteNetworkInterface`, `ec2:AssignPrivateIpAddresses`, `ec2:UnassignPrivateIpAddresses`, and the describe variants of each.

The VPC CNI implements Kubernetes pod networking by assigning secondary private IP addresses from the node's subnets directly to pods. Each pod gets a real VPC IP address — the same address block as the node — rather than an overlay network address. When a pod is created, the CNI requests an IP from one of the node's pre-warmed secondary ENIs. This is what makes pod-to-pod traffic within the VPC routable without NAT. Without this policy, the CNI cannot allocate pod IPs and pod creation stalls with a network setup error.

**`AmazonEC2ContainerRegistryReadOnly`**

Grants `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, and `ecr:BatchCheckLayerAvailability` on all ECR repositories in the account.

The workload image (`ghcr.io/e2b-dev/sre-interview`) is pulled from the GitHub Container Registry, not ECR, so the workload itself does not need this policy. However, several EKS-managed add-ons are distributed through ECR — `kube-proxy`, `coredns`, and the VPC CNI itself use ECR images. When EKS upgrades these add-ons, the node must be able to pull from ECR. Without this policy, add-on upgrades silently fail with image pull errors.

**`AmazonSSMManagedInstanceCore`**

Grants the permissions the SSM agent needs to register the instance with Systems Manager and accept Session Manager connections: `ssm:UpdateInstanceInformation`, `ssmmessages:CreateControlChannel`, `ssmmessages:OpenControlChannel`, and related APIs.

Session Manager is the mechanism for getting a shell onto a node without configuring SSH or a bastion host. On AL2023 nodes, the SSM agent is installed and running by default — the policy alone is sufficient to enable Session Manager access. On Bottlerocket nodes, the SSM agent is not running in the default configuration; it is available only when the Bottlerocket admin container is explicitly enabled via `EC2NodeClass.spec.userData` in Karpenter, or via the launch template user data for managed node groups.

The practical value: when a pod is behaving unexpectedly at the kernel or OS level — a container escape attempt, an unexpected syscall pattern, unusually high disk or network I/O — Session Manager provides a way to inspect the host directly without pre-planned SSH configuration.

#### Managed Node Group (`aws_eks_node_group.this`)

```
cluster_name:      e2b-sre-fresh
node_group_name:   e2b-sre-fresh-default
subnet_ids:        [3 private subnets]
instance_types:    [m6i.large]
capacity_type:     ON_DEMAND
ami_type:          AL2023_x86_64_STANDARD
min_size:          2
max_size:          6
desired_size:      3
max_unavailable:   1  (during updates)
```

A managed node group is an AWS-managed Auto Scaling Group with EKS-specific integration. AWS handles node bootstrapping (registering the node with the cluster, installing kubelet, configuring networking), AMI patching, and rolling replacement during node group updates. The alternative — self-managed node groups — requires the operator to handle all of this.

**Subnet placement.** The node group receives `module.network.private_subnet_ids` — the same three private subnets passed to the cluster module. EKS distributes new nodes across all provided subnets (and therefore across all AZs) using the Auto Scaling Group's `AZRebalance` process. With three subnets and `desired_size = 3`, each AZ gets one node in the steady state, satisfying the topology spread constraints (`topologySpreadConstraints`) configured in the Helm chart.

**Instance type: `m6i.large`.** The m6i.large provides 2 vCPU and 8 GiB of memory. EKS limits the maximum number of pods per node based on the instance's ENI and secondary IP capacity: for m6i.large (3 ENIs, 10 secondary IPs each), the pod limit is `(3 × 10) − 3 + 2 = 29`. With the workload's resource requests of 100m CPU and 128Mi memory, a single m6i.large can theoretically host up to 16 replicas before memory is exhausted, well above the HPA maximum of 10. Instance type selection should be revisited if the workload's actual resource consumption (measured after deployment) differs significantly from the declared requests.

**Capacity type: `ON_DEMAND`.** On-demand instances have no interruption risk — AWS does not reclaim them without notice. Spot instances are cheaper (typically 60–90% discount) but can be interrupted with two minutes' notice when EC2 capacity is reclaimed. The Karpenter module handles spot capacity with proper interruption handling (SQS queue + EventBridge rules); for the base managed node group, on-demand is the safe default.

**Scaling configuration.** `min_size = 2` guarantees at least two nodes are always running, which matters for the PodDisruptionBudget on the workload: `minAvailable = 1` means one pod must always be running, and with two nodes, a rolling node replacement can always keep at least one pod running by first scheduling the replacement pod on the surviving node. Setting `min_size = 1` would make the workload momentarily unavailable during node replacement. `max_size = 6` caps autoscaler-driven scale-out; `desired_size = 3` is the initial target.

**`update_config { max_unavailable = 1 }`.** When the node group is updated — typically for an AMI version upgrade — EKS drains and replaces nodes in sequence. `max_unavailable = 1` means only one node is cordoned and drained at a time. With a PodDisruptionBudget on the workload (`minAvailable = 1`) and `min_size = 2`, this ensures no workload downtime during rolling node replacement: pods evicted from the draining node reschedule onto the remaining nodes before the next node is touched.

**`lifecycle { ignore_changes = [scaling_config[0].desired_size] }`.** Once cluster-autoscaler is running, it becomes the owner of the node group's desired capacity. Every scale-out or scale-in event it performs updates the Auto Scaling Group's desired count — a value Terraform also tracks. Without `ignore_changes`, the next `terraform apply` would detect a drift between `var.desired_size` (3) and the autoscaler's current value (say, 5 after a scale-out) and reset it to 3, undoing the autoscaler's work. `ignore_changes` tells Terraform to treat `desired_size` as externally managed after the initial creation.

**Dual role when Karpenter is enabled.** When `var.enable_karpenter = true` in the environment, the node group is sized as a system pool rather than a workload pool:

```hcl
min_size     = 1   # system_node_min_size
max_size     = 2   # system_node_max_size
desired_size = 1   # system_node_desired_size
labels       = { "karpenter.sh/controller" = "true" }
```

The Karpenter Helm release (in `modules/node-pool/karpenter`) configures a `nodeSelector` on its controller pod matching `karpenter.sh/controller = true`. This forces the Karpenter pod to land only on nodes in this managed group and never on nodes that Karpenter itself provisioned. The reason is a bootstrapping safety property: if the Karpenter controller runs on a Karpenter-provisioned node and that node is consolidated or interrupted, Karpenter cannot launch a replacement for itself — it is the thing that launches nodes. Running the controller on a stable, independently managed group breaks this circular dependency.

**`depends_on = [aws_iam_role_policy_attachment.node_policies]`** ensures all four policy attachments have propagated through IAM before EKS validates the node role during node group creation. EKS checks the role's policies at creation time; a race condition here would produce an intermittent IAM validation error.

### Module outputs

```hcl
node_group_arn    → informational; useful for IAM conditions scoped to this group
node_role_arn     → modules/node-pool/karpenter (to distinguish the Karpenter node role
                    from this managed-group role; both need separate Access Entries)
node_group_status → informational; reflects ACTIVE / DEGRADED / UPDATING
```

The `node_role_arn` output is used by the Karpenter module to verify that the two node roles (managed node group vs. Karpenter-provisioned nodes) are distinct and that only the Karpenter-specific role has `aws_eks_access_entry` type `EC2_LINUX` created by Karpenter's module, while this module's role gets its Access Entry auto-created by EKS in API auth mode.

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| Missing `AmazonEKSWorkerNodePolicy` | kubelet starts but cannot register the node; node stays `NotReady` indefinitely |
| Missing `AmazonEKS_CNI_Policy` | VPC CNI cannot manage ENIs; pod IP assignment fails; pods stay in `ContainerCreating` |
| Missing `AmazonEC2ContainerRegistryReadOnly` | EKS add-on upgrades fail with `ImagePullBackOff`; kube-proxy or CoreDNS version updates stall |
| Missing `AmazonSSMManagedInstanceCore` | SSM Session Manager cannot connect; no shell access to nodes without a bastion or SSH |
| `depends_on` for policy attachments removed | Intermittent IAM race at node group creation; node group occasionally fails with a role validation error |
| `http_tokens = "optional"` (IMDSv2 disabled) | IMDSv1 re-enabled; SSRF vulnerabilities on the node can exfiltrate the node's IAM credentials |
| `http_put_response_hop_limit = 1` | VPC CNI DaemonSet pods cannot reach IMDS; pod IP assignment fails cluster-wide |
| `encrypted = false` on EBS volumes | Node disk contents readable if a volume snapshot is shared or physical media is recovered |
| `delete_on_termination = false` | Orphaned EBS volumes accumulate on every node replacement; unbounded storage cost |
| `min_size = 1` | During node replacement or AZ failure, the single remaining node may not have enough capacity for the workload's PDB to be satisfied; rolling update can cause an outage |
| `ignore_changes` on `desired_size` removed | Every `terraform apply` resets node count to `var.desired_size`, fighting the cluster autoscaler and causing disruptive node churn |
| Nodes in public subnets | Worker nodes get public IPs and are directly reachable from the internet; each node's ports become an external attack surface |
