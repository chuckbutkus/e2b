# A dedicated, minimally-scoped node service account — GKE's default is
# to run nodes as the wide-open Compute Engine default service account,
# which is far broader than nodes actually need. Equivalent in spirit to
# the AWS module's node IAM role with only the 3 required managed policies.
resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node"
  display_name = "GKE node SA for ${var.cluster_name}"
}

resource "google_project_iam_member" "node" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader", # pull images from Artifact Registry
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_node_pool" "this" {
  name     = "${var.cluster_name}-default"
  project  = var.project_id
  location = var.region
  cluster  = var.cluster_name

  # Native autoscaling — no separate cluster-autoscaler deployment needed
  # here, unlike EKS. This is the single biggest structural difference
  # from the AWS node-pool module: on GKE, this block *is* the
  # autoscaler, not a knob that a separate controller reads.
  autoscaling {
    min_node_count = var.min_count
    max_node_count = var.max_count
  }

  initial_node_count = var.initial_count

  # Same reasoning as the EKS module's node group update_config: replace
  # nodes gradually during pool changes rather than all at once.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    image_type      = var.image_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = var.disk_type
    spot            = var.spot
    service_account = google_service_account.node.email

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required on the node side for Workload Identity to actually work —
    # this is what lets kubelet present the GKE metadata server (rather
    # than the raw GCE one) so pods can fetch Workload-Identity-bound
    # tokens. The cluster-level workload_identity_config in
    # modules/cluster/gcp-gke is necessary but not sufficient without this.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, var.tags)

    dynamic "taint" {
      for_each = var.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    # Same reasoning as the EKS module: once workloads scale the pool
    # via HPA-driven pending pods, GKE's own autoscaler (not a value we
    # set once at apply time) owns actual node count.
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.node]
}
