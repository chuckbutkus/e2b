# GCP Fresh Install — Resource Reference

**Environment**: `terraform/envs/gcp-fresh`

This document describes every resource created by each Terraform module in the fresh GCP install path, what each resource does, and why it matters. Modules are documented in dependency order. Where the GCP design differs meaningfully from its AWS counterpart in `docs/aws-fresh-networking.md`, the difference is called out directly.

---

## 1. Network (`modules/network/gcp`)

**Source**: `terraform/modules/network/gcp`

This module creates the VPC, the single regional subnet that carries both nodes and pod IPs, Cloud NAT for outbound internet access from private nodes, and the baseline firewall rule that allows internal cluster traffic. It produces the four outputs the cluster module needs: the network and subnetwork self-links, and the names of the two secondary IP ranges.

### Structural difference from AWS

On AWS, network isolation is achieved with separate public and private subnets per availability zone. GCP subnets are regional — a single subnet spans all zones in the region automatically. There is no concept of a public subnet in the same sense: GCP nodes either have or don't have external IP addresses, and outbound internet access from private nodes is handled by Cloud NAT rather than by being placed in a different subnet with a NAT gateway in it.

The result is a simpler topology: one subnet with two secondary IP ranges, rather than six subnets (three public, three private) with three Elastic IPs and three NAT gateways.

### Network topology

```
                         Internet
                            │
              ┌─────────────┴──────────────┐
              │                            │
    [Cloud NAT]  (outbound from nodes      │
    [+ Router ]   and pods, no external    │
                  IPs needed on instances) │
                                           │
                     [GCP Load Balancer]   │
                     (ingress-nginx svc    │
                      type:LoadBalancer)   │
                            │
  ┌─────────────────────────▼──────────────────────────────┐
  │  VPC:  e2b-sre-gcp-fresh                               │
  │                                                         │
  │  Subnet: e2b-sre-gcp-fresh-nodes  (regional, us-east1)  │
  │  Primary range:   10.0.0.0/20   ← GKE node IPs         │
  │  Secondary range: 10.4.0.0/14   ← pod IPs (alias IP)   │
  │  Secondary range: 10.8.0.0/20   ← service ClusterIPs   │
  │                                                         │
  │  Firewall: allow-internal                               │
  │  (TCP/UDP/ICMP within node + pod + service CIDRs)       │
  └─────────────────────────────────────────────────────────┘
```

### Resource inventory

| Resource type | Count | Name (default) |
|---|---|---|
| `google_compute_network` | 1 | `e2b-sre-gcp-fresh` |
| `google_compute_subnetwork` | 1 | `e2b-sre-gcp-fresh-nodes` |
| `google_compute_router` | 1 | `e2b-sre-gcp-fresh-router` |
| `google_compute_router_nat` | 1 | `e2b-sre-gcp-fresh-nat` |
| `google_compute_firewall` | 1 | `e2b-sre-gcp-fresh-allow-internal` |

### Resources in detail

#### VPC (`google_compute_network.this`)

```
name:                    e2b-sre-gcp-fresh
auto_create_subnetworks: false
```

`auto_create_subnetworks = false` selects custom-mode networking. In auto mode, GCP creates a subnet in every region automatically, each with the same default CIDR. Custom mode prevents this: no subnets exist until explicitly declared. For a GKE cluster with intentional CIDR planning (especially the secondary ranges that alias IP networking requires), auto mode is inappropriate — it creates subnets with ranges that might overlap the secondary ranges, and it wastes address space in regions that won't be used.

Unlike an AWS VPC, a GCP VPC is a global resource — it spans all regions. Subnets are regional. The VPC itself has no CIDR; the CIDRs live on the subnets.

#### Subnetwork (`google_compute_subnetwork.this`)

```
name:              e2b-sre-gcp-fresh-nodes
region:            us-east1
ip_cidr_range:     10.0.0.0/20    (4,094 node IPs)
secondary ranges:
  e2b-sre-gcp-fresh-pods:      10.4.0.0/14    (262,144 pod IPs)
  e2b-sre-gcp-fresh-services:  10.8.0.0/20    (4,094 service ClusterIPs)
private_ip_google_access: true
```

GKE's VPC-native networking (alias IP) requires named secondary ranges on the subnet. These are not separate subnets — they are additional CIDR blocks defined on the same subnet resource. The three ranges serve distinct purposes:

**Primary range (`10.0.0.0/20`): node IPs.** Each GKE node receives one IP from this range as its primary internal address. A /20 supports up to 4,094 nodes, which is well above GKE's regional cluster limit of 15,000 nodes per cluster (though practical limits are lower). Node IPs are routable within the VPC and reachable from other GCP resources in the same network.

