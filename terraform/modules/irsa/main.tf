variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (from modules/cluster/aws-eks or modules/cluster/existing outputs)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer URL, including https:// — from the same cluster module's cluster_oidc_issuer_url output."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount this role trusts."
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount this role trusts — must match serviceAccount.name in the Helm chart values (or the chart's generated fullname if left unset)."
  type        = string
}

variable "policy_arns" {
  description = "Managed IAM policy ARNs to attach. Prefer this over policy_json for standard AWS service access."
  type        = list(string)
  default     = []
}

variable "policy_json" {
  description = "Optional inline policy JSON for permissions with no suitable managed policy. Leave null to skip."
  type        = string
  default     = null
}

variable "attach_inline_policy" {
  description = <<-EOT
    Whether to attach policy_json as an inline policy. Deliberately a
    separate boolean rather than inferring from `policy_json != null` —
    when policy_json is built from an aws_iam_policy_document that
    references ARNs of resources created in this same apply (e.g. a role
    or queue that doesn't exist yet), the resulting .json value is
    "known after apply," and Terraform can't evaluate a `count` based on
    an unknown value even to just check non-nullness. This plain boolean
    is always known at plan time regardless of what policy_json resolves
    to, so it doesn't hit that error.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  # Strip the scheme for use in the federated principal's condition key,
  # per AWS's documented IRSA trust-policy format.
  oidc_issuer_host = replace(var.oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "this" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count  = var.attach_inline_policy ? 1 : 0
  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.policy_json

  lifecycle {
    precondition {
      condition     = var.policy_json != null
      error_message = "attach_inline_policy is true but policy_json is null — pass a policy document, or set attach_inline_policy = false."
    }
  }
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
