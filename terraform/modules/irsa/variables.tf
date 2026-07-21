variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (from modules/cluster/aws-eks or modules/cluster/aws-eks-existing outputs)."
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
