resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  create_namespace = false
  wait             = true

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.role_arn
  }

  # Karpenter's own pods must run on the small "system" node group (or
  # Fargate), never on nodes Karpenter itself provisions — otherwise a
  # scale-to-zero decision could evict the controller that's supposed to
  # notice and reverse it. Pin it with an anti-affinity-style node
  # selector against the system node group's label instead of leaving it
  # schedulable anywhere.
  set {
    name  = "nodeSelector.karpenter\\.sh/controller"
    value = "true"
  }
}

# --- EC2NodeClass: the "how" (AMI family, IAM, network, disk) --------------
resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: ${var.ami_family}
      role: ${aws_iam_role.karpenter_node.name}
      subnetSelectorTerms:
        %{~for id in var.private_subnet_ids~}
        - id: ${id}
        %{~endfor~}
      securityGroupSelectorTerms:
        - id: ${var.cluster_security_group_id}
      tags:
        %{~for k, v in var.tags~}
        ${k}: "${v}"
        %{~endfor~}
        karpenter.sh/discovery: ${var.cluster_name}
      %{~if var.ami_family == "Bottlerocket"~}
      blockDeviceMappings:
        - deviceName: /dev/xvdb
          ebs:
            volumeSize: ${var.bottlerocket_data_volume_size_gb}Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true
      %{~endif~}
  YAML

  depends_on = [helm_release.karpenter]
}

# --- NodePool: the "what/when" (instance shapes, capacity type, limits, disruption) ---
resource "kubectl_manifest" "node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: [${join(", ", [for v in var.capacity_types : "\"${v}\""])}]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: [${join(", ", [for v in var.instance_categories : "\"${v}\""])}]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["4"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      limits:
        cpu: "${var.cpu_limit}"
      disruption:
        consolidationPolicy: ${var.consolidation_policy}
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.ec2_node_class]
}
