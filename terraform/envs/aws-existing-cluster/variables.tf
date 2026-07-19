variable "region" {
  type    = string
  default = "us-east-1"
}

# Required — no default forces explicit input rather than silently
# targeting the wrong cluster.
variable "cluster_name" {
  description = "Name of the customer's existing EKS cluster."
  type        = string
}

# Autoscaling: defaults to false because the existing cluster is likely
# already managed (eksctl, another Terraform root, etc.) and adding a
# second cluster-autoscaler would conflict. Flip to true only after
# confirming the cluster has no existing autoscaler.
variable "install_cluster_autoscaler" {
  type    = bool
  default = false
}

variable "install_ingress_nginx" {
  type    = bool
  default = true
}

variable "install_metrics_server" {
  type    = bool
  default = true
}

# cert-manager and external-dns both default to false for existing clusters:
# the customer may already have them installed and a duplicate install would
# conflict. Opt in explicitly after confirming the cluster state.

variable "install_cert_manager" {
  type    = bool
  default = false
}

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

variable "tags" {
  type = map(string)
  default = {
    Project     = "e2b-sre-assignment"
    Environment = "existing-cluster"
    ManagedBy   = "terraform"
  }
}
