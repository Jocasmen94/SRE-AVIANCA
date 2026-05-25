output "gke_cluster_name" {
  value       = module.gke.cluster_name
  description = "gcloud container clusters get-credentials <valor> --zone us-central1-a --project northern-bliss-421915"
}

output "gke_location" {
  value = module.gke.location
}

output "gke_cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "node_sa_email" {
  value = module.gcp_service_accounts.node_sa_email
}

output "dns_name_servers" {
  value       = var.enable_dns && var.gateway_ip_gke != "" ? module.gcp_dns[0].name_servers : []
  description = "NS records — apuntar desde tu registrar a estos servidores"
}
