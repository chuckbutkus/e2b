terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
  }

  # backend "gcs" {} configured via
  # `terraform init -backend-config=../../backend-config/gcp-fresh.hcl`,
  # same reasoning as the AWS envs' S3 backend — kept out of the root
  # module so it stays reusable across customer GCP projects.
  #backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GCP has no exec-plugin equivalent as clean as `aws eks get-token` in
# common use — the standard Terraform+GKE pattern instead pulls a
# short-lived access token from the already-authenticated google provider
# via this data source, refreshed on every plan/apply rather than stored.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
