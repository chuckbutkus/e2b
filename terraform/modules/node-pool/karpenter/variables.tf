variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "cluster_security_group_id" {
  description = "From modules/cluster/aws-eks (or existing) output cluster_security_group_id — used as the security group Karpenter-launched nodes join."
  type        = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}

variable "ami_family" {
  description = "Bottlerocket or AL2023. Determines EC2NodeClass.spec.amiFamily and which block device mapping shape gets applied."
  type        = string
  default     = "Bottlerocket"

  validation {
    condition     = contains(["Bottlerocket", "AL2023"], var.ami_family)
    error_message = "ami_family must be Bottlerocket or AL2023."
  }
}

variable "bottlerocket_data_volume_size_gb" {
  type    = number
  default = 50
}

variable "instance_categories" {
  description = "EC2 instance categories Karpenter is allowed to choose from."
  type        = list(string)
  default     = ["c", "m", "r"]
}

variable "capacity_types" {
  description = "on-demand, spot, or both. Spot needs the interruption-handling SQS/EventBridge wiring this module creates regardless, so both are always safe to include here."
  type        = list(string)
  default     = ["on-demand", "spot"]
}

variable "cpu_limit" {
  description = "Total vCPU ceiling across everything this NodePool provisions — a safety rail against runaway scale-out, not a target."
  type        = number
  default     = 1000
}

variable "memory_limit" {
  description = "Total memory ceiling across everything this NodePool provisions (Kubernetes quantity string, e.g. '2000Gi', '2Ti'). A safety rail alongside the CPU limit."
  type        = string
  default     = "2000Gi"
}

variable "consolidation_policy" {
  description = "WhenEmpty consolidates only fully-empty nodes (no live pod eviction). WhenEmptyOrUnderutilized also evicts pods to bin-pack, which causes live-traffic churn on low-replica workloads. Default is WhenEmpty."
  type        = string
  default     = "WhenEmpty"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be WhenEmpty or WhenEmptyOrUnderutilized."
  }
}

variable "consolidate_after" {
  description = "How long a node must remain empty (WhenEmpty) or underutilized (WhenEmptyOrUnderutilized) before Karpenter consolidates it. Longer values reduce churn."
  type        = string
  default     = "5m"
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.1.1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
