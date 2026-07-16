output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_endpoint" {
  value = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "cluster_location" {
  value = google_container_cluster.this.location
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

output "cluster_id" {
  value = google_container_cluster.this.id
}

output "master_version" {
  value = google_container_cluster.this.master_version
}
