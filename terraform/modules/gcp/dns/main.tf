resource "google_dns_managed_zone" "this" {
  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name
  description = "Managed zone for SRE Avianca — GKE cluster"

  visibility = "public"
}

# A record pointing to GKE Istio Gateway LoadBalancer
resource "google_dns_record_set" "gateway" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this.name
  name         = var.dns_name
  type         = "A"
  ttl          = var.ttl
  rrdatas      = [var.gateway_ip]
}

# Wildcard A record for subdomains (e.g. sender.avianca.example.com)
resource "google_dns_record_set" "wildcard" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this.name
  name         = "*.${var.dns_name}"
  type         = "A"
  ttl          = var.ttl
  rrdatas      = [var.gateway_ip]
}
