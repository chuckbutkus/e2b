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

variable "install_external_dns" {
  type    = bool
  default = false
}

variable "external_dns_hosted_zone_id" {
  description = "Route 53 hosted zone ID to scope the external-dns IAM policy. Leave empty to allow all zones."
  type        = string
  default     = ""
}
