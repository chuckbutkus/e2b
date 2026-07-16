resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional, not zonal — HA control plane across zones

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  # Node pools are managed entirely by modules/node-pool/gcp-gke — this is
  # the standard Terraform GKE pattern to avoid the provider fighting over
  # node pool state between the cluster resource and separate node pool
  # resources. GKE requires at least one node pool at creation time, so we
  # create a throwaway one and immediately remove it.
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # GKE's Workload Identity — the equivalent of AWS's IRSA, but simpler:
  # no separate OIDC provider registration step, it's inherently tied to
  # the project's fixed workload pool. modules/workload-identity binds
  # individual KSAs to GSAs against this pool.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  resource_labels = var.tags

  deletion_protection = var.deletion_protection
}
