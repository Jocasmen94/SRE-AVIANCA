output "zone_name" {
  value = google_dns_managed_zone.this.name
}

output "name_servers" {
  value       = google_dns_managed_zone.this.name_servers
  description = "Delegate these NS records from your domain registrar to use this zone"
}

output "dns_name" {
  value = google_dns_managed_zone.this.dns_name
}
