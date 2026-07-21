module "cluster" {
  source = "../../modules/cluster/aws-existing"

  cluster_name = var.cluster_name
}

# Opt-in IRSA role for cluster-autoscaler. Not created by default because
# the customer's existing cluster may already have autoscaling managed by
# another process. Set install_cluster_autoscaler = true to enable.
module "cluster_autoscaler_irsa" {
  count  = var.install_cluster_autoscaler ? 1 : 0
  source = "../../modules/irsa"

  role_name            = "${var.cluster_name}-cluster-autoscaler"
  oidc_provider_arn    = module.cluster.oidc_provider_arn
  oidc_issuer_url      = module.cluster.cluster_oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "cluster-autoscaler"
  policy_json          = data.aws_iam_policy_document.cluster_autoscaler[0].json
  attach_inline_policy = true
  tags                 = var.tags
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

  cluster_name               = module.cluster.cluster_name
  region                     = var.region
  install_cluster_autoscaler = var.install_cluster_autoscaler
  # try() safely returns "" when the count-0 module has no index 0 —
  # the k8s-platform precondition only fires when install_cluster_autoscaler
  # is true, so the empty string is never actually validated in that case.
  cluster_autoscaler_role_arn = try(module.cluster_autoscaler_irsa[0].role_arn, "")
  install_ingress_nginx       = var.install_ingress_nginx
  install_metrics_server      = var.install_metrics_server

  install_nginx_gateway_fabric = var.install_nginx_gateway_fabric
  install_cert_manager         = var.install_cert_manager
  acme_email                   = var.acme_email
  install_external_dns         = var.install_external_dns
  external_dns_service_account_annotations = var.install_external_dns ? {
    "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].role_arn
  } : {}

  depends_on = [module.cluster]
}
