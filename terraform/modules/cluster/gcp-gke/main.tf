data "google_project" "current" {
  project_id = var.project_id
}

# --- Application-layer secrets encryption -----------------------------------
# GKE encrypts etcd at rest with a Google-managed key by default — that
# covers disk-level encryption but not application-layer envelope
# encryption of Kubernetes Secret objects with a key the customer controls
# (the GCP equivalent of EKS's encryption_config). create_kms_key=true
# (default) provisions a dedicated key ring + CMEK per cluster; set it
# false and pass kms_key_id to reuse an existing centrally managed key.
# Requires cloudkms.googleapis.com enabled on the project.
resource "google_kms_key_ring" "gke" {
  count    = var.create_kms_key ? 1 : 0
  name     = "${var.cluster_name}-gke"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "gke_secrets" {
  count           = var.create_kms_key ? 1 : 0
  name            = "${var.cluster_name}-secrets"
  key_ring        = google_kms_key_ring.gke[0].id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = false
  }
}

# GKE's control plane calls Cloud KMS as the project's GKE service agent
# (service-<project_number>@container-engine-robot.iam.gserviceaccount.com),
# not as whatever identity is running Terraform — without this binding,
# cluster creation with database_encryption enabled fails permission checks.
resource "google_kms_crypto_key_iam_member" "gke_secrets" {
  count         = var.create_kms_key ? 1 : 0
  crypto_key_id = google_kms_crypto_key.gke_secrets[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}

locals {
  # Resolve to the key we just created, or the customer-supplied existing
  # key ID when create_kms_key = false.
  kms_key_id = var.create_kms_key ? google_kms_crypto_key.gke_secrets[0].id : var.kms_key_id
}

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

  database_encryption {
    state    = "ENCRYPTED"
    key_name = local.kms_key_id
  }

  resource_labels = var.tags

  deletion_protection = var.deletion_protection

  # Ensures the GKE service agent's decrypt/encrypt grant exists before GKE
  # tries to use the key at cluster-creation time. A no-op dependency when
  # create_kms_key = false (resource has zero instances), same as the
  # always-declared-provider pattern in the AWS envs.
  depends_on = [google_kms_crypto_key_iam_member.gke_secrets]

  lifecycle {
    precondition {
      condition     = var.create_kms_key || var.kms_key_id != null
      error_message = "create_kms_key is false but kms_key_id was not set — pass the resource ID of an existing Cloud KMS key, or leave create_kms_key at its default (true) to have this module provision one."
    }
    precondition {
      # Defaulting master_authorized_networks to 0.0.0.0/0 is how GKE
      # clusters end up with an internet-reachable control plane endpoint
      # by accident — same reasoning as the AWS module's public_access_cidrs
      # precondition. Applies regardless of enable_private_endpoint, since
      # master_authorized_networks gates whichever endpoint is active.
      condition     = length(var.master_authorized_networks) > 0
      error_message = "master_authorized_networks is empty. Set explicit CIDRs allowed to reach the control plane endpoint (office/VPN egress range, or the VPC range if accessing over private connectivity)."
    }
  }
}
