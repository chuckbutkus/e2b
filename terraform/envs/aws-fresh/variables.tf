variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "e2b-sre-fresh"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m6i.large"]
}

variable "node_ami_type" {
  description = "AL2023_x86_64_STANDARD or a BOTTLEROCKET_* variant — see modules/node-pool/aws-eks for the full validated list."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_desired_size" {
  type    = number
  default = 3
}

# --- Karpenter toggle --------------------------------------------------
# When true: the managed node group above shrinks to a small fixed-size
# "system" pool (sized by the three variables below) that hosts only
# Karpenter itself, core add-ons, and ingress-nginx/metrics-server — actual
# workload capacity comes from Karpenter-provisioned nodes instead.
# cluster-autoscaler is automatically disabled in this mode (it would
# otherwise fight Karpenter for control over node count).
variable "enable_karpenter" {
  type    = bool
  default = false
}

variable "karpenter_ami_family" {
  description = "Bottlerocket or AL2023 — the AMI family Karpenter provisions."
  type        = string
  default     = "Bottlerocket"
}

variable "system_node_min_size" {
  description = "Sizing for the system node group when enable_karpenter=true — only needs to run Karpenter + core add-ons, not workload pods."
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  type    = number
  default = 2
}

variable "system_node_desired_size" {
  type    = number
  default = 1
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "e2b-sre-assignment"
    Environment = "fresh"
    ManagedBy   = "terraform"
  }
}

# --- cert-manager / external-dns --------------------------------------------

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration. Required to create letsencrypt-staging and letsencrypt-prod ClusterIssuers. Leave empty to skip ClusterIssuer creation."
  type        = string
  default     = ""
}

variable "install_nginx_gateway_fabric" {
  description = "Install NGINX Gateway Fabric alongside (or instead of) ingress-nginx. Disabled by default."
  type        = bool
  default     = false
}

variable "install_external_dns" {
  description = "Install external-dns and create an IRSA role with Route 53 write access. Disabled by default — enable once the customer's hosted zone is ready and its ID is known."
  type        = bool
  default     = false
}

variable "external_dns_hosted_zone_id" {
  description = "Route 53 hosted zone ID to scope the external-dns IAM policy to a specific zone. Leave empty to allow access to all zones in the account (broader but simpler for initial setup)."
  type        = string
  default     = ""
}
