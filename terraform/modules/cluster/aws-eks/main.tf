data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- Secrets envelope encryption --------------------------------------------
# EKS does not encrypt Kubernetes Secrets at rest with a customer-managed
# key unless explicitly configured via encryption_config — the default is
# encrypted-at-rest by AWS's own key only, which is not sufficient for most
# production/compliance baselines. create_kms_key=true (default) provisions
# a dedicated CMK per cluster; set it false and pass kms_key_arn to reuse a
# centrally managed key instead (e.g. a customer's existing security-team-
# owned KMS key).
resource "aws_kms_key" "eks_secrets" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "EKS Kubernetes secrets envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  tags                    = var.tags

  # EKS's control plane assumes the cluster IAM role to call kms:Encrypt /
  # kms:Decrypt / kms:DescribeKey / kms:CreateGrant against this key when
  # reading/writing Secrets — without this statement the default key policy
  # (root-account-only) blocks the cluster from ever using its own key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountRootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowEKSClusterRoleToUseKey"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.cluster.arn }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
      {
        # CloudWatch Logs must be able to encrypt/decrypt log events for the
        # control-plane log group. Scoped to the exact log group ARN via the
        # kms:EncryptionContext condition so the grant cannot be used for any
        # other log group in the account.
        Sid       = "AllowCloudWatchLogsToUseKey"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.cluster_name}/cluster"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "eks_secrets" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets[0].key_id
}

locals {
  # Resolve to the key we just created, or the customer-supplied existing
  # key ARN when create_kms_key = false.
  kms_key_arn = var.create_kms_key ? aws_kms_key.eks_secrets[0].arn : var.kms_key_arn
}

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
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn
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

  encryption_config {
    provider {
      key_arn = local.kms_key_arn
    }
    resources = ["secrets"]
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]

  lifecycle {
    precondition {
      condition     = var.create_kms_key || var.kms_key_arn != null
      error_message = "create_kms_key is false but kms_key_arn was not set — pass the ARN of an existing CMK, or leave create_kms_key at its default (true) to have this module provision one."
    }
    precondition {
      # Defaulting public_access_cidrs to 0.0.0.0/0 is how EKS clusters end
      # up with an internet-reachable control plane API by accident. If the
      # public endpoint is on, the caller must say explicitly who can reach
      # it (office CIDR, VPN range, etc.) — or turn endpoint_public_access
      # off entirely for a fully private cluster.
      condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
      error_message = "endpoint_public_access is true but public_access_cidrs is empty. Set explicit CIDRs allowed to reach the public API endpoint, or set endpoint_public_access = false for a private-only cluster."
    }
  }
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
