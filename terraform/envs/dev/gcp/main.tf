################################################################################
# GCP — VPC
################################################################################
module "gcp_vpc" {
  source = "../../../modules/gcp/vpc"

  project_id    = var.gcp_project_id
  name          = var.gke_cluster_name
  region        = var.gcp_region
  subnet_cidr   = "10.1.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.56.0.0/20"
}

################################################################################
# GCP — Service Accounts para nodos GKE
################################################################################
module "gcp_service_accounts" {
  source = "../../../modules/gcp/service-accounts"

  project_id = var.gcp_project_id
  name       = var.gke_cluster_name
}

################################################################################
# GCP — GKE Cluster 2
################################################################################
module "gke" {
  source = "../../../modules/gcp/gke"

  project_id   = var.gcp_project_id
  cluster_name = var.gke_cluster_name
  zone         = var.gcp_zone

  network_self_link   = module.gcp_vpc.network_self_link
  subnet_self_link    = module.gcp_vpc.subnet_self_link
  pods_range_name     = module.gcp_vpc.pods_range_name
  services_range_name = module.gcp_vpc.services_range_name
  node_sa_email       = module.gcp_service_accounts.node_sa_email

  node_machine_type = var.gke_node_machine_type
  node_count        = 1
  node_disk_size_gb = 30

  depends_on = [module.gcp_vpc, module.gcp_service_accounts]
}

################################################################################
# GCP — Cloud DNS (opcional)
# Paso 1: deploy sin DNS (enable_dns = false)
# Paso 2: instalar Istio → obtener LB IP del IngressGateway
# Paso 3: terraform apply -var enable_dns=true -var gateway_ip_gke=<IP>
################################################################################
module "gcp_dns" {
  source = "../../../modules/gcp/dns"
  count  = var.enable_dns && var.gateway_ip_gke != "" ? 1 : 0

  project_id = var.gcp_project_id
  zone_name  = var.dns_zone_name
  dns_name   = var.dns_name
  gateway_ip = var.gateway_ip_gke
}
