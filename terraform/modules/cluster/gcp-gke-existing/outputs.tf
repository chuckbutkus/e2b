output "cluster_name" {
  value = data.google_container_cluster.this.name
}

output "cluster_endpoint" {
  value = "https://${data.google_container_cluster.this.endpoint}"
}

output "cluster_ca_certificate" {
  value     = data.google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "cluster_location" {
  value = data.google_container_cluster.this.location
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

output "cluster_id" {
  value = data.google_container_cluster.this.id
}

output "master_version" {
  value = data.google_container_cluster.this.master_version
}
