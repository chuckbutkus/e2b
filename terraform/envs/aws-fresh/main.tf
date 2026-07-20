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
  ami_type       = var.node_ami_type

  # System-only sizing when Karpenter owns workload capacity; full sizing
  # otherwise. See variables.tf for why these differ so much.
  min_size     = var.enable_karpenter ? var.system_node_min_size : var.node_min_size
  max_size     = var.enable_karpenter ? var.system_node_max_size : var.node_max_size
  desired_size = var.enable_karpenter ? var.system_node_desired_size : var.node_desired_size

  # Karpenter's own controller pod must land on this node group, never on
  # a node Karpenter itself provisions (see karpenter module's helm_release
  # nodeSelector) — this label is what that selector matches against.
  labels = var.enable_karpenter ? { "karpenter.sh/controller" = "true" } : {}

  tags = var.tags

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
  attach_inline_policy  = true
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

module "external_dns_irsa" {
  count  = var.install_external_dns ? 1 : 0
  source = "../../modules/irsa"

  role_name            = "${var.cluster_name}-external-dns"
  oidc_provider_arn    = module.cluster.oidc_provider_arn
  oidc_issuer_url      = module.cluster.cluster_oidc_issuer_url
  namespace            = "external-dns"
  service_account_name = "external-dns"
  policy_json          = data.aws_iam_policy_document.external_dns[0].json
  attach_inline_policy = true
  tags                 = var.tags
}

data "aws_iam_policy_document" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["route53:ChangeResourceRecordSets"]
    # Scope to a specific hosted zone when external_dns_hosted_zone_id is set;
    # fall back to all zones for initial setup when the zone ID isn't known yet.
    resources = var.external_dns_hosted_zone_id != "" ? [
      "arn:aws:route53:::hostedzone/${var.external_dns_hosted_zone_id}"
    ] : ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

module "k8s_platform" {
  source = "../../modules/k8s-platform"

  cluster_name                = module.cluster.cluster_name
  region                      = var.region
  cluster_autoscaler_role_arn = module.cluster_autoscaler_irsa.role_arn
  install_cluster_autoscaler  = !var.enable_karpenter # Karpenter replaces it; running both fights over node count

  install_nginx_gateway_fabric = var.install_nginx_gateway_fabric
  acme_email                   = var.acme_email
  install_external_dns         = var.install_external_dns
  external_dns_service_account_annotations = var.install_external_dns ? {
    "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].role_arn
  } : {}

  depends_on = [module.node_pool]
}

module "karpenter" {
  count  = var.enable_karpenter ? 1 : 0
  source = "../../modules/node-pool/karpenter"

  cluster_name               = module.cluster.cluster_name
  cluster_endpoint           = module.cluster.cluster_endpoint
  region                     = var.region
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  cluster_security_group_id  = module.cluster.cluster_security_group_id
  oidc_provider_arn          = module.cluster.oidc_provider_arn
  oidc_issuer_url            = module.cluster.cluster_oidc_issuer_url
  ami_family                 = var.karpenter_ami_family
  tags                       = var.tags

  depends_on = [module.k8s_platform] # needs the system node group Ready
                                       # (via node_pool) and cluster autoscaler
                                       # decision already settled before install
}
