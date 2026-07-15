variable "cluster_name" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets worker nodes launch into."
  type        = list(string)
}

variable "instance_types" {
  type    = list(string)
  default = ["m6i.large"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "ami_type" {
  description = <<-EOT
    EKS-optimized AMI family for the managed node group. Bottlerocket is a
    drop-in swap here — EKS handles the bootstrap/join process for managed
    node groups regardless of AMI family, so no user_data/launch-template
    changes are required to switch. Two things do change operationally:
    Bottlerocket has no shell/SSH — use the built-in admin/control
    container (or SSM) for node-level debugging instead — and its root
    volume is split (OS partition + separate data partition for
    containerd/kubelet), see `bottlerocket_data_volume_size_gb` below.
  EOT
  type    = string
  default = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD",
      "AL2023_ARM_64_STANDARD",
      "BOTTLEROCKET_x86_64",
      "BOTTLEROCKET_ARM_64",
      "BOTTLEROCKET_x86_64_NVIDIA",
    ], var.ami_type)
    error_message = "ami_type must be one of: AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, BOTTLEROCKET_x86_64, BOTTLEROCKET_ARM_64, BOTTLEROCKET_x86_64_NVIDIA."
  }
}

variable "bottlerocket_data_volume_size_gb" {
  description = "Size of Bottlerocket's separate data volume (containerd/kubelet storage). Ignored for non-Bottlerocket ami_type."
  type        = number
  default     = 50
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 6
}

variable "desired_size" {
  type    = number
  default = 3
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Note: Karpenter is implemented as a separate module
# (modules/node-pool/karpenter), not as a flag here — this module always
# represents a managed-node-group pool, used either as the sole worker
# capacity or, in Karpenter mode, as the small fixed-size "system" pool
# that hosts Karpenter itself. See the top-level terraform/README.md.
