variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for cluster-autoscaler (from modules/irsa), granting autoscaling:* / ec2:DescribeInstances etc. Only relevant when install_cluster_autoscaler=true (AWS only — GKE's node-pool autoscaling is native, so the GCP env leaves this at its default and sets install_cluster_autoscaler=false)."
  type        = string
  default     = ""
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
