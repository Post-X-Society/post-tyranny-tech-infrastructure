# DNS Configuration
# OPTIONAL: Only used if you have a domain registered in Hetzner DNS
# Comment out this entire file if you don't have a domain yet

# Uncomment below when you have a domain registered in Hetzner DNS
/*
# DNS Zone (must already exist in Hetzner DNS)
data "hetznerdns_zone" "main" {
  name = var.base_domain
}

# A Records for client servers
resource "hetznerdns_record" "client_a" {
  for_each = var.clients

  zone_id = data.hetznerdns_zone.main.id
  name    = each.value.subdomain
  type    = "A"
  value   = hcloud_server.client[each.key].ipv4_address
  ttl     = 300
}

# Wildcard A record for each client (for subdomains like auth.alpha.platform.nl)
resource "hetznerdns_record" "client_wildcard" {
  for_each = var.clients

  zone_id = data.hetznerdns_zone.main.id
  name    = "*.${each.value.subdomain}"
  type    = "A"
  value   = hcloud_server.client[each.key].ipv4_address
  ttl     = 300
}

# AAAA Records for IPv6
resource "hetznerdns_record" "client_aaaa" {
  for_each = var.clients

  zone_id = data.hetznerdns_zone.main.id
  name    = each.value.subdomain
  type    = "AAAA"
  value   = hcloud_server.client[each.key].ipv6_address
  ttl     = 300
}
*/
