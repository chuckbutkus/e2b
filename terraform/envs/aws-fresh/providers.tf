terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }

  # backend "s3" block intentionally omitted here — configured via
  # `terraform init -backend-config=../../backend-config/aws-fresh.hcl`
  # so this root module stays reusable across customer AWS accounts
  # without a hardcoded bucket name.
  #backend "s3" {}
}

provider "aws" {
  region = var.region
}

# exec-based auth avoids ever storing a short-lived EKS token in state —
# the CLI plugin fetches a fresh one at every provider call, using
# whatever AWS credentials Terraform itself is already running as.
provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command      = "aws"
    args         = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", var.region]
    }
  }
}

# Only exercised when enable_karpenter=true (see modules/node-pool/karpenter)
# — always declared regardless, since Terraform provider blocks can't be
# conditional, but it does nothing if no kubectl_manifest resource exists.
provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command      = "aws"
    args         = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", var.region]
  }
}
