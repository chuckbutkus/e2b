output "karpenter_node_role_arn" {
  value = aws_iam_role.karpenter_node.arn
}

output "karpenter_controller_role_arn" {
  value = module.irsa.role_arn
}

output "interruption_queue_name" {
  value = aws_sqs_queue.karpenter_interruption.name
}
