data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)
  id       = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "Subnet ${each.value} does not belong to vpc_id ${var.vpc_id}. Check for a copy-paste error in the customer-provided subnet IDs."
    }
    postcondition {
      condition     = lookup(self.tags, "kubernetes.io/role/internal-elb", "") == "1" || lookup(self.tags, "kubernetes.io/cluster/${var.cluster_name}", "") != ""
      error_message = <<-EOT
        Subnet ${each.value} is missing required EKS discovery tags.
        Private subnets need either 'kubernetes.io/role/internal-elb = 1'
        or 'kubernetes.io/cluster/${var.cluster_name} = shared' (or 'owned').
        Ask the customer to add these tags, or add them out-of-band before
        re-running plan — Terraform will not add tags to resources it
        didn't create in this BYO-VPC path, to avoid surprising a customer
        who manages their own VPC tagging.
      EOT
    }
  }
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "Subnet ${each.value} does not belong to vpc_id ${var.vpc_id}."
    }
    postcondition {
      condition     = lookup(self.tags, "kubernetes.io/role/elb", "") == "1" || lookup(self.tags, "kubernetes.io/cluster/${var.cluster_name}", "") != ""
      error_message = "Public subnet ${each.value} is missing 'kubernetes.io/role/elb = 1' — internet-facing load balancers won't auto-discover it."
    }
  }
}
