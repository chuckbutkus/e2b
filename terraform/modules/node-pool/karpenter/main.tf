data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# --- IAM role + instance profile for nodes Karpenter launches directly ---
# Distinct from modules/node-pool/aws-eks's node role: that role is for the
# small "system" managed node group Karpenter itself runs on; this role is
# for the (much larger, variable) fleet Karpenter provisions on demand.
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    # SSM is attached for parity with the managed-node-group path's
    # debuggability, but note it only does something on Bottlerocket if
    # the admin container is explicitly enabled via EC2NodeClass userData
    # — Bottlerocket doesn't ship the SSM agent in its default (non-admin)
    # container the way AL2023 does.
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name
}

# Nodes Karpenter launches bypass the "managed node group" path entirely
# (they're plain EC2 instances with this instance profile), so — unlike
# modules/node-pool/aws-eks — they do NOT get an access entry auto-created
# by EKS under API auth mode. This has to be explicit, or every
# Karpenter-launched node fails to join with an authorization error.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX" # covers Bottlerocket too — this selects the
                              # node-bootstrap access type, not an OS-specific one
}

# --- IRSA role for the Karpenter controller itself -------------------------
module "irsa" {
  source = "../../irsa"

  role_name             = "${var.cluster_name}-karpenter-controller"
  oidc_provider_arn     = var.oidc_provider_arn
  oidc_issuer_url       = var.oidc_issuer_url
  namespace             = "kube-system"
  service_account_name  = "karpenter"
  policy_json           = data.aws_iam_policy_document.karpenter_controller.json
  attach_inline_policy  = true
  tags                  = var.tags
}

data "aws_iam_policy_document" "karpenter_controller" {
  # Karpenter tags every resource it creates with karpenter.sh/discovery=<cluster>.
  # Mutating actions are scoped to those tagged resources so the controller
  # cannot touch EC2 resources belonging to other clusters or outside its purview.
  # aws:RequestTag conditions cover resources being created; aws:ResourceTag
  # conditions cover resources that already exist (termination, deletion).
  statement {
    sid    = "AllowScopedEC2MutatingActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  statement {
    sid    = "AllowScopedEC2DeletionActions"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  statement {
    sid    = "AllowScopedEC2TaggingActions"
    effect = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  statement {
    sid    = "AllowPassingNodeRole"
    effect = "Allow"
    actions = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
  }

  # EC2 Describe calls and SSM/pricing lookups do not support resource-level
  # permissions — AWS requires "*" for these read-only operations regardless.
  statement {
    sid    = "AllowEC2ReadOnlyActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  statement {
    sid    = "AllowPricingAndSSMLookup"
    effect = "Allow"
    actions = [
      "pricing:GetProducts",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }
}
