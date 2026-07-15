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
  description = "CIDRs allowed to reach the public API endpoint. Restrict this in production — default is permissive for initial setup only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
