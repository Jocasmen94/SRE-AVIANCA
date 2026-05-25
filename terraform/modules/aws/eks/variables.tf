variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version"
  default     = "1.30"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID — from aws/vpc module output"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EKS nodes"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for EKS control plane"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for managed node group"
  default     = "t3.medium"
}

variable "node_desired" {
  type    = number
  default = 1
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 1
}
