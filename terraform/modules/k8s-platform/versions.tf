terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
    kubectl = {
      # gavinbunney/kubectl — same rationale as in modules/node-pool/karpenter:
      # kubernetes_manifest validates CRDs at plan time, which fails when the
      # cert-manager chart (which installs the CRDs) and the ClusterIssuer
      # resources that use them are applied in the same run.
      source  = "gavinbunney/kubectl"
      version = ">= 1.14, < 2.0.0"
    }
  }
}
