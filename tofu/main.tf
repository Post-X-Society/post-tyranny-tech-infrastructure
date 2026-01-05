# Provider Configuration
provider "hcloud" {
  token = var.hcloud_token
}

# hcloud provider handles both Cloud and DNS resources

# SSH Key Resource
resource "hcloud_ssh_key" "default" {
  name       = "infrastructure-deploy-key"
  public_key = var.ssh_public_key
}

# Firewall Rules
resource "hcloud_firewall" "client_firewall" {
  name = "client-default-firewall"

  # SSH (restricted - add your management IPs here)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",  # CHANGE THIS: Replace with your management IP
      "::/0"
    ]
  }

  # HTTP (for Let's Encrypt challenge)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

# Client VPS Instances
resource "hcloud_server" "client" {
  for_each = var.clients

  name        = each.key
  server_type = each.value.server_type
  image       = "ubuntu-24.04"
  location    = each.value.location
  ssh_keys    = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.client_firewall.id]

  labels = {
    client = each.key
    role   = "app-server"
    # Note: labels can't contain special chars, store apps list separately if needed
  }

  # Enable backups if requested
  backups = var.enable_snapshots

  # User data for initial setup
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - wget
      - git
      - python3
      - python3-pip
    runcmd:
      - hostnamectl set-hostname ${each.key}
  EOF
}
