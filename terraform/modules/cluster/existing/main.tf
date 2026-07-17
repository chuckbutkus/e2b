data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# Assumption (documented, not silently assumed): the customer's existing
# cluster already has an IAM OIDC provider registered — true for the large
# majority of EKS clusters created via eksctl/Terraform/Console in the last
# few years, but not guaranteed for older or hand-rolled clusters. If this
# data source errors with "no OIDC provider found", the fix is a one-time
# `aws iam create-open-id-connect-provider` (or a small Terraform resource,
# same shape as in modules/cluster/aws-eks/main.tf) before this module can
# proceed — intentionally not auto-created here, since silently mutating a
# customer's existing IAM setup from a "just read what's there" module is
# the wrong default.
data "aws_iam_openid_connect_provider" "existing" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}
