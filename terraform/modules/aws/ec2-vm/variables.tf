variable "name" {
  type    = string
  default = "sre-sender-vm"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID — same VPC as EKS so Istio mesh can reach the VM"
}

variable "subnet_id" {
  type        = string
  description = "Private subnet ID for the VM"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR — used in SG ingress rules for Istio ports"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key (.pub) for EC2 key pair"
  default     = "~/.ssh/id_rsa.pub"
}
