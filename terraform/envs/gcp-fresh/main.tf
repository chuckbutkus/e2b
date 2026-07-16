module "network" {
  source = "../../modules/network/gcp"

  name          = var.cluster_name
  project_id    = var.project_id
  region        = var.region
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
  tags          = var.tags
}

module "cluster" {
  source = "../../modules/cluster/gcp-gke"

  cluster_name          = var.cluster_name
  project_id            = var.project_id
  region                = var.region
  network_self_link     = module.network.network_self_link
  subnetwork_self_link  = module.network.subnetwork_self_link
  pods_range_name       = module.network.pods_range_name
  services_range_name   = module.network.services_range_name
  release_channel       = var.release_channel
  tags                  = var.tags
}

module "node_pool" {
  source = "../../modules/node-pool/gcp-gke"

  cluster_name  = module.cluster.cluster_name
  project_id    = var.project_id
  region        = var.region
  machine_type  = var.node_machine_type
  image_type    = var.node_image_type
  min_count     = var.node_min_count
  max_count     = var.node_max_count
  initial_count = var.node_initial_count
  tags          = var.tags

  depends_on = [module.cluster]
}

# Example workload Workload Identity binding — same role this plays for
# AWS's IRSA module: the thing a deployer wires the Helm chart's
# serviceAccount.annotations."iam.gke.io/gcp-service-account" against, if
# the sre-interview workload ever needs GCP API access (unconfirmed as of
# this writing, per the Helm chart's own README).
#
# module "workload_irsa" {
#   source = "../../modules/workload-identity"
#
#   project_id            = var.project_id
#   gsa_account_id        = "${var.cluster_name}-sre-workload"
#   namespace             = "default"
#   service_account_name  = "sre-workload"
#   workload_pool         = module.cluster.workload_pool
#   project_roles         = []
# }

module "k8s_platform" {
  source = "../../modules/k8s-platform"

  cluster_name               = module.cluster.cluster_name
  region                     = var.region
  install_cluster_autoscaler = false # GKE node-pool autoscaling is native
                                       # (see modules/node-pool/gcp-gke) —
                                       # the separate cluster-autoscaler
                                       # Helm chart is AWS-only in this tree

  depends_on = [module.node_pool]
}
