variable "project_id" {
  type = string
}

variable "zone_name" {
  type        = string
  description = "Cloud DNS managed zone name (slug, not FQDN)"
  default     = "sre-avianca-zone"
}

variable "dns_name" {
  type        = string
  description = "DNS name for the managed zone — must end with dot. E.g. 'avianca.example.com.'"
}

variable "gateway_ip" {
  type        = string
  description = "IP of the GKE Istio Gateway LoadBalancer — set after gateway is created"
}

variable "ttl" {
  type    = number
  default = 300
}
