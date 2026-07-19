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
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_pool}[${var.namespace}/${var.service_account_name}]"
}
