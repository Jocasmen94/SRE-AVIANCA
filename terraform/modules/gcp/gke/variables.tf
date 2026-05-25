variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "network_self_link" {
  type        = string
  description = "VPC network self link — from gcp/vpc module"
}

variable "subnet_self_link" {
  type        = string
  description = "Subnet self link — from gcp/vpc module"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary range name for pods — from gcp/vpc module"
}

variable "services_range_name" {
  type        = string
  description = "Secondary range name for services — from gcp/vpc module"
}

variable "node_sa_email" {
  type        = string
  description = "Node service account email — from gcp/service-accounts module"
}

variable "node_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_disk_size_gb" {
  type    = number
  default = 30
}

variable "kubernetes_version" {
  type    = string
  default = "latest"
}
