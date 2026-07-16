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