**First secondary range (`10.4.0.0/14`): pod IPs.** GKE allocates a `/24` slice from this range to each node (256 addresses, ~110 usable given GKE's per-node pod limit). A `/14` provides 262,144 addresses — enough for 1,024 nodes' worth of pod capacity. Pod IPs are routable within the VPC without NAT. A pod in `us-east1-a` can open a direct TCP connection to a pod in `us-east1-c` using its pod IP, with no VXLAN overlay or address translation in between. This is the alias IP model: GCP programs the VPC's routing fabric to know which pod CIDR lives on which node, and routes packets directly to the correct host.

**Second secondary range (`10.8.0.0/20`): service ClusterIPs.** When a Kubernetes Service is created, its ClusterIP is allocated from this range. These IPs are not real VPC routes — they exist only within kube-proxy's iptables rules on each node and are translated to pod IPs before packets leave the node. The range needs to be large enough for all Services ever created in the cluster (a /20 provides ~4,000 service IPs, which is generous for most deployments).

**`private_ip_google_access = true`.** Nodes in this subnet have no external IPs. Normally, that would mean they cannot reach any external address — including Google's own APIs. Private Google Access is a VPC routing feature that allows instances without external IPs to reach Google APIs and services (Cloud Storage, Artifact Registry, Cloud Logging, the GKE metadata server) via Google's internal network rather than requiring an external IP or Cloud NAT. This is required for private GKE nodes: without it, nodes cannot pull images from Artifact Registry, cannot push logs to Cloud Logging, and cannot communicate with GKE's own management plane.

#### Cloud Router (`google_compute_router.this`)

```
name:    e2b-sre-gcp-fresh-router
region:  us-east1
network: e2b-sre-gcp-fresh
```

A Cloud Router is the regional control-plane component that Cloud NAT attaches to. It is not a router in the traditional sense — it does not route traffic itself. Instead, it provides a BGP configuration plane and serves as the anchor point for Cloud NAT configuration within a region. Cloud NAT cannot exist without a Cloud Router.

On AWS, this function is implicit in the NAT gateway and route table structure. On GCP, it is an explicit resource.

#### Cloud NAT (`google_compute_router_nat.this`)

```
name:                            e2b-sre-gcp-fresh-nat
nat_ip_allocate_option:          AUTO_ONLY
source_subnetwork_ip_ranges:     ALL_SUBNETWORKS_ALL_IP_RANGES
log_config:                      ERRORS_ONLY
```

Cloud NAT provides outbound internet access for instances that have no external IP address. Nodes in the private subnet use it to pull container images from `ghcr.io` and other non-Google registries, and pods use it for any internet egress not covered by Private Google Access.

**`nat_ip_allocate_option = "AUTO_ONLY"`.** GCP automatically allocates and manages external IP addresses for the NAT gateway. The alternative (`MANUAL_ONLY`) lets you reserve specific static IPs, which is useful when external services need to allowlist your egress IPs. With `AUTO_ONLY`, GCP may change the NAT IPs over time. If the workload needs to allowlist egress IPs with third-party APIs, switch to `MANUAL_ONLY` and reserve static external IPs in Terraform.

**`source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"`.** Applies NAT to both the primary (node) and secondary (pod) ranges in the subnet. Pod IPs are routable within the VPC via alias IP routing, but when a pod originates traffic destined for the internet, NAT is still required. This setting ensures pod-originated internet egress works without additional configuration.

**Regional, not per-zone.** Unlike AWS NAT gateways, which are per-AZ resources that require one per zone for resilience, Cloud NAT is a regional, distributed service. There is no single point of failure for Cloud NAT within a region — GCP distributes the NAT capacity across zones automatically. A single `google_compute_router_nat` resource provides resilient NAT for the entire region.

**`log_config { filter = "ERRORS_ONLY" }`.** Logs only failed NAT translations (packets that could not be translated, typically due to port exhaustion). Logging all translations would capture every outbound connection from every pod, generating very high log volume and cost. Errors-only logging preserves visibility into NAT failures without the noise.

#### Internal Firewall Rule (`google_compute_firewall.internal`)

```
name:          e2b-sre-gcp-fresh-allow-internal
source_ranges: 10.0.0.0/20, 10.4.0.0/14, 10.8.0.0/20
allow:         tcp 0-65535, udp 0-65535, icmp
```

GCP VPCs have implicit deny-all ingress and allow-all egress by default, unlike AWS security groups which start with stateful tracking. Without an explicit rule permitting intra-cluster traffic, nodes cannot communicate with each other, pods cannot reach other pods on different nodes, and health checks fail.

This rule allows all TCP, UDP, and ICMP traffic between the three CIDRs: node IPs, pod IPs, and service ClusterIPs. It is the GCP equivalent of the EKS cluster security group — it creates the permissive intra-cluster communication baseline.

GKE automatically creates and manages the additional firewall rules needed for the control plane to reach nodes (for webhook admission, health probes, and node registration). Those rules are deliberately not declared here: Terraform would conflict with GKE's own reconciliation of them, causing plan noise and potential rule deletion.

### Module outputs

```hcl
network_id           → not used in gcp-fresh directly (available for peering/VPN config)
network_self_link    → modules/cluster/gcp-gke (network field)
subnetwork_self_link → modules/cluster/gcp-gke (subnetwork field)
subnetwork_name      → available for direct kubectl or gcloud references
pods_range_name      → modules/cluster/gcp-gke (cluster_secondary_range_name)
services_range_name  → modules/cluster/gcp-gke (services_secondary_range_name)
```

The output contract is deliberately different from the AWS network module's (`vpc_id`, `public_subnet_ids`, `private_subnet_ids`). GCP's networking model — one regional subnet with named secondary ranges — genuinely does not map onto the AWS multi-subnet shape. Forcing a shared interface would hide the real difference and create a false impression of portability at the network layer.

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| `auto_create_subnetworks = true` | GCP creates subnets in every region with default CIDRs; secondary ranges cannot be added after creation; cluster module fails on the ip_allocation_policy block |
| Pod CIDR too small (e.g. `/20`) | GKE allocates a /24 per node; a /20 supports only 16 nodes before pod IPs are exhausted; new nodes fail to join |
| Pod CIDR overlaps node or service CIDR | GKE rejects the cluster creation with a CIDR overlap error |
| `private_ip_google_access = false` | Nodes cannot reach Artifact Registry, Cloud Logging, or GKE management APIs; node bootstrapping fails |
| Cloud NAT not created | Pods and nodes cannot reach non-Google internet addresses; image pulls from ghcr.io fail |
| `source_subnetwork_ip_ranges` set to primary only | Pod-originated internet traffic is not NAT'd; pods cannot reach external endpoints |
| Internal firewall rule missing | Pods on different nodes cannot communicate; GKE readiness/liveness probes fail across nodes |
| Secondary range names passed to cluster module incorrect | Cluster creation fails: GKE cannot find the named secondary ranges on the subnetwork |

---

## 2. GKE Cluster (`modules/cluster/gcp-gke`)

**Source**: `terraform/modules/cluster/gcp-gke`  
**Receives from network module**: `network_self_link`, `subnetwork_self_link`, `pods_range_name`, `services_range_name`

This module creates a single `google_container_cluster` resource. GKE manages its control plane as a fully managed service — far more so than EKS. The Kubernetes API server, etcd, the scheduler, and the controller manager all run in Google's infrastructure and are never visible in the customer's GCP project. The cluster resource declares configuration that GKE uses to set up and maintain that infrastructure.

### Resource inventory

| Resource type | Count | Name (default) |
|---|---|---|
| `google_container_cluster` | 1 | `e2b-sre-gcp-fresh` |

### Resources in detail

#### GKE Cluster (`google_container_cluster.this`)

```
name:                    e2b-sre-gcp-fresh
location:                us-east1   (regional)
networking_mode:         VPC_NATIVE
remove_default_node_pool: true
initial_node_count:       1
enable_private_nodes:     true
enable_private_endpoint:  false
master_ipv4_cidr_block:   172.16.0.0/28
master_authorized_networks: ["0.0.0.0/0"]
workload_pool:            <project_id>.svc.id.goog
release_channel:          REGULAR
deletion_protection:      false
```

**Regional location.** Setting `location = "us-east1"` creates a regional cluster: GKE replicates the control plane across all zones in `us-east1` (typically three zones). If one zone loses its control plane replica, the cluster continues operating. A zonal cluster (e.g. `location = "us-east1-b"`) runs a single-zone control plane that becomes unavailable during zone events. The regional configuration is analogous to how EKS automatically distributes its managed control plane across AZs — except on GKE it is explicit in the `location` value.

**`remove_default_node_pool = true` and `initial_node_count = 1`.** The GKE API requires at least one node to exist when a cluster is created. The Terraform provider creates a single-node default pool to satisfy this requirement, then immediately deletes it. The actual node pool is managed by the separate `google_container_node_pool` resource in `modules/node-pool/gcp-gke`. This separation is necessary for clean Terraform state: if the node pool were defined inside the cluster resource and also as a separate resource, the provider would conflict with itself on every plan. The temporary node is an implementation detail; it produces no lasting compute cost.

**VPC-native networking.** `networking_mode = "VPC_NATIVE"` enables alias IP routing. The `ip_allocation_policy` block tells GKE which named secondary ranges (from the network module) to use for pod and service IPs. Without this, GKE falls back to routes-based networking, which does not use alias IPs, is not compatible with some GKE features, and requires VPC routes that have scaling limits. VPC-native mode is the current standard and is required for certain network policies and load balancer modes.

**Private nodes.** `enable_private_nodes = true` in the `private_cluster_config` block removes external IP addresses from all GKE nodes. Nodes get their IP from the primary subnet range only; they have no public interface. Outbound internet access goes through Cloud NAT (section 1). This is the GCP equivalent of placing EC2 nodes in private subnets on AWS — nodes are not directly reachable from the internet.

**Control plane access.** GKE's regional control plane runs in a Google-managed VPC. The `master_ipv4_cidr_block = "172.16.0.0/28"` allocates a `/28` in the customer VPC for a peering connection between Google's managed project and the customer's VPC. This peered range is how the private API endpoint (`kubectl` via VPN or from within the VPC) reaches the control plane. The range must not overlap any existing VPC range (node, pod, or service CIDRs).

`enable_private_endpoint = false` (the default) keeps the control plane's public endpoint available, protected by `master_authorized_networks`. This parallels EKS's `endpoint_public_access = true` + `public_access_cidrs`. Setting `enable_private_endpoint = true` removes the public endpoint entirely; `kubectl` must then originate from within the VPC or over a VPN/Interconnect.

`master_authorized_networks` defaults to `["0.0.0.0/0"]` — permissive for initial setup. Restrict this to operator IP ranges or VPN CIDRs before exposing the cluster to production traffic.

**Workload Identity.** `workload_identity_config { workload_pool = "<project_id>.svc.id.goog" }` enables GKE Workload Identity at the cluster level. This is the GCP equivalent of the EKS OIDC provider registration in section 2 of the AWS document — but with a critical difference:

On AWS, each cluster has its own unique OIDC issuer URL, which must be explicitly registered as an IAM identity provider before IRSA works. On GCP, the workload pool `<project_id>.svc.id.goog` is a fixed, permanent, per-project resource that requires no registration step. Every GKE cluster in the project shares the same workload pool identifier. This configuration tells GKE to enable the in-cluster plumbing (the GKE metadata proxy on nodes) that makes Workload Identity token exchange work. There is no separate "register an OIDC provider" step.

**Release channel.** `release_channel { channel = "REGULAR" }` opts the cluster into GKE's managed upgrade cadence. REGULAR receives GKE-optimized Kubernetes minor version upgrades roughly two to four weeks after they reach general availability, along with security patches. RAPID receives upgrades sooner; STABLE receives them later (with longer soak time). The release channel replaces the EKS `kubernetes_version` variable: rather than pinning a specific version, you pick a cadence and let Google manage the version progression. Auto-upgrades of both the control plane and node pools (enabled by `management.auto_upgrade = true` in the node pool module) align with the selected channel.

**Logging and monitoring.** `logging_config { enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"] }` ships Kubernetes system component logs (api-server, scheduler, etcd, controller-manager) and workload pod logs to Cloud Logging. `monitoring_config { enable_components = ["SYSTEM_COMPONENTS"] }` ships cluster metrics to Cloud Monitoring. These are the GCP equivalents of EKS's `enabled_cluster_log_types` — GKE routes them to Cloud Logging automatically rather than requiring a separately managed CloudWatch log group.

**`deletion_protection = false`.** GKE provides a native deletion protection flag that prevents `terraform destroy` (and the gcloud CLI) from deleting the cluster. The default here is `false` to allow easy teardown during development and testing. Any cluster serving real traffic should have this set to `true` in `terraform.tfvars`.

### Module outputs

```hcl
cluster_name        → modules/node-pool/gcp-gke (cluster), modules/k8s-platform,
                       kubernetes and helm providers
cluster_endpoint    → kubernetes and helm providers (host)
cluster_ca_certificate → kubernetes and helm providers  [sensitive]
cluster_location    → informational; passed to gcloud commands for kubeconfig setup
workload_pool       → modules/workload-identity (workload_pool)
cluster_id          → informational
master_version      → informational; reflects the current control plane version
```

`cluster_ca_certificate` is `sensitive = true` — redacted in plan output, not shown by `terraform output` without `--raw`. The kubernetes and helm providers use it to verify the API server's TLS certificate when applying the platform addon charts.

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| `location` set to a zone instead of a region | Single-zone control plane; unavailable during zone maintenance events |
| `remove_default_node_pool = false` | Default node pool created with Compute Engine default SA (over-permissioned) and no custom configuration; separate node pool resource fights the cluster resource in Terraform state |
| `networking_mode` left as default routes-based | Alias IP / VPC-native features unavailable; some network policies and load balancer modes unsupported |
| `ip_allocation_policy` range names pointing to non-existent secondary ranges | Cluster creation fails: GKE cannot allocate pod or service IPs |
| `workload_identity_config` omitted | Workload Identity not enabled at cluster level; pod token exchange fails regardless of node-level configuration |
| `enable_private_nodes = false` | Nodes receive external IPs; directly reachable from internet on all open ports |
| `master_ipv4_cidr_block` overlaps node/pod/service CIDRs | Cluster creation rejected with a CIDR overlap error |
| `deletion_protection = true` in a test environment | `terraform destroy` fails; requires manually setting `deletion_protection = false` in the GCP console before destruction |

---

## 3. Node Pool (`modules/node-pool/gcp-gke`)

**Source**: `terraform/modules/node-pool/gcp-gke`  
**Receives from cluster module**: `cluster_name`

This module creates the GKE node pool and the Google Service Account the nodes run as. Its most significant structural difference from the AWS node pool module is the `autoscaling {}` block: on GKE, the cluster autoscaler is a built-in feature of the node pool resource, not a separately deployed Helm chart. No external controller is required, and no IRSA or Workload Identity binding is needed to grant autoscaling permissions — GKE manages scaling internally.

### Resource inventory

| Resource type | Count | Name (default) |
|---|---|---|
| `google_service_account` | 1 | `e2b-sre-gcp-fresh-node` |
| `google_project_iam_member` | 4 | *(one per role; see below)* |
| `google_container_node_pool` | 1 | `e2b-sre-gcp-fresh-default` |

### Resources in detail

#### Node Service Account (`google_service_account.node`)

```
account_id:   e2b-sre-gcp-fresh-node
email:        e2b-sre-gcp-fresh-node@<project_id>.iam.gserviceaccount.com
```

GKE's default behaviour is to run nodes as the Compute Engine default service account, which has the `Editor` role on the project — an extremely broad grant that covers almost every GCP API. Running nodes as the default SA violates least-privilege: any workload that can reach the GCE metadata server on a node could potentially obtain credentials for `Editor`-level access.

This module creates a dedicated, minimal service account instead. The node SA is the GCP analogue of the AWS node IAM role from section 3 of the AWS document: it covers the infrastructure-level operations the node itself needs, not the application-level operations workload pods need. Workload pods get their own credentials through Workload Identity (section 5).

#### Node IAM Bindings (`google_project_iam_member.node`, ×4)

GCP IAM works differently from AWS IAM. There are no policy documents attached to roles; instead, IAM bindings on a resource (here the project) grant a member (the node SA) a predefined role. The four bindings are:

| Role | Purpose |
|---|---|
| `roles/logging.logWriter` | Allow the node to push structured logs to Cloud Logging. The Logging agent on each node (built into COS and Ubuntu) uses the node SA to authenticate. Without this, node-level and system component logs are silently dropped. |
| `roles/monitoring.metricWriter` | Allow the node to push metrics to Cloud Monitoring. The GKE metrics agent writes node-level CPU, memory, and disk metrics using this role. Without it, node metrics are absent from Cloud Monitoring dashboards and alerting policies. |
| `roles/monitoring.viewer` | Allow the node to read monitoring data. Required by some GKE system components that query their own health metrics. |
| `roles/artifactregistry.reader` | Allow nodes to pull container images from Artifact Registry repositories in the project. Even if the workload image comes from ghcr.io, GKE add-ons (GKE Dataplane V2, network components) are distributed through Artifact Registry. Without this, add-on upgrades fail with a permission-denied error on image pull. |

These are project-level bindings — they grant the SA access to all Artifact Registry repos, all Cloud Logging streams, and all Cloud Monitoring namespaces in the project. More granular bindings (to specific repos or log sinks) are possible but require knowing those resource names at Terraform time, and GKE's own add-on images may live in GCP-managed repos the customer cannot reference.

**`depends_on = [google_project_iam_member.node]`** on the node pool resource ensures IAM bindings have propagated through GCP's IAM system before GKE validates the SA when creating the node pool. IAM propagation in GCP is eventually consistent; without this dependency, node pool creation occasionally fails with a SA permission validation error.

#### Node Pool (`google_container_node_pool.this`)

```
name:              e2b-sre-gcp-fresh-default
location:          us-east1   (regional — nodes spread across zones automatically)
machine_type:      e2-standard-4   (4 vCPU, 16 GiB)
image_type:        COS_CONTAINERD
disk_size_gb:      100
disk_type:         pd-ssd
spot:              false
min_node_count:    2
max_node_count:    6
initial_node_count: 3
max_surge:         1
max_unavailable:   0
auto_repair:       true
auto_upgrade:      true
workload_metadata_config: GKE_METADATA
```

**Regional node pool and automatic zone distribution.** Because the cluster's location is `us-east1` (a region), the node pool is also regional. GKE distributes nodes across all zones in the region automatically, maintaining balance. With `initial_node_count = 3` across three zones in `us-east1`, each zone starts with one node. The cluster autoscaler maintains this balance as it scales. Unlike the AWS setup — where explicit per-AZ subnet IDs drive the placement — no per-zone configuration is needed here.

**Machine type: `e2-standard-4`.** The e2-standard-4 provides 4 vCPU and 16 GiB of memory. GKE's default per-node pod limit is 110 pods (configurable, but 110 is the standard maximum). With the workload's resource requests of 100m CPU and 128Mi memory, a single e2-standard-4 can host up to 40 replicas by CPU and 128 by memory — well above the HPA's maximum of 10. The e2 machine family is cost-optimised, using a mix of Intel and AMD hardware under a fixed-performance model.

**Image type: `COS_CONTAINERD`.** Container-Optimized OS is Google's minimal, security-hardened node operating system. It has a read-only root filesystem, runs only the components needed for container execution, and receives automatic security updates from Google. Its role is analogous to Bottlerocket on AWS (also minimal and container-focused), but COS is GCP-specific — Bottlerocket is not available on GKE. `UBUNTU_CONTAINERD` is the alternative for workloads that require full Ubuntu tooling on the node.

**Disk: `pd-ssd`, 100 GiB.** Persistent Disk SSD provides consistent IOPS and throughput. A 100 GiB pd-ssd delivers approximately 3,000 IOPS and 120 MB/s. The AWS equivalent in the node pool is `gp3` with explicitly set IOPS; pd-ssd is the GCP standard for production node disks. The larger default size (100 GiB vs 50 GiB on AWS) reflects that COS nodes use a single volume for both the OS and container image layers, unlike Bottlerocket's two-partition split.

**Native autoscaling.** The `autoscaling { min_node_count = 2, max_node_count = 6 }` block enables GKE's built-in cluster autoscaler. This is the single most important structural difference from the AWS node pool: on GKE, this block IS the autoscaler. When pods are unschedulable due to insufficient node capacity, GKE adds a node. When nodes are underutilised, GKE removes one. No separate Helm chart, no IRSA role, no AWS API permissions, and no `cluster_autoscaler_role_arn` are needed — GKE handles this internally. The `install_cluster_autoscaler = false` flag passed to `modules/k8s-platform` in the env reflects this.

**Upgrade strategy: surge upgrade.** `upgrade_settings { max_surge = 1, max_unavailable = 0 }` selects surge upgrades over in-place replacement. During a node pool upgrade (triggered by GKE's auto-upgrade mechanism or a manual change), GKE adds one new node (the surge node) with the new configuration, waits for it to become Ready and for pods to be rescheduled onto it, then removes one old node. `max_unavailable = 0` ensures capacity never drops below the current node count during the upgrade. On AWS, the node group uses `max_unavailable = 1` (removes an old node before adding a new one); the GCP approach is conservative in the opposite direction — add first, remove later.

**`management { auto_repair = true, auto_upgrade = true }`.** Auto-repair detects nodes that become unhealthy (fail repeated health checks) and recreates them automatically. Auto-upgrade allows GKE to upgrade the node pool's Kubernetes version automatically when the control plane's version advances, following the selected release channel. Both settings transfer operational responsibility to GKE and are appropriate for production; disabling either requires the operator to manually monitor node health and apply version upgrades.

**Workload metadata mode.** `workload_metadata_config { mode = "GKE_METADATA" }` is the node-side requirement for Workload Identity, complementing the cluster-level `workload_identity_config`. By default, GCE nodes expose the raw GCE metadata server to all processes — including pods. A pod that can reach `http://169.254.169.254` can request the node SA's credentials directly, bypassing Workload Identity entirely. `GKE_METADATA` mode replaces the metadata server exposure with GKE's metadata proxy. The proxy intercepts requests, identifies the calling pod's ServiceAccount, checks whether that KSA is bound to a GSA via a Workload Identity binding, and issues tokens only for the bound GSA. Pods that are not bound to any GSA receive an error rather than the node SA's credentials. This is the node-level enforcement that makes Workload Identity's security properties hold.

**`oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]`.** This grants the node SA access to any GCP API it has IAM permissions for, controlled by the project IAM bindings above. The alternative — listing specific API scopes — is more restrictive but requires knowing every API the node needs access to at Terraform time. When the node SA has minimal IAM roles (the four above), the broad scope does not produce excess access in practice: the scope is the ceiling, and IAM is the effective grant.

**`lifecycle { ignore_changes = [initial_node_count] }`.** Once the GKE cluster autoscaler is running, it owns the node count. `initial_node_count` is used only at pool creation; GKE updates it as it scales. `ignore_changes` prevents Terraform from resetting the pool to its original count on the next apply, for the same reason as the `ignore_changes` on `desired_size` in the AWS node pool module.

### Module outputs

```hcl
node_service_account_email → informational; useful for granting the node SA
                              access to additional GCP resources if needed;
                              also needed when configuring Workload Identity
                              bindings that need to know the node SA identity
node_pool_id               → informational
```

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| Node SA not created (using Compute Engine default SA) | Nodes run with `Editor`-level GCP access; any pod that reaches the metadata server can obtain near-admin credentials |
| Missing `roles/logging.logWriter` | Node and system component logs silently dropped; no visibility into node-level errors |
| Missing `roles/artifactregistry.reader` | GKE add-on image pulls fail during cluster upgrades |
| `depends_on` for IAM bindings removed | Intermittent IAM propagation race at node pool creation; SA validation fails ~10% of the time |
| `workload_metadata_config` omitted or set to `EXPOSE` | GCE metadata server exposed to pods; Workload Identity bindings can be bypassed; node SA credentials accessible to all pods |
| `auto_upgrade = false` | Node pool falls behind the control plane version; GKE eventually prevents the version gap from exceeding two minor versions, forcing a manual upgrade with potential disruption |
| `auto_repair = false` | Unhealthy nodes remain in the pool indefinitely; pods evicted from unhealthy nodes are not re-schedulable until the node is manually replaced |
| `max_unavailable = 1` instead of `max_surge = 1` | Node count temporarily drops during upgrades, potentially violating the workload's PodDisruptionBudget |
| `spot = true` without application-level disruption handling | Spot VMs interrupted with ~30 seconds' notice on GCP (less than AWS's 2 minutes); workload pods may be terminated before rescheduling completes |
| `ignore_changes` on `initial_node_count` removed | Every `terraform apply` resets pool to `var.initial_count`, fighting GKE's native autoscaler |

---

## 4. Kubernetes Platform Addons (`modules/k8s-platform`)

**Source**: `terraform/modules/k8s-platform`  
**Receives from cluster module**: `cluster_name`  
**Depends on**: node pool (nodes must be Ready before Helm can schedule pods)

The same shared module used by the AWS path. On GCP, it is called with `install_cluster_autoscaler = false` — the GKE native autoscaler from section 3 handles that function, and installing the separate Helm-based cluster-autoscaler alongside it would create a conflict.

### What is and is not installed on GCP

| Chart | Installed | Reason |
|---|---|---|
| metrics-server | ✅ yes | HPA still requires a metrics source on GKE |
| ingress-nginx | ✅ yes | The same Nginx ingress controller works on GKE |
| cluster-autoscaler | ❌ no | GKE native autoscaler handles this; running both would conflict |

### GCP-specific behaviour

**metrics-server** installs identically to the AWS path. GKE does not include a metrics-server by default (despite what some documentation implies — GKE includes the older Heapster for Cloud Monitoring integration, not the Metrics API server that HPA uses). The chart and settings are unchanged.

**ingress-nginx** creates a Service of type `LoadBalancer`. On GKE, the in-tree cloud controller (not the AWS Load Balancer Controller) handles `LoadBalancer` service provisioning. It provisions a Google Cloud Network Load Balancer (pass-through L4 NLB) and assigns it an external IP from Google's address pool. The `service.beta.kubernetes.io/aws-load-balancer-type: nlb` annotation in the module is AWS-specific and is silently ignored by GKE — no error, no effect. GCP already provisions an NLB-equivalent by default without requiring any annotation.

The practical result is that ingress-nginx on GKE receives an external IP that routes through a GCP NLB to the ingress controller pods, which then route HTTP/S traffic to Kubernetes Services based on Ingress rules. The behaviour is the same as on AWS; only the underlying cloud load balancer product differs.

**`depends_on = [module.node_pool]`** applies for the same reason as on AWS: Helm chart installation requires Ready nodes to schedule the metrics-server and ingress-nginx pods onto.

---

## 5. Workload Identity (`modules/workload-identity`)

**Source**: `terraform/modules/workload-identity`  
**Receives from cluster module**: `workload_pool`  
**Status in gcp-fresh**: commented out (same pattern as the workload IRSA on the AWS side — used when the workload requires GCP API access)

Workload Identity is GKE's mechanism for giving pods access to GCP APIs without static service account keys. It is the GCP equivalent of AWS IRSA. The `modules/workload-identity` module is the GCP equivalent of `modules/irsa`.

This module is not actively instantiated in `gcp-fresh` because the `ghcr.io/e2b-dev/sre-interview` workload has not been confirmed to need GCP API access. When it does, a single uncomment enables the binding.

### Resource inventory (when used)

| Resource type | Count | Name (example) |
|---|---|---|
| `google_service_account` | 1 | `e2b-sre-gcp-fresh-sre-workload` |
| `google_project_iam_member` | N | *(one per role in `project_roles`)* |
| `google_service_account_iam_member` | 1 | *(the Workload Identity binding itself)* |

### Resources in detail

#### Google Service Account (`google_service_account.this`)

```
account_id:   <gsa_account_id>
email:        <gsa_account_id>@<project_id>.iam.gserviceaccount.com
```

A Google Service Account is a GCP identity, not a Kubernetes concept. It exists in IAM and can be granted access to GCP APIs. Workload Identity establishes a link between a Kubernetes ServiceAccount (which exists in the cluster) and a Google Service Account (which exists in GCP IAM), allowing pods running under the KSA to impersonate the GSA and obtain GCP API tokens.

#### Project IAM Bindings (`google_project_iam_member.roles`)

These grant the GSA project-level access to GCP APIs. `project_roles` defaults to an empty list (the workload gets a GSA with no GCP access). Roles are added based on what the workload needs — for example:
- `roles/storage.objectViewer` for reading from Cloud Storage
- `roles/secretmanager.secretAccessor` for reading secrets from Secret Manager

The GCP binding model differs from the AWS inline-or-managed policy model: every permission grant is a role-on-resource binding (`member has role on resource`), not a policy document attached to an identity. There are no inline policies. Predefined roles are the standard unit of permission.

#### Workload Identity Binding (`google_service_account_iam_member.workload_identity_binding`)

```
role:    roles/iam.workloadIdentityUser
member:  serviceAccount:<project_id>.svc.id.goog[<namespace>/<ksa_name>]
```

This single IAM binding is the entire federation mechanism. It grants `roles/iam.workloadIdentityUser` on the GSA to the Kubernetes ServiceAccount, identified by the Workload Identity pool member syntax: `serviceAccount:<workload_pool>[<namespace>/<ksa_name>]`.

**Comparison to AWS IRSA.** The binding replaces three distinct IRSA components:

| AWS IRSA component | GCP Workload Identity equivalent |
|---|---|
| `aws_iam_openid_connect_provider` (register cluster OIDC issuer) | Not needed — `<project_id>.svc.id.goog` is a permanent per-project pool |
| Trust policy `StringEquals` on `:sub` claim | The `[namespace/ksa_name]` suffix in the member string |
| Trust policy `StringEquals` on `:aud` claim | Handled internally by GKE's metadata proxy |

The IRSA pattern requires explicit OIDC provider registration per cluster, a multi-condition trust policy, and a separate AWS STS exchange. The Workload Identity binding achieves the same scope restriction in one IAM binding, using a per-project pool that never needs to be registered.

**How the token exchange works at runtime:**
1. The pod's ServiceAccount is annotated with `iam.gke.io/gcp-service-account: <gsa_email>`.
2. When the pod starts, GKE's node-level metadata proxy (`GKE_METADATA` mode from section 3) is active.
3. The pod's AWS SDK — or any GCP client library — requests credentials from the GCE metadata server endpoint.
4. The GKE metadata proxy intercepts the request, identifies the pod's KSA, finds the Workload Identity binding, and issues a short-lived GCP access token for the GSA.
5. The pod uses that token for GCP API calls.

No token file is injected into the pod (unlike IRSA's `AWS_WEB_IDENTITY_TOKEN_FILE`). No environment variable points at an external STS endpoint. The token is issued by the local metadata proxy on the node and is transparent to the application.

### Module outputs

```hcl
gsa_email  → set as the value of the Helm chart annotation
              serviceAccount.annotations."iam.gke.io/gcp-service-account"
              so the GKE metadata proxy can identify which GSA to issue tokens for
```

### What happens if this module is misconfigured

| Misconfiguration | Failure mode |
|---|---|
| Workload Identity binding `member` has wrong namespace or KSA name | GKE metadata proxy cannot find a binding for the pod's identity; token requests return a permission-denied error; all GCP API calls from the pod fail |
| `workload_pool` from a different project | The member string references a non-existent pool; binding creation fails |
| KSA annotation missing in Helm values | GKE metadata proxy has no GSA to map to; returns node SA credentials if `GKE_METADATA` is not enforced, or an error if it is |
| `workload_metadata_config` set to `EXPOSE` on the node pool | Metadata proxy disabled; pods reach the raw GCE metadata server; Workload Identity binding is bypassed entirely; pod receives node SA credentials |
| `project_roles` empty when workload needs GCP access | GSA exists and the binding works; token exchange succeeds; but the GSA has no IAM permissions and all GCP API calls return `403 PERMISSION_DENIED` |
