variable "name" {
  description = "Name prefix for all networking resources (e.g. cluster name)."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. At least 2 required for EKS."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least 2 availability zones are required for an EKS-compatible VPC."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ, same order as var.azs). Worker nodes go here."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ, same order as var.azs). NAT gateways / public LBs go here."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ. Cheaper, less resilient — fine for dev/test, not recommended for production."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch (ALL traffic). Cheap relative to the forensic value — retroactively invaluable for incident investigation and compliance audits."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch log retention for VPC flow logs in days. Compliance baselines commonly require ≥365."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
