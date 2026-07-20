terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
    kubectl = {
      # gavinbunney/kubectl, not the official kubernetes provider's
      # kubernetes_manifest — that resource requires the CRD to already
      # exist in the cluster at plan time, which breaks the common case of
      # "install Karpenter (which creates the CRDs) and its NodePool/
      # EC2NodeClass resources in the same apply." kubectl_manifest defers
      # schema validation and handles this create-CRD-then-use-CRD
      # ordering correctly as long as depends_on is set (see controller.tf).
      source  = "gavinbunney/kubectl"
      version = ">= 1.14, < 2.0.0"
    }
  }
}
