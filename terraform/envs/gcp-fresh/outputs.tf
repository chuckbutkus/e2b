output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "network_self_link" {
  value = module.network.network_self_link
}

output "workload_pool" {
  value = module.cluster.workload_pool
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "gcloud container clusters get-credentials ${module.cluster.cluster_name} --region ${var.region} --project ${var.project_id}"
}
