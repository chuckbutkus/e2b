variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for cluster-autoscaler (from modules/irsa), granting autoscaling:* / ec2:DescribeInstances etc."
  type        = string
}

variable "install_ingress_nginx" {
  type    = bool
  default = true
}

variable "install_metrics_server" {
  type    = bool
  default = true
}

variable "install_cluster_autoscaler" {
  type    = bool
  default = true
}
