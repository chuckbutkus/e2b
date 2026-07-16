variable "cluster_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  description = "Location of the existing cluster — region for a regional cluster, zone for a zonal one."
  type        = string
}

data "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region
}
