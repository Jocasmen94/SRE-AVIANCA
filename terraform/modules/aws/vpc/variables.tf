variable "name" {
  type        = string
  description = "Name prefix for all resources"
}

variable "cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet CIDRs — one per AZ (for EKS nodes)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnet CIDRs — for NLB/ALB"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "azs" {
  type        = list(string)
  description = "Availability zones"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name — used for subnet tags required by EKS"
}
