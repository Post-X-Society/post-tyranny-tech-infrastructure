# Storage Architecture

Comprehensive guide to storage architecture using Hetzner Volumes for Nextcloud data.

## Overview

The infrastructure uses **Hetzner Volumes** (block storage) for Nextcloud user data, separating application and data layers:

- **Server local disk**: Operating system, Docker images, application code
- **Hetzner Volume**: Nextcloud user files (/var/www/html/data)
- **Docker volumes**: Database and Redis data (ephemeral, can be rebuilt)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Hetzner Cloud Server (cpx22)                                │
│                                                               │
│  ┌──────────────────────┐       ┌────────────────────────┐  │
│  │ Local Disk (80 GB)   │       │ Hetzner Volume (100GB) │  │
│  │                      │       │                        │  │
│  │ - OS (Ubuntu 24.04)  │       │ Mounted at:            │  │
│  │ - Docker images      │       │ /mnt/nextcloud-data    │  │
│  │ - Application code   │       │                        │  │
│  │ - Config files       │       │ Contains:              │  │
│  │                      │       │ - Nextcloud user files │  │
│  │ Docker volumes:      │       │ - Uploaded documents   │  │
│  │ - postgres-db        │       │ - Photos, videos       │  │
│  │ - redis-cache        │       │ - All user data        │  │
│  │ - nextcloud-app      │       │                        │  │
│  └──────────────────────┘       └────────────────────────┘  │
│           │                                │                  │
│           └────────────────────────────────┘                  │
│                  Both accessible to                          │
│                  Docker containers                           │
└─────────────────────────────────────────────────────────────┘
```

## Benefits

### 1. Data Independence
- User data survives server rebuilds
- Can detach volume from one server and attach to another
- Easier disaster recovery

### 2. Flexible Scaling
- Resize storage without touching server
- Pay only for storage you need
- Start small (100 GB), grow as needed

### 3. Better Separation
- Application layer (ephemeral, can be rebuilt)
- Data layer (persistent, backed up)
- Clear distinction between code and content

### 4. Simplified Backups
- Snapshot volumes independently
- Smaller, faster snapshots (only data, not OS)
- Point-in-time recovery of user files

### 5. Cost Optimization
- Small clients: 50 GB (~€2.70/month)
- Medium clients: 100 GB (~€5.40/month)
- Large clients: 250+ GB (~€13.50+/month)
- Only pay for what you use

## Volume Specifications

| Feature | Value |
|---------|-------|
| Minimum size | 10 GB |
| Maximum size | 10 TB (10,000 GB) |
| Pricing | €0.054/GB/month |
| Performance | Fast NVMe SSD |
| IOPS | High performance |
| Filesystem | ext4 (pre-formatted) |
| Snapshots | Supported |
| Backups | Via Hetzner API |

## How It Works

### 1. OpenTofu Creates Volume

When deploying a client:

```hcl
# tofu/volumes.tf
resource "hcloud_volume" "nextcloud_data" {
  for_each = var.clients

  name     = "nextcloud-data-${each.key}"
  size     = each.value.nextcloud_volume_size  # e.g., 100 GB
  location = each.value.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "nextcloud_data" {
  for_each  = var.clients
  volume_id = hcloud_volume.nextcloud_data[each.key].id
  server_id = hcloud_server.client[each.key].id
  automount = false
}
```

### 2. Ansible Mounts Volume

During deployment:

```yaml
# ansible/roles/nextcloud/tasks/mount-volume.yml
- Find volume device at /dev/disk/by-id/scsi-0HC_Volume_*
- Format as ext4 (if not already formatted)
- Mount at /mnt/nextcloud-data
- Create data directory with proper permissions
```

### 3. Docker Uses Mount

Docker Compose configuration:

```yaml
services:
  nextcloud:
    volumes:
      - nextcloud-app:/var/www/html           # Application code (local)
      - /mnt/nextcloud-data/data:/var/www/html/data  # User data (volume)
```

## Directory Structure

### On Server Local Disk

```
/var/lib/docker/volumes/
├── nextcloud-app/           # Nextcloud application code
├── nextcloud-db-data/       # PostgreSQL database
└── nextcloud-redis-data/    # Redis cache

/opt/docker/
├── authentik/               # Authentik configuration
├── nextcloud/               # Nextcloud docker-compose.yml
└── traefik/                 # Traefik configuration
```

### On Hetzner Volume

```
/mnt/nextcloud-data/
└── data/                    # Nextcloud user data directory
    ├── admin/               # Admin user files
    ├── user1/               # User 1 files
    ├── user2/               # User 2 files
    └── appdata_*/           # Application data
```

## Volume Sizing Guidelines

### Small Clients (1-10 users)
- **Starting size**: 50 GB
- **Monthly cost**: ~€2.70
- **Use case**: Personal use, small teams
- **Growth**: +10 GB increments

### Medium Clients (10-50 users)
- **Starting size**: 100 GB
- **Monthly cost**: ~€5.40
- **Use case**: Small businesses, departments
- **Growth**: +25 GB increments

### Large Clients (50-200 users)
- **Starting size**: 250 GB
- **Monthly cost**: ~€13.50
- **Use case**: Medium businesses
- **Growth**: +50 GB increments

### Enterprise Clients (200+ users)
- **Starting size**: 500 GB+
- **Monthly cost**: ~€27+
- **Use case**: Large organizations
- **Growth**: +100 GB increments

**Pro tip**: Start conservative and grow as needed. Resizing is online and takes seconds.

## Volume Operations

### Resize Volume

Increase volume size (cannot decrease):

```bash
./scripts/resize-client-volume.sh <client> <new_size_gb>
```

Example:
```bash
# Resize dev client from 100 GB to 200 GB
./scripts/resize-client-volume.sh dev 200
```

The script will:
1. Resize via Hetzner API
2. Expand filesystem
3. Verify new size
4. Show cost increase

**Note**: Resizing is **online** (no downtime) and **instant**.

### Snapshot Volume

Create a point-in-time snapshot:

```bash
# Via Hetzner Cloud Console
# Or via API:
hcloud volume create-snapshot nextcloud-data-dev \
    --description "Before major update"
```

### Restore from Snapshot

1. Create new volume from snapshot
2. Attach to server
3. Update mount in Ansible
4. Restart Nextcloud containers

### Detach and Move Volume

Move data between servers:

```bash
# 1. Stop Nextcloud on old server
ansible old-server -i hcloud.yml -m shell -a "docker stop nextcloud"

# 2. Detach volume via Hetzner Console or API
hcloud volume detach nextcloud-data-client1

# 3. Attach to new server
hcloud volume attach nextcloud-data-client1 --server new-server

# 4. Mount on new server
ansible new-server -i hcloud.yml -m shell -a "mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/nextcloud-data"

# 5. Start Nextcloud
ansible new-server -i hcloud.yml -m shell -a "docker start nextcloud"
```

## Backup Strategy

### Option 1: Hetzner Volume Snapshots

**Pros:**
- Fast (incremental)
- Integrated with Hetzner
- Point-in-time recovery

**Cons:**
- Stored in same region
- Not off-site

**Implementation:**
```bash
# Daily snapshots via cron
0 2 * * * hcloud volume create-snapshot nextcloud-data-prod \
    --description "Daily backup $(date +%Y-%m-%d)"
```

### Option 2: Rsync to External Storage

**Pros:**
- Off-site backup
- Full control
- Can use any storage provider

**Cons:**
- Slower
- More complex

**Implementation:**
```bash
# Backup to external server
ansible client -i hcloud.yml -m shell -a "\
    rsync -av /mnt/nextcloud-data/data/ \
    backup-server:/backups/client/nextcloud/"
```

### Option 3: Nextcloud Built-in Backup

**Pros:**
- Uses Nextcloud's own backup tools
- Consistent with application state

**Cons:**
- Slower than volume snapshots

**Implementation:**
```bash
# Using occ command
docker exec -u www-data nextcloud php occ maintenance:mode --on
rsync -av /mnt/nextcloud-data/ /backup/location/
docker exec -u www-data nextcloud php occ maintenance:mode --off
```

## Performance Considerations

### Hetzner Volume Performance

| Metric | Specification |
|--------|---------------|
| Type | NVMe SSD |
| IOPS | High (exact spec varies) |
| Throughput | Fast sequential R/W |
| Latency | Low (local to server) |

### Optimization Tips

1. **Use ext4 filesystem** (default, well-tested)
2. **Enable discard** for SSD optimization (default in our setup)
3. **Monitor I/O** with `iostat -x 1`
4. **Check volume usage** regularly

### Monitoring

```bash
# Check volume usage
df -h /mnt/nextcloud-data

# Check I/O stats
iostat -x 1 /dev/disk/by-id/scsi-0HC_Volume_*

# Check mount status
mount | grep nextcloud-data
```

## Troubleshooting

### Volume Not Mounting

**Problem:** Volume doesn't mount after server restart

**Solutions:**
1. Check if volume is attached:
   ```bash
   lsblk
   ls -la /dev/disk/by-id/scsi-0HC_Volume_*
   ```

2. Check fstab entry:
   ```bash
   cat /etc/fstab | grep nextcloud-data
   ```

3. Manually mount:
   ```bash
   mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/nextcloud-data
   ```

4. Re-run Ansible:
   ```bash
   ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit client --tags volume
   ```

### Volume Full

**Problem:** Nextcloud reports "not enough space"

**Solutions:**
1. Check usage:
   ```bash
   df -h /mnt/nextcloud-data
   ```

2. Resize volume:
   ```bash
   ./scripts/resize-client-volume.sh client 200
   ```

3. Clean up old files:
   ```bash
   docker exec -u www-data nextcloud php occ files:scan --all
   docker exec -u www-data nextcloud php occ files:cleanup
   ```

### Permission Issues

**Problem:** Nextcloud can't write to volume

**Solutions:**
1. Check ownership:
   ```bash
   ls -la /mnt/nextcloud-data/
   ```

2. Fix permissions:
   ```bash
   chown -R www-data:www-data /mnt/nextcloud-data/data
   chmod -R 750 /mnt/nextcloud-data/data
   ```

3. Re-run mount tasks:
   ```bash
   ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit client --tags volume
   ```

### Volume Detached Accidentally

**Problem:** Volume was detached and lost mount

**Solutions:**
1. Re-attach via Hetzner Console or API
2. Remount:
   ```bash
   ansible client -i hcloud.yml -m shell -a "\
       mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/nextcloud-data"
   ```
3. Restart Nextcloud:
   ```bash
   docker restart nextcloud nextcloud-cron
   ```

## Cost Analysis

### Example Scenarios

**Scenario 1: 10 Clients, 100 GB each**
- Volume cost: 10 × 100 GB × €0.054 = €54/month
- Server cost: 10 × €7/month = €70/month
- **Total**: €124/month

**Scenario 2: 5 Small + 3 Medium + 2 Large**
- Small (50 GB): 5 × €2.70 = €13.50
- Medium (100 GB): 3 × €5.40 = €16.20
- Large (250 GB): 2 × €13.50 = €27.00
- **Volume total**: €56.70/month
- Plus server costs

**Cost Savings vs Local Disk:**
- Can use smaller servers (cheaper compute)
- Pay only for storage needed
- Resize incrementally vs over-provisioning

## Migration from Local Volumes

See [volume-migration.md](volume-migration.md) for detailed migration procedures.

## Related Documentation

- [Volume Migration Guide](volume-migration.md) - Migrating existing clients
- [Deployment Guide](deployment.md) - Full deployment with volumes
- [Maintenance Tracking](maintenance-tracking.md) - Monitoring and updates
