# Hetzner Cloud API Token
variable "hcloud_token" {
  description = "Hetzner Cloud API Token (Read & Write)"
  type        = string
  sensitive   = true
}

# Hetzner DNS API Token (can be same as Cloud token)
variable "hetznerdns_token" {
  description = "Hetzner DNS API Token"
  type        = string
  sensitive   = true
}

# SSH keys are now per-client, stored in keys/ssh/<client>.pub
# No global ssh_public_key variable needed

# Base Domain (optional - only needed if using DNS)
variable "base_domain" {
  description = "Base domain for client subdomains (e.g., platform.nl) - leave empty if not using DNS"
  type        = string
  default     = ""
}

# Client Configurations
variable "clients" {
  description = "Map of client configurations"
  type = map(object({
    server_type            = string       # e.g., "cx22" (2 vCPU, 4 GB RAM)
    location               = string       # e.g., "fsn1" (Falkenstein), "nbg1" (Nuremberg), "hel1" (Helsinki)
    subdomain              = string       # e.g., "alpha" for alpha.platform.nl
    apps                   = list(string) # e.g., ["zitadel", "nextcloud"]
    nextcloud_volume_size  = number       # Size in GB for Nextcloud data volume (min 10, max 10000)
  }))
  default = {}
}

# Enable automated snapshots
variable "enable_snapshots" {
  description = "Enable automated daily snapshots (20% of server cost)"
  type        = bool
  default     = true
}
