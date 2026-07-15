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
  type    = string
  default = "AL2023_x86_64_STANDARD"
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

variable "use_karpenter" {
  description = <<-EOT
    Out of scope for this assignment's implementation — structured as a flag
    so the decision is explicit rather than silently defaulted. When true,
    this module should provision only enough EKS-managed capacity to run
    Karpenter itself, and node provisioning for the workload becomes
    Karpenter NodePool/EC2NodeClass CRDs applied via the k8s-platform module
    instead of an aws_eks_node_group. Left unimplemented here; the managed
    node group path below is the default and the fully-tested path.
  EOT
  type    = bool
  default = false
}
