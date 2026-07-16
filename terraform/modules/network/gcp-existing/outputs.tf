output "network_id" {
  value = data.google_compute_network.this.id
}

output "network_self_link" {
  value = data.google_compute_network.this.self_link
}

output "subnetwork_self_link" {
  value = data.google_compute_subnetwork.this.self_link
}

output "subnetwork_name" {
  value = data.google_compute_subnetwork.this.name
}

output "pods_range_name" {
  value = var.pods_range_name
}

output "services_range_name" {
  value = var.services_range_name
}
