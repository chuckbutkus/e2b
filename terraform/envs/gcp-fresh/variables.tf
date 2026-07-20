variable "project_id" {
  description = "GCP project ID — no default, forces explicit input rather than deploying into the wrong project."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "cluster_name" {
  type    = string
  default = "e2b-sre-gcp-fresh"
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the GKE control plane endpoint. No safe default — set this to your office/VPN egress range(s) per environment. Enforced by a precondition in the cluster module."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "create_kms_key" {
  description = "Provision a dedicated Cloud KMS key for GKE application-layer secrets encryption. Set false and supply kms_key_id to reuse an existing centrally-managed key."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Existing Cloud KMS crypto key resource ID, used only when create_kms_key = false."
  type        = string
  default     = null
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.4.0.0/14"
}

variable "services_cidr" {
  type    = string
  default = "10.8.0.0/20"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "node_image_type" {
  description = "COS_CONTAINERD or UBUNTU_CONTAINERD — see modules/node-pool/gcp-gke for why Bottlerocket isn't an option here."
  type        = string
  default     = "COS_CONTAINERD"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 6
}

variable "node_initial_count" {
  type    = number
  default = 3
}

variable "tags" {
  type = map(string)
  default = {
    project     = "e2b-sre-assignment"
    environment = "gcp-fresh"
    managed-by  = "terraform"
  }
}

# --- cert-manager / external-dns --------------------------------------------

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration. Leave empty to skip ClusterIssuer creation."
  type        = string
  default     = ""
}

variable "install_nginx_gateway_fabric" {
  description = "Install NGINX Gateway Fabric alongside (or instead of) ingress-nginx. Disabled by default."
  type        = bool
  default     = false
}

variable "install_external_dns" {
  description = "Install external-dns and create a Workload Identity binding with Cloud DNS admin access. Disabled by default."
  type        = bool
  default     = false
}
