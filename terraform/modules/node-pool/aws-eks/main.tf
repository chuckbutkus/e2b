data "aws_partition" "current" {}

locals {
  is_bottlerocket = startswith(var.ami_type, "BOTTLEROCKET")
}

resource "aws_launch_template" "this" {
  name_prefix = "${var.cluster_name}-"

  # Bottlerocket splits its root disk into an OS partition and a separate
  # data partition (containerd/kubelet storage lives on the latter,
  # conventionally /dev/xvdb) — the default size is small, so size it
  # explicitly. AL2023 uses a single root volume at /dev/xvda instead.
  block_device_mappings {
    device_name = local.is_bottlerocket ? "/dev/xvdb" : "/dev/xvda"
    ebs {
      volume_size           = local.is_bottlerocket ? var.bottlerocket_data_volume_size_gb : 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only — no v1 fallback
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tags = var.tags
}

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    # SSM: allows node-level debugging via Session Manager without requiring
    # SSH or a bastion. On Bottlerocket this only works when the admin
    # container is explicitly enabled via EC2NodeClass userData; on AL2023
    # the SSM agent runs by default. Kept here for parity with the
    # Karpenter node role in modules/node-pool/karpenter.
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  ami_type       = var.ami_type

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  # Managed node groups replace nodes one at a time by default via this
  # block — keep max_unavailable low so a node-group update doesn't take
  # out capacity faster than pods can reschedule elsewhere.
  update_config {
    max_unavailable = 1
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.node_policies]

  lifecycle {
    # cluster-autoscaler/Karpenter own desired_size at runtime once
    # deployed — without this, every `terraform apply` would fight the
    # autoscaler and forcibly reset replica count back to var.desired_size.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
