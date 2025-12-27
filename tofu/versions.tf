terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    # DNS provider - optional, only needed if using Hetzner DNS
    # Commented out since DNS is not required initially
    # hetznerdns = {
    #   source  = "timohirt/hetznerdns"
    #   version = "~> 2.4"
    # }
  }
}
