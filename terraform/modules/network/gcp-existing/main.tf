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

data "google_compute_network" "this" {
  project = var.project_id
  name    = var.network_name
}

data "google_compute_subnetwork" "this" {
  project = var.project_id
  region  = var.region
  name    = var.subnetwork_name

  lifecycle {
    postcondition {
      condition = anytrue([
        for r in self.secondary_ip_range : r.range_name == var.pods_range_name
      ])
      error_message = "Subnetwork ${var.subnetwork_name} has no secondary range named '${var.pods_range_name}' — VPC-native GKE requires a pods secondary range. Ask the customer to add one, or point at the correct range_name."
    }
    postcondition {
      condition = anytrue([
        for r in self.secondary_ip_range : r.range_name == var.services_range_name
      ])
      error_message = "Subnetwork ${var.subnetwork_name} has no secondary range named '${var.services_range_name}' — VPC-native GKE requires a services secondary range."
    }
  }
}
