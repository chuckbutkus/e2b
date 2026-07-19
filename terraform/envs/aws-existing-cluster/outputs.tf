output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.cluster.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.cluster.cluster_name} --region ${var.region}"
}
