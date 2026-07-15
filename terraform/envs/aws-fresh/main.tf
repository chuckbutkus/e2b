module "network" {
  source = "../../modules/network/aws"

  name                  = var.cluster_name
  cidr_block            = var.vpc_cidr
  azs                   = var.azs
  private_subnet_cidrs  = var.private_subnet_cidrs
  public_subnet_cidrs   = var.public_subnet_cidrs
  single_nat_gateway    = false # production default: resilient, one NAT per AZ
  tags                  = var.tags
}

module "cluster" {
  source = "../../modules/cluster/aws-eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  tags                = var.tags
}

module "node_pool" {
  source = "../../modules/node-pool/aws-eks"

  cluster_name   = module.cluster.cluster_name
  subnet_ids     = module.network.private_subnet_ids
  instance_types = var.node_instance_types
  min_size       = var.node_min_size
  max_size       = var.node_max_size
  desired_size   = var.node_desired_size
  tags           = var.tags

  depends_on = [module.cluster]
}

# IRSA role for cluster-autoscaler itself (distinct from the workload's
# own IRSA role, which the customer/deployer creates separately using the
# same module — see docs/ARCHITECTURE.md for the pattern).
module "cluster_autoscaler_irsa" {
  source = "../../modules/irsa"

  role_name             = "${var.cluster_name}-cluster-autoscaler"
  oidc_provider_arn     = module.cluster.oidc_provider_arn
  oidc_issuer_url       = module.cluster.cluster_oidc_issuer_url
  namespace             = "kube-system"
  service_account_name  = "cluster-autoscaler"
  policy_json           = data.aws_iam_policy_document.cluster_autoscaler.json
  tags                  = var.tags
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }
}

# Example workload IRSA role — the actual role a customer's Helm release
# would reference via values.yaml `serviceAccount.annotations`. Only
# uncomment/populate policy_arns if the sre-interview workload itself needs
# AWS API access (unconfirmed as of this writing — see the Helm chart's
# README for what's been verified against the running image so far).
#
# module "workload_irsa" {
#   source = "../../modules/irsa"
#
#   role_name            = "${var.cluster_name}-sre-workload"
#   oidc_provider_arn    = module.cluster.oidc_provider_arn
#   oidc_issuer_url      = module.cluster.cluster_oidc_issuer_url
#   namespace            = "default"
#   service_account_name = "sre-workload"
#   policy_arns          = []
#   tags                 = var.tags
# }

module "k8s_platform" {
  source = "../../modules/k8s-platform"

  cluster_name                = module.cluster.cluster_name
  region                      = var.region
  cluster_autoscaler_role_arn = module.cluster_autoscaler_irsa.role_arn

  depends_on = [module.node_pool]
}
