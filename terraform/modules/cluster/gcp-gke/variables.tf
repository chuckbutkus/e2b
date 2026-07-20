variable "cluster_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  description = "Regional cluster location (e.g. us-central1) — spans zones for HA control plane, same rationale as EKS's inherently multi-AZ control plane."
  type        = string
}

variable "network_self_link" {
  type = string
}

variable "subnetwork_self_link" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "release_channel" {
  description = "RAPID, REGULAR, or STABLE. Left unpinned to a hardcoded default deliberately, same reasoning as the EKS module's kubernetes_version."
  type        = string
  default     = "REGULAR"
}

variable "enable_private_endpoint" {
  description = "If true, the control plane has no public IP at all — kubectl/Terraform must reach it via VPN/interconnect/bastion. False (default) keeps a public endpoint restricted by master_authorized_networks, closer to the AWS module's default posture."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "/28 CIDR for the control plane's private VPC peering range. Must not overlap the node/pod/service ranges."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the control plane endpoint. No default on
    purpose — must be set explicitly (e.g. your office/VPN egress range)
    rather than silently falling back to 0.0.0.0/0. Enforced by a
    precondition on the cluster resource, matching the EKS module's
    public_access_cidrs behaviour.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "tags" {
  description = "Applied as GCP resource labels."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "GKE's own deletion protection. Defaults to false here since this is an assignment/test context where tear-down needs to be easy — flip to true for anything real."
  type        = bool
  default     = false
}

variable "create_kms_key" {
  description = "Provision a dedicated Cloud KMS key ring + key for GKE application-layer secrets encryption. Set false and pass kms_key_id to reuse an existing customer-managed key."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Existing Cloud KMS crypto key resource ID to use for secrets encryption when create_kms_key = false. Ignored otherwise."
  type        = string
  default     = null
}
