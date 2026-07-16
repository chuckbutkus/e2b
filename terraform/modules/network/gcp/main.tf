resource "google_compute_network" "this" {
  name                    = var.name
  project                 = var.project_id
  auto_create_subnetworks = false # custom-mode — explicit subnet/secondary
                                    # ranges below, not GCP's auto default
}

# VPC-native (alias IP) GKE requires named secondary ranges for pods and
# services — this is the GCP equivalent of the AWS module's private
# subnets, just structured differently (one subnet + two secondary ranges,
# rather than one subnet per AZ).
resource "google_compute_subnetwork" "this" {
  name          = "${var.name}-nodes"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "${var.name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name}-services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true # nodes without external IPs can still
                                    # reach Google APIs (GCR/Artifact
                                    # Registry, etc.) — required for a
                                    # private-nodes GKE cluster to function
}

# Cloud NAT — GKE nodes here have no external IPs (private nodes), so
# outbound internet access (pulling non-Google images, hitting external
# APIs) goes through this instead. GCP's equivalent of the AWS module's
# per-AZ NAT gateways, though Cloud NAT is regional, not per-zone.
resource "google_compute_router" "this" {
  name    = "${var.name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name    = "${var.name}-nat"
  project = var.project_id
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Baseline internal-traffic firewall rule. GKE itself auto-manages the
# firewall rules needed for the control plane to reach nodes for webhooks
# (when using private clusters with authorized networks) — not duplicated
# here, since re-declaring GKE-managed firewall rules in Terraform tends to
# fight with GKE's own reconciliation of them.
resource "google_compute_firewall" "internal" {
  name    = "${var.name}-allow-internal"
  project = var.project_id
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}
