variable "cluster_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "image_type" {
  description = <<-EOT
    COS_CONTAINERD (Google's Container-Optimized OS, the GKE default and
    equivalent role to AL2023 on the AWS side) or UBUNTU_CONTAINERD.
    Bottlerocket is not available on GKE — it's an AWS-specific AMI
    project, not a general cloud-portable node OS, unlike what the
    Terraform module structure might otherwise imply. COS is the closer
    analogue to Bottlerocket in spirit (minimal, purpose-built,
    immutable-ish, container-focused) if that property matters more than
    the specific Bottlerocket project.
  EOT
  type = string
  default = "COS_CONTAINERD"

  validation {
    condition     = contains(["COS_CONTAINERD", "UBUNTU_CONTAINERD"], var.image_type)
    error_message = "image_type must be COS_CONTAINERD or UBUNTU_CONTAINERD."
  }
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "disk_type" {
  type    = string
  default = "pd-ssd"
}

variable "spot" {
  description = "Use Spot VMs instead of on-demand. GCP's equivalent of AWS's SPOT capacity_type."
  type        = bool
  default     = false
}

variable "min_count" {
  type    = number
  default = 2
}

variable "max_count" {
  type    = number
  default = 6
}

variable "initial_count" {
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
    effect = string # NO_SCHEDULE | PREFER_NO_SCHEDULE | NO_EXECUTE — GKE's own casing, differs from k8s's NoSchedule/etc.
  }))
  default = []
}

variable "tags" {
  description = "Applied as GCP resource labels."
  type        = map(string)
  default     = {}
}
