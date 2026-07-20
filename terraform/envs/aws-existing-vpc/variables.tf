variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "e2b-sre-existing-vpc"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

# --- Customer-supplied, no defaults on purpose: forces explicit input
# rather than silently deploying into the wrong VPC. ---
variable "vpc_id" {
  description = "Customer's existing VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Customer's existing private subnet IDs (>= 2, must carry EKS discovery tags — see modules/network/existing for the exact tags checked)."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Customer's existing public subnet IDs, if internet-facing ingress is needed."
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Expose the EKS API server publicly. If true, public_access_cidrs must be set to something narrower than 0.0.0.0/0."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint when endpoint_public_access = true. No safe default — set this to your office/VPN egress range(s) per environment. Enforced by a precondition in the cluster module."
  type        = list(string)
  default     = []
}

variable "create_kms_key" {
  description = "Provision a dedicated CMK for EKS secrets envelope encryption. Set false and supply kms_key_arn to reuse an existing centrally-managed key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Existing CMK ARN, used only when create_kms_key = false."
  type        = string
  default     = null
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m6i.large"]
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

variable "tags" {
  type = map(string)
  default = {
    Project     = "e2b-sre-assignment"
    Environment = "existing-vpc"
    ManagedBy   = "terraform"
  }
}

# --- cert-manager / external-dns --------------------------------------------

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration. Leave empty to skip ClusterIssuer creation."
  type        = string
  default     = ""
}

variable "install_nginx_gateway_fabric" {
  type    = bool
  default = false
}

variable "install_external_dns" {
  type    = bool
  default = false
}

variable "external_dns_hosted_zone_id" {
  description = "Route 53 hosted zone ID to scope the external-dns IAM policy. Leave empty to allow all zones."
  type        = string
  default     = ""
}
