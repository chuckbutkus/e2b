# Karpenter watches this queue for spot interruption warnings, rebalance
# recommendations, and instance state-change events so it can drain and
# replace a node *before* AWS forcibly reclaims it (spot interruptions give
# ~2 minutes notice — without this wiring, Karpenter has no way to react
# in time and pods just get killed abruptly instead of gracefully drained).

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
      }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

locals {
  interruption_event_rules = {
    spot_interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance_recommendation = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
    scheduled_change = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each    = local.interruption_event_rules
  name        = "${var.cluster_name}-karpenter-${each.key}"
  description = "Forwards ${each.key} events to the Karpenter interruption queue"

  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value["detail-type"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = local.interruption_event_rules
  rule     = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  arn      = aws_sqs_queue.karpenter_interruption.arn
}
