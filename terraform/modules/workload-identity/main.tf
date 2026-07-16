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

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.gsa_account_id
  display_name = "Workload Identity SA for ${var.namespace}/${var.service_account_name}"
}

resource "google_project_iam_member" "roles" {
  for_each = toset(var.project_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.this.email}"
}

# The actual Workload Identity binding: lets the Kubernetes ServiceAccount
# impersonate this GSA. This one resource is the GCP equivalent of the
# entire AWS irsa module's assume-role-policy federation logic — GCP's
# model needs no separate OIDC provider registration because the workload
# pool is a fixed, always-present per-project resource.
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.this.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.workload_pool}[${var.namespace}/${var.service_account_name}]"
}

output "gsa_email" {
  value = google_service_account.this.email
}
