# AWS Networking — Fresh Install

**Source**: `terraform/modules/network/aws`  
**Used by**: `terraform/envs/aws-fresh`

This module builds everything that has to exist before an EKS cluster can be created: the VPC, subnets, internet and NAT gateways, and the route tables that connect them. None of the higher-level modules (cluster, node pool, platform addons) can run until this module's outputs are available.

---

## Resource inventory

With the default configuration in `envs/aws-fresh` — three availability zones, `single_nat_gateway = false` — the module creates 22 AWS resources:

| Resource type | Count | Names (defaults) |
|---|---|---|
| `aws_vpc` | 1 | `e2b-sre-fresh` |
| `aws_internet_gateway` | 1 | `e2b-sre-fresh-igw` |
| `aws_subnet` (public) | 3 | `e2b-sre-fresh-public-us-east-1{a,b,c}` |
| `aws_subnet` (private) | 3 | `e2b-sre-fresh-private-us-east-1{a,b,c}` |
| `aws_eip` | 3 | `e2b-sre-fresh-nat-eip-{0,1,2}` |
| `aws_nat_gateway` | 3 | `e2b-sre-fresh-nat-{0,1,2}` |
| `aws_route_table` (public) | 1 | `e2b-sre-fresh-public-rt` |
| `aws_route` (public internet) | 1 | *(default route → IGW)* |
| `aws_route_table_association` (public) | 3 | *(one per public subnet)* |
| `aws_route_table` (private) | 3 | `e2b-sre-fresh-private-rt-us-east-1{a,b,c}` |
| `aws_route` (private NAT) | 3 | *(one default route per private RT → local NAT GW)* |
| `aws_route_table_association` (private) | 3 | *(one per private subnet)* |

---

## Network topology

```
                         Internet
                            │
                 ┌──────────▼──────────┐
                 │   Internet Gateway  │
                 │   e2b-sre-fresh-igw │
                 └──────────┬──────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
┌─────────▼────────┐ ┌──────▼───────┐ ┌──────▼───────┐
│  Public Subnet   │ │Public Subnet │ │Public Subnet │
│  us-east-1a      │ │us-east-1b    │ │us-east-1c    │
│  10.0.128.0/20   │ │10.0.144.0/20 │ │10.0.160.0/20 │
│  [NAT GW + EIP]  │ │[NAT GW + EIP]│ │[NAT GW + EIP]│
└─────────┬────────┘ └──────┬───────┘ └──────┬───────┘
          │  (outbound only)│                 │
┌─────────▼────────┐ ┌──────▼───────┐ ┌──────▼───────┐
│  Private Subnet  │ │Private Subnet│ │Private Subnet│
│  us-east-1a      │ │us-east-1b    │ │us-east-1c    │
│  10.0.0.0/20     │ │10.0.16.0/20  │ │10.0.32.0/20  │
│  [EKS nodes]     │ │[EKS nodes]   │ │[EKS nodes]   │
└──────────────────┘ └──────────────┘ └──────────────┘
```

Traffic can enter the private subnets from the internet only through a load balancer sitting in a public subnet. Nodes in the private subnets can initiate outbound connections (to pull container images, call AWS APIs, etc.) through the NAT gateway in the same AZ, but nothing on the internet can reach a node directly.

---

## Resources in detail

### VPC (`aws_vpc`)

```
cidr_block:           10.0.0.0/16   (65,536 addresses)
enable_dns_support:   true
enable_dns_hostnames: true
```

The VPC is the private network boundary for the entire deployment. Everything — EKS control plane ENIs, worker nodes, load balancers — lives inside it.

The `/16` block is large enough to carve out multiple `/20` subnets (4,096 addresses each) per tier per AZ without address space running short. The default layout uses only a fraction:

```
10.0.0.0/20    private, us-east-1a   (4,094 usable)
10.0.16.0/20   private, us-east-1b
10.0.32.0/20   private, us-east-1c
...            (10.0.48.0 – 10.0.127.255 unallocated, available for future use)
10.0.128.0/20  public,  us-east-1a
10.0.144.0/20  public,  us-east-1b
10.0.160.0/20  public,  us-east-1c
...            (10.0.176.0 – 10.0.255.255 unallocated)
```

**`enable_dns_support = true`** turns on the Route 53 Resolver inside the VPC. Without it, hostnames don't resolve at all — pods couldn't reach `s3.amazonaws.com`, AWS service endpoints, or each other by DNS name.

