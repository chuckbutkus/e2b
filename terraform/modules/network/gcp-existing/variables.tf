variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_name" {
  description = "Name of the customer's existing VPC network."
  type        = string
}

variable "subnetwork_name" {
  description = "Name of the customer's existing regional subnet for GKE nodes."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the existing secondary range for pod IPs on that subnet."
  type        = string
}

variable "services_range_name" {
  description = "Name of the existing secondary range for Service ClusterIPs on that subnet."
  type        = string
}
