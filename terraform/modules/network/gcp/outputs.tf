# Deliberately NOT reusing the AWS network module's exact output names
# (vpc_id/public_subnet_ids/private_subnet_ids) — GCP's model genuinely
# differs (one regional subnet + named secondary ranges, not per-AZ
# public/private subnet pairs), and forcing an identical shape here would
# hide that difference rather than represent it honestly. The cluster
# module on each cloud consumes its matching network module's real outputs.

output "network_id" {
  value = google_compute_network.this.id
}

output "network_self_link" {
  value = google_compute_network.this.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.this.self_link
}

output "subnetwork_name" {
  value = google_compute_subnetwork.this.name
}

output "pods_range_name" {
  value = google_compute_subnetwork.this.secondary_ip_range[0].range_name
}

output "services_range_name" {
  value = google_compute_subnetwork.this.secondary_ip_range[1].range_name
}