**`enable_dns_hostnames = true`** gives EC2 instances public DNS hostnames (e.g. `ec2-54-x-x-x.compute-1.amazonaws.com`). For EKS specifically this also enables VPC DNS resolution for the cluster API endpoint, which is how `kubectl` and the kubelet both reach the control plane. EKS will refuse to create the cluster if this flag is off.

---

### Internet Gateway (`aws_internet_gateway`)

```
attached to: aws_vpc.this
```

An Internet Gateway is the single point through which a VPC exchanges traffic with the public internet. It performs no address translation — it maps public Elastic IPs to private addresses and passes packets between them.

The IGW is required even in a deployment where worker nodes are entirely private. It serves two purposes here:

1. **Outbound path for NAT gateways.** NAT gateways sit in public subnets. Their route tables point to this gateway for outbound traffic. Without the IGW, NAT gateways would have nowhere to send packets, and private-subnet nodes couldn't reach the internet.
2. **Public load balancer termination.** When `ingress-nginx` or the AWS Load Balancer Controller creates an internet-facing load balancer, that load balancer gets a public IP in a public subnet. Traffic from the internet arrives at the VPC through this gateway and is forwarded to the load balancer's ENI.

The `depends_on = [aws_internet_gateway.this]` on the NAT gateway resource enforces that the IGW exists before NAT gateways are created, because a NAT gateway in a public subnet can't route outbound traffic until the IGW is attached.

---

### Public Subnets (`aws_subnet.public`, ×3)

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

### Private Subnets (`aws_subnet.private`, ×3)

```
count:                    3  (one per AZ)
availability_zones:       us-east-1a, us-east-1b, us-east-1c
cidr_blocks:              10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
map_public_ip_on_launch:  false  (the default; not set explicitly)
```

Private subnets are where all EKS worker nodes run. Nodes here have no public IP address and are unreachable from the internet directly — the only inbound path is through a load balancer in a public subnet. Outbound traffic (pulling images, calling AWS APIs) goes through the NAT gateway in the same AZ.

Keeping nodes private is the standard EKS security posture. A node with a public IP is a direct attack surface; a node behind a NAT gateway is not. Even with restrictive security groups, the defence-in-depth principle strongly favours private nodes.

**Subnet tags applied:**

```
kubernetes.io/role/internal-elb       = "1"
kubernetes.io/cluster/e2b-sre-fresh   = "shared"
```

The `kubernetes.io/role/internal-elb = 1` tag serves the same role as the public subnet's `elb` tag, but for *internal* load balancers. When a Kubernetes Service of type `LoadBalancer` is created with the `internal: true` annotation (or when the ingress controller is configured for internal routing), the AWS Load Balancer Controller looks for subnets tagged with `internal-elb` to place the NLB. EKS also reads this tag when it needs to create control-plane ENIs in the VPC.

The `modules/network/existing` module — used when a customer brings their own VPC — validates that these tags are present on the supplied subnets before the plan proceeds, producing a clear error rather than a silent failure minutes later during cluster creation.

---

### Elastic IPs (`aws_eip`, ×3)

```
count:   3  (one per AZ, because single_nat_gateway = false)
domain:  "vpc"
```

An Elastic IP is a static public IPv4 address in your AWS account. NAT gateways require one: it's the source IP address that all outbound traffic from the private subnets appears to come from when it exits to the internet.

The practical significance of a static IP is that it can be added to external allowlists. If the workload calls a third-party API that restricts access by IP, the customer gives the vendor the EIP addresses (one per AZ, three in this configuration) once, and the list never changes even when nodes are replaced or autoscaled.

EIPs are created separately from NAT gateways (`aws_eip` → `aws_nat_gateway` via `allocation_id`) because AWS bills for them independently and their lifecycle is separate: if a NAT gateway is destroyed and recreated, the EIP address can be preserved.

---

### NAT Gateways (`aws_nat_gateway`, ×3)

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

None of this is possible from a private subnet without a NAT gateway (or VPC endpoints as an alternative — see note below).

**Why one per AZ, not one shared.** A NAT gateway is an Availability Zone-scoped resource. It is not replicated across AZs. If `us-east-1a` suffers a partial outage and the single NAT gateway happens to be there, every private subnet in every AZ loses outbound internet access simultaneously — the cluster's nodes can no longer reach ECR or AWS APIs, new pod scheduling stalls, and the workload degrades across all AZs, not just the affected one.

