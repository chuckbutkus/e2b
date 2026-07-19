variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for cluster-autoscaler (from modules/irsa), granting autoscaling:* / ec2:DescribeInstances etc. Only relevant when install_cluster_autoscaler=true (AWS only — GKE's node-pool autoscaling is native, so the GCP env leaves this at its default and sets install_cluster_autoscaler=false)."
  type        = string
  default     = ""
}

variable "install_ingress_nginx" {
  type    = bool
  default = true
}

variable "install_metrics_server" {
  type    = bool
  default = true
}

variable "install_cluster_autoscaler" {
  type    = bool
  default = true
}

# --- cert-manager -----------------------------------------------------------

variable "install_cert_manager" {
  description = "Install cert-manager and create Let's Encrypt ClusterIssuers. Disable if the cluster already has cert-manager or if a different certificate strategy is used."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  type    = string
  default = "1.16.2"
}

variable "acme_email" {
  description = "Email address for Let's Encrypt ACME registration. Required to create the letsencrypt-staging and letsencrypt-prod ClusterIssuers. Leave empty to skip ClusterIssuer creation (cert-manager is still installed; operators can add issuers manually)."
  type        = string
  default     = ""
}

# --- external-dns ------------------------------------------------------------

variable "install_external_dns" {
  description = "Install external-dns. Disabled by default because it requires write access to the customer's DNS zone and the zone may be managed externally."
  type        = bool
  default     = false
}

variable "external_dns_chart_version" {
  type    = string
  default = "1.15.0"
}

variable "external_dns_provider" {
  description = "Cloud DNS provider: 'aws' (Route 53) or 'google' (Cloud DNS)."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "google"], var.external_dns_provider)
    error_message = "external_dns_provider must be 'aws' or 'google'."
  }
}

variable "external_dns_google_project" {
  description = "GCP project ID for the Cloud DNS zone. Required when external_dns_provider='google'."
  type        = string
  default     = ""
}

variable "external_dns_txt_owner_id" {
  description = "TXT record owner ID that external-dns uses to claim ownership of records it manages. Defaults to cluster_name, which makes records from different clusters distinguishable."
  type        = string
  default     = ""
}

variable "external_dns_service_account_annotations" {
  description = "Annotations on the external-dns ServiceAccount — typically the IRSA role ARN (AWS) or Workload Identity GSA email (GCP). Populated by the calling env, not here."
  type        = map(string)
  default     = {}
}
