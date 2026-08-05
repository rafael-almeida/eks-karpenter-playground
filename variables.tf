variable "aws_region" {
  description = "AWS region in which to create the cluster."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "demo-karpenter-alb"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "ID of the existing VPC in which to create the EKS cluster."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  description = "Existing subnet IDs used by EKS and Karpenter. Use private subnets in at least two availability zones."
  type        = list(string)

  validation {
    condition = (
      length(var.subnet_ids) >= 2 &&
      alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    )
    error_message = "subnet_ids must contain at least two valid subnet IDs."
  }
}

variable "dev0_host" {
  description = "Hostname routed to the ui Service in namespace dev0."
  type        = string
  default     = "dev0.example.com"
}

variable "dev1_host" {
  description = "Hostname routed to the ui Service in namespace dev1."
  type        = string
  default     = "dev1.example.com"
}

variable "tags" {
  description = "Additional tags applied to AWS resources."
  type        = map(string)
  default = {
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}
