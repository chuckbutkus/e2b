module "network" {
  source = "../../modules/network/existing"

  vpc_id              = var.vpc_id
  private_subnet_ids  = var.private_subnet_ids
  public_subnet_ids   = var.public_subnet_ids
  cluster_name        = var.cluster_name
}

module "cluster" {
  source = "../../modules/cluster/aws-eks"

  cluster_name             = var.cluster_name
  kubernetes_version       = var.kubernetes_version
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_subnet_ids
  endpoint_public_access   = var.endpoint_public_access
  public_access_cidrs      = var.public_access_cidrs
  create_kms_key           = var.create_kms_key
  kms_key_arn              = var.kms_key_arn
  tags                     = var.tags
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

module "cluster_autoscaler_irsa" {
  count  = var.install_cluster_autoscaler ? 1 : 0
  source = "../../modules/irsa"

  role_name             = "${var.cluster_name}-cluster-autoscaler"
  oidc_provider_arn     = module.cluster.oidc_provider_arn
  oidc_issuer_url       = module.cluster.cluster_oidc_issuer_url
  namespace             = "kube-system"
  service_account_name  = "cluster-autoscaler"
  policy_json           = data.aws_iam_policy_document.cluster_autoscaler[0].json
  attach_inline_policy  = true
  tags                  = var.tags
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  count = var.install_cluster_autoscaler ? 1 : 0

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

resource "terraform_data" "assert_external_dns_zone_scoped" {
  count = var.install_external_dns ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.external_dns_hosted_zone_id != ""
      error_message = "install_external_dns is true but external_dns_hosted_zone_id is empty. Set the Route 53 hosted zone ID to prevent external-dns from gaining write access to all zones in the account."
    }
  }
}

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
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
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
  install_cluster_autoscaler  = var.install_cluster_autoscaler
  # try() safely returns "" when the count-0 module has no index 0 —
  # the k8s-platform precondition only fires when install_cluster_autoscaler
  # is true, so the empty string is never actually validated in that case.
  cluster_autoscaler_role_arn = try(module.cluster_autoscaler_irsa[0].role_arn, "")

  install_nginx_gateway_fabric = var.install_nginx_gateway_fabric
  acme_email                   = var.acme_email
  install_external_dns         = var.install_external_dns
  external_dns_service_account_annotations = var.install_external_dns ? {
    "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].role_arn
  } : {}

  depends_on = [module.node_pool]
}
