variable "vpc_id" {
  description = "ID of the customer's existing VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of existing private subnets to deploy worker nodes into (at least 2, different AZs)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets (in different AZs) are required for an EKS-compatible VPC."
  }
}

variable "public_subnet_ids" {
  description = "IDs of existing public subnets for internet-facing load balancers. Optional if the customer's ingress is internal-only."
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "Name the EKS cluster will use — required so we can validate the customer's subnets carry the matching kubernetes.io/cluster/<name> tag before anything downstream tries to use them."
  type        = string
}
