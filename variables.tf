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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
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
