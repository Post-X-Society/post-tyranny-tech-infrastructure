# Outputs for Ansible and monitoring

# Client server IPs
output "client_ips" {
  description = "Map of client names to their IPv4 addresses"
  value = {
    for name, server in hcloud_server.client :
    name => server.ipv4_address
  }
}

# Client FQDNs
output "client_fqdns" {
  description = "Map of client names to their fully qualified domain names"
  value = {
    for name, config in var.clients :
    name => "${config.subdomain}.${var.base_domain}"
  }
}

# All client information
output "clients" {
  description = "Complete client information"
  value = {
    for name, server in hcloud_server.client :
    name => {
      id       = server.id
      name     = server.name
      ipv4     = server.ipv4_address
      ipv6     = server.ipv6_address
      location = server.location
      fqdn     = "${var.clients[name].subdomain}.${var.base_domain}"
      apps     = var.clients[name].apps
    }
  }
}

# Ansible inventory hint
output "ansible_inventory_hint" {
  description = "Hint for Ansible dynamic inventory configuration"
  value       = <<-EOT
    Configure Ansible to use Hetzner dynamic inventory:

    1. Set HCLOUD_TOKEN environment variable
    2. Use ansible/hcloud.yml inventory configuration
    3. Run: ansible-inventory -i ansible/hcloud.yml --graph
  EOT
}
