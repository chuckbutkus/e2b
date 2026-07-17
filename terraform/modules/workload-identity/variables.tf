variable "project_id" {
  type = string
}

variable "gsa_account_id" {
  description = "Google Service Account ID (becomes <gsa_account_id>@<project_id>.iam.gserviceaccount.com)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount this GSA is bound to."
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount (KSA) — must match serviceAccount.name in the Helm chart values (or its generated fullname if unset), same as the AWS irsa module's service_account_name."
  type        = string
}

variable "workload_pool" {
  description = "From modules/cluster/gcp-gke (or gcp-gke-existing) output workload_pool — '<project_id>.svc.id.goog'."
  type        = string
}

variable "project_roles" {
  description = "Project-level IAM roles to grant this GSA. GCP's equivalent of the AWS irsa module's policy_arns — prefer this over custom_role_permissions for standard access patterns."
  type        = list(string)
  default     = []
}