With one NAT gateway per AZ, an AZ-level event affects only the nodes in that AZ. The nodes in `us-east-1b` and `us-east-1c` continue routing through their own gateways, unaffected. This is why `single_nat_gateway = false` is the production default, even though it triples the NAT gateway cost (~$0.045/hour per gateway, plus data processing charges).

`single_nat_gateway = true` is available for cost-sensitive non-production environments and can be set in `terraform.tfvars`.

> **VPC Endpoints as an alternative.** For clusters with very high outbound data volumes, replacing NAT gateway traffic with VPC Interface Endpoints (for ECR, S3, EC2, STS, CloudWatch, etc.) can reduce both cost and latency, since traffic stays on the AWS network rather than exiting through the IGW. This is a post-initial-deployment hardening step, not a day-one requirement, and is out of scope for this module.

---

### Public Route Table and Routes

```
aws_route_table.public         (1 table, shared by all 3 public subnets)
aws_route.public_internet      destination 0.0.0.0/0  →  Internet Gateway
aws_route_table_association    (3 associations, one per public subnet)
```

A route table is the routing policy attached to a subnet. All three public subnets share a single route table because their routing is identical: local VPC traffic stays local, everything else goes to the Internet Gateway.

| Destination | Target | Added by |
|---|---|---|
| `10.0.0.0/16` | local | AWS (automatic, always present) |
| `0.0.0.0/0` | `igw-...` | `aws_route.public_internet` |

The local route (`10.0.0.0/16 → local`) is injected automatically by AWS and cannot be deleted. It ensures that traffic destined for any address inside the VPC stays inside the VPC rather than being sent out through the IGW.

The default route (`0.0.0.0/0 → IGW`) makes a subnet "public": any traffic that doesn't match a more specific route is forwarded to the Internet Gateway. Resources in a public subnet can initiate and receive internet connections through it.

---

### Private Route Tables and Routes

```
aws_route_table.private        (3 tables, one per AZ)
aws_route.private_nat          destination 0.0.0.0/0  →  NAT Gateway (per-AZ)
aws_route_table_association    (3 associations, one per private subnet)
```

Each private subnet gets its own route table rather than sharing one, so each can route outbound traffic to the NAT gateway in its own AZ.

| Destination | Target | Added by |
|---|---|---|
| `10.0.0.0/16` | local | AWS (automatic) |
| `0.0.0.0/0` | `nat-...` (same AZ) | `aws_route.private_nat` |

**Why per-AZ route tables matter.** If all three private subnets shared one route table pointing to a single NAT gateway, traffic from a node in `us-east-1b` to the internet would travel cross-AZ to reach the gateway in `us-east-1a`, incur cross-AZ data transfer charges, and add latency. More importantly, it reintroduces the single-NAT-gateway failure mode at the routing level even if three NAT gateways exist. Per-AZ route tables ensure each subnet's traffic stays within the AZ for as long as possible before exiting.

When `single_nat_gateway = true`, all three private route tables are created but each points to the single shared NAT gateway — the structure is the same, only the target changes.

---

## Module outputs

```hcl
vpc_id             → consumed by modules/cluster/aws-eks (vpc_config block)
private_subnet_ids → consumed by modules/cluster/aws-eks (control-plane ENIs)
                     and modules/node-pool/aws-eks (node launch subnets)
public_subnet_ids  → available for load balancer subnet references
azs                → available for downstream AZ-aware resources
```

The output contract (`vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `azs`) is identical to the one exposed by `modules/network/existing`, which looks up a customer's pre-existing VPC instead of creating one. The `envs/` root modules compose against this shape regardless of which implementation is behind it — swapping from fresh to existing is a one-line source change with no downstream edits required.

---

## What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| `enable_dns_hostnames = false` | EKS cluster creation rejected; kubelet can't resolve the API endpoint |
| Missing `kubernetes.io/role/internal-elb` tag on private subnets | Internal load balancers silently fail to provision; Service stays in `Pending` |
| Missing `kubernetes.io/role/elb` tag on public subnets | Internet-facing load balancers fail; ingress controller errors |
| Single NAT gateway in production | AZ outage kills all outbound internet access across the cluster |
| Private subnets in fewer than 2 AZs | Terraform validation error before any resources are created (enforced by `var.azs` validation block) |
| Private subnets in only 1 AZ | EKS API rejects the cluster; EKS requires control-plane ENIs in at least 2 AZs |
