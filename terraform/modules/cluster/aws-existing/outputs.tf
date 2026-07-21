output "cluster_name" {
  value = data.aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = data.aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value     = data.aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "cluster_version" {
  value = data.aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  value = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  value = data.aws_iam_openid_connect_provider.existing.arn
}

output "cluster_security_group_id" {
  value = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
