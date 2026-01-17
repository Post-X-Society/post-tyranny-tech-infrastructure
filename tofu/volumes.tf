# Hetzner Volumes for Nextcloud Data Storage
#
# Each client gets a dedicated volume for Nextcloud user data.
# Volumes are independent from server instances, enabling:
# - Independent storage scaling
# - Easy data migration between servers
# - Simpler backup/restore procedures
# - Better separation of application and data

resource "hcloud_volume" "nextcloud_data" {
  for_each = var.clients

  name     = "nextcloud-data-${each.key}"
  size     = each.value.nextcloud_volume_size
  location = each.value.location
  format   = "ext4"

  labels = {
    client  = each.key
    purpose = "nextcloud-data"
    managed = "terraform"
  }
}

resource "hcloud_volume_attachment" "nextcloud_data" {
  for_each = var.clients

  volume_id = hcloud_volume.nextcloud_data[each.key].id
  server_id = hcloud_server.client[each.key].id
  automount = false # We mount manually via Ansible for better control
}
