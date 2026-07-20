# Cluster-scoped platform addons the workload chart assumes exist.
# These are cluster infrastructure shared across workloads, so they live in
# Terraform rather than the application Helm chart — same reasoning as why
# the VPC/EKS cluster itself is Terraform, not kubectl.

resource "helm_release" "metrics_server" {
  count      = var.install_metrics_server ? 1 : 0
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  # NOT setting --kubelet-insecure-tls here — that's a kind-only workaround
  # for self-signed kubelet certs (see the Helm chart's kind testing docs).
  # Real EKS nodes have properly signed kubelet serving certs.
}

resource "helm_release" "ingress_nginx" {
  count            = var.install_ingress_nginx ? 1 : 0
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.3"

  # NLB rather than the legacy Classic LB — matters for target-type=ip
  # compatibility with EKS's VPC CNI pod networking.
  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
    },
  ]
}

resource "helm_release" "cluster_autoscaler" {
  count      = var.install_cluster_autoscaler ? 1 : 0
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.43.2"

  lifecycle {
    precondition {
      condition     = var.cluster_autoscaler_role_arn != ""
      error_message = "install_cluster_autoscaler is true but cluster_autoscaler_role_arn is empty — pass the IRSA role ARN."
    }
  }

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = var.cluster_name
    },
    {
      name  = "awsRegion"
      value = var.region
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.cluster_autoscaler_role_arn
    },
  ]
}

# --- cert-manager -----------------------------------------------------------
# Installs the cert-manager controller and, when acme_email is provided,
# creates two ClusterIssuers: letsencrypt-staging (for validating ACME
# configuration without hitting rate limits) and letsencrypt-prod (for real
# certificates). Both use the HTTP-01 challenge via ingress-nginx, which
# works on both AWS and GCP without any cloud IAM.
#
# Disable (install_cert_manager = false) when the cluster already has
# cert-manager, or when a non-ACME certificate strategy is used (corporate
# CA, commercial CA, AWS ACM with ALB, etc.).

resource "helm_release" "cert_manager" {
  count            = var.install_cert_manager ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_chart_version
  # wait=true is required: the ClusterIssuer kubectl_manifests below depend
  # on the cert-manager CRDs, which are installed by this chart. Without
  # wait, Terraform may attempt to apply the ClusterIssuers before the CRDs
  # are registered, causing a "no matches for kind ClusterIssuer" error.
  wait = true

  set = [
    {
      # Install CRDs as part of the chart release so they are tracked in
      # Terraform state and upgraded with the chart. The alternative
      # (crds.keep=false + manual kubectl apply) is harder to manage.
      name  = "crds.enabled"
      value = "true"
    },
  ]
}

locals {
  create_cluster_issuers = var.install_cert_manager && var.acme_email != ""
}

resource "kubectl_manifest" "cluster_issuer_staging" {
  count = local.create_cluster_issuers ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-staging
    spec:
      acme:
        server: https://acme-staging-v02.api.letsencrypt.org/directory
        email: ${var.acme_email}
        privateKeySecretRef:
          name: letsencrypt-staging-key
        solvers:
          - http01:
              ingress:
                ingressClassName: nginx
  YAML

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "cluster_issuer_prod" {
  count = local.create_cluster_issuers ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ${var.acme_email}
        privateKeySecretRef:
          name: letsencrypt-prod-key
        solvers:
          - http01:
              ingress:
                ingressClassName: nginx
  YAML

  depends_on = [helm_release.cert_manager]
}

# --- external-dns ------------------------------------------------------------
# Watches Ingress and Service resources and creates DNS records in the
# cloud provider's DNS service (Route 53 on AWS, Cloud DNS on GCP).
# Disabled by default: requires write access to the customer's DNS zone,
# which may be managed externally or unavailable.
#
# On AWS: pass external_dns_service_account_annotations with the IRSA role
# ARN. The role is created by the calling env (modules/irsa).
# On GCP: pass external_dns_service_account_annotations with the GSA email
# and set external_dns_google_project to the GCP project ID.

locals {
  external_dns_owner_id = coalesce(var.external_dns_txt_owner_id, var.cluster_name)

  # All Helm set values assembled as a map so they can be passed to a single
  # dynamic "set" block — avoids mixing the set=[...] argument with dynamic
  # set blocks, which the provider does not support simultaneously.
  external_dns_set_values = var.install_external_dns ? merge(
    {
      "provider.name" = var.external_dns_provider
      "txtOwnerId"    = local.external_dns_owner_id
      # upsert-only: create/update records but never delete them. Safer
      # default — a mis-scoped selector won't wipe records it shouldn't own.
      "policy"        = "upsert-only"
    },
    var.external_dns_provider == "google" && var.external_dns_google_project != "" ? {
      "provider.google.project" = var.external_dns_google_project
    } : {},
    {
      for k, v in var.external_dns_service_account_annotations :
      "serviceAccount.annotations.${replace(k, ".", "\\.")}" => v
    }
  ) : {}
}

resource "helm_release" "external_dns" {
  count            = var.install_external_dns ? 1 : 0
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  version          = var.external_dns_chart_version

  dynamic "set" {
    for_each = local.external_dns_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}
