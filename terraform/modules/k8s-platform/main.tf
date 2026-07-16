# Cluster-scoped platform addons the workload chart assumes exist
# (metrics-server for HPA, ingress-nginx for the default ingress class,
# cluster-autoscaler so HPA scale-out isn't capped by static node count).
# These are cluster infrastructure, not the customer's application, so they
# live in Terraform rather than the application Helm chart — same
# reasoning as why the VPC/EKS cluster itself is Terraform, not kubectl.

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
