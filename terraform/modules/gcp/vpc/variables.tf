variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Name prefix for VPC resources"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "subnet_cidr" {
  type    = string
  default = "10.1.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.4.0.0/14"
}

variable "services_cidr" {
  type    = string
  default = "10.56.0.0/20"
}
