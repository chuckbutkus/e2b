variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Left unpinned to a hardcoded default deliberately — pass explicitly per environment so upgrades are a conscious variable change, not a surprise on next apply."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS control plane ENIs — pass private subnets for a private/internal cluster, or private+public if the control plane endpoint needs to reach public subnets too."
  type        = list(string)
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API endpoint. No default on purpose —
    if endpoint_public_access is true, this must be set explicitly (e.g.
    your office/VPN egress range) rather than silently falling back to
    0.0.0.0/0. Enforced by a precondition on the cluster resource. Leave
    empty and set endpoint_public_access = false for a fully private
    cluster instead.
  EOT
  type        = list(string)
  default     = []
}

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types to ship to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "scheduler", "controllerManager"]
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "create_kms_key" {
  description = "Provision a dedicated CMK for EKS secrets envelope encryption. Set false and pass kms_key_arn to reuse an existing customer-managed key instead."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Existing CMK ARN to use for secrets encryption when create_kms_key = false. Ignored otherwise."
  type        = string
  default     = null
}

variable "kms_key_deletion_window" {
  description = "Days KMS waits before actually deleting the key after a destroy (7-30). Shorter aids iterative dev/test environments; production should stay at the AWS default of 30."
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "CloudWatch log retention for EKS control-plane logs in days. Compliance baselines commonly require ≥365. The log group is encrypted with the same CMK as EKS secrets."
  type        = number
  default     = 365
}
