data "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region
}
