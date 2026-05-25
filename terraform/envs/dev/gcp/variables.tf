variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "gke_cluster_name" {
  type    = string
  default = "sre-avianca-gke"
}

variable "gke_node_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "enable_dns" {
  type        = bool
  description = "Crear Cloud DNS zone + A record. Requiere gateway_ip_gke."
  default     = false
}

variable "dns_zone_name" {
  type    = string
  default = "sre-avianca-zone"
}

variable "dns_name" {
  type        = string
  description = "Dominio para la zona (termina en punto). Ej: sre.tudominio.com."
  default     = "sre.example.com."
}

variable "gateway_ip_gke" {
  type        = string
  description = "IP del Istio IngressGateway LB en GKE — completar después de instalar Istio"
  default     = ""
}
