# DNS Configuration for vrije.cloud using hcloud provider
# The zone already exists in Hetzner Console, so we reference it as a data source

# Reference the existing DNS zone
data "hcloud_zone" "main" {
  name = var.base_domain
}

# A Records for client servers (e.g., test.vrije.cloud -> 78.47.191.38)
resource "hcloud_zone_rrset" "client_a" {
  for_each = var.clients

  zone   = data.hcloud_zone.main.name
  name   = each.value.subdomain
  type   = "A"
  ttl    = 300
  records = [
    {
      value   = hcloud_server.client[each.key].ipv4_address
      comment = "Client ${each.key} server"
    }
  ]
}

# Wildcard A record for each client (e.g., *.test.vrije.cloud for zitadel.test.vrije.cloud)
resource "hcloud_zone_rrset" "client_wildcard" {
  for_each = var.clients

  zone   = data.hcloud_zone.main.name
  name   = "*.${each.value.subdomain}"
  type   = "A"
  ttl    = 300
  records = [
    {
      value   = hcloud_server.client[each.key].ipv4_address
      comment = "Wildcard for ${each.key} subdomains (Zitadel, Nextcloud, etc)"
    }
  ]
}

# AAAA Records for IPv6 (e.g., test.vrije.cloud IPv6)
resource "hcloud_zone_rrset" "client_aaaa" {
  for_each = var.clients

  zone   = data.hcloud_zone.main.name
  name   = each.value.subdomain
  type   = "AAAA"
  ttl    = 300
  records = [
    {
      value   = hcloud_server.client[each.key].ipv6_address
      comment = "Client ${each.key} server IPv6"
    }
  ]
}

# Static A record for monitoring server (status.vrije.cloud -> external monitoring server)
resource "hcloud_zone_rrset" "monitoring" {
  zone   = data.hcloud_zone.main.name
  name   = "status"
  type   = "A"
  ttl    = 300
  records = [
    {
      value   = "94.130.231.155"
      comment = "Uptime Kuma monitoring server"
    }
  ]
}
