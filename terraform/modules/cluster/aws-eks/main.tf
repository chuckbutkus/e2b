data "aws_partition" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Control plane logs — off by default in EKS, and genuinely useful for
# debugging auth/RBAC issues in a customer environment we don't have
# shell access to.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access   = var.endpoint_public_access
    endpoint_private_access  = var.endpoint_private_access
    public_access_cidrs      = var.public_access_cidrs
  }

  # API-mode access entries instead of the legacy aws-auth ConfigMap:
  # avoids a chicken-and-egg problem where the ConfigMap approach requires
  # kubectl/Kubernetes-provider access to a cluster that isn't reachable
  # yet, and EKS auto-creates the access entry for managed node groups in
  # this mode (no separate aws_eks_access_entry needed for basic node join).
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# --- OIDC provider for IRSA -------------------------------------------------
# EKS clusters have an OIDC issuer but AWS doesn't auto-register it as an
# IAM identity provider — that's a separate step required before any
# ServiceAccount can assume an IAM role.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = var.tags
}
