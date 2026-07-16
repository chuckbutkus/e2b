variable "name" {
  description = "Name prefix for all networking resources (e.g. cluster name)."
  type        = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "subnet_cidr" {
  description = "Primary CIDR for the GKE node subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range CIDR for pod IPs (VPC-native/alias IP GKE requires this — pods get real routable IPs from this range, not NAT'd)."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "Secondary range CIDR for Kubernetes Service ClusterIPs."
  type        = string
  default     = "10.8.0.0/20"
}

variable "tags" {
  description = "Labels applied to created resources (GCP calls these 'labels', kept as 'tags' for naming parity with the AWS modules)."
  type        = map(string)
  default     = {}
}
