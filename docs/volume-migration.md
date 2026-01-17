# Volume Migration Guide

Step-by-step guide for migrating existing Nextcloud clients from local Docker volumes to Hetzner Volumes.

## Overview

This guide covers migrating an existing client (like `dev`) that currently stores Nextcloud data in a Docker volume to the new Hetzner Volume architecture.

**Migration is SAFE and REVERSIBLE** - we keep the old data until verification is complete.

## Prerequisites

- Client currently deployed and running
- SSH access to the server
- Hetzner API token (`HCLOUD_TOKEN`)
- SOPS age key for secrets (`SOPS_AGE_KEY_FILE`)
- At least 30 minutes of maintenance window

## Migration Steps

### Phase 1: Preparation

#### 1. Verify Current State

```bash
# Check client is running
./scripts/client-status.sh dev

# Check current data location
cd ansible
ansible dev -i hcloud.yml -m shell -a "docker inspect nextcloud | jq '.[0].Mounts'"
```

Expected output shows Docker volume:
```json
{
  "Type": "volume",
  "Name": "nextcloud-data",
  "Source": "/var/lib/docker/volumes/nextcloud-data/_data",
  "Destination": "/var/www/html"
}
```

#### 2. Check Data Size

```bash
# Check how much data we're migrating
ansible dev -i hcloud.yml -m shell -a "\
    du -sh /var/lib/docker/volumes/nextcloud-data/_data/data"
```

Note the size - you'll need a volume at least this big (we recommend 2x for growth).

#### 3. Notify Users

⚠️ **Important**: Inform users that Nextcloud will be unavailable during migration (typically 10-30 minutes depending on data size).

### Phase 2: Create and Attach Volume

#### 4. Update OpenTofu Configuration

Already done if you're following the issue #18 implementation:

```hcl
# tofu/terraform.tfvars
clients = {
  dev = {
    # ... existing config ...
    nextcloud_volume_size = 100  # Adjust based on current data size
  }
}
```

#### 5. Apply OpenTofu Changes

```bash
cd tofu

# Review changes
tofu plan

# Apply - this creates the volume and attaches it
tofu apply
```

Expected output:
```
+ hcloud_volume.nextcloud_data["dev"]
+ hcloud_volume_attachment.nextcloud_data["dev"]
```

The volume is now attached to the server but not yet mounted.

### Phase 3: Stop Services and Mount Volume

#### 6. Enable Maintenance Mode

```bash
cd ansible

# Enable Nextcloud maintenance mode
ansible dev -i hcloud.yml -m shell -a "\
    docker exec -u www-data nextcloud php occ maintenance:mode --on"
```

#### 7. Stop Nextcloud Containers

```bash
# Stop Nextcloud and cron (keep database and redis running)
ansible dev -i hcloud.yml -m shell -a "\
    docker stop nextcloud nextcloud-cron"
```

#### 8. Mount the Volume

```bash
# Run Ansible volume mounting tasks
ansible-playbook -i hcloud.yml playbooks/deploy.yml \
    --limit dev \
    --tags volume
```

This will:
- Find the volume device
- Format as ext4 (if needed)
- Mount at `/mnt/nextcloud-data`
- Create data directory with correct permissions
- Add to `/etc/fstab` for persistence

#### 9. Verify Mount

```bash
# Check mount is successful
ansible dev -i hcloud.yml -m shell -a "df -h /mnt/nextcloud-data"
ansible dev -i hcloud.yml -m shell -a "ls -la /mnt/nextcloud-data"
```

### Phase 4: Migrate Data

#### 10. Copy Data to Volume

```bash
# Copy all data from Docker volume to Hetzner Volume
ansible dev -i hcloud.yml -m shell -a "\
    rsync -avh --progress \
    /var/lib/docker/volumes/nextcloud-data/_data/data/ \
    /mnt/nextcloud-data/data/" -b
```

This will take some time depending on data size. Progress is shown.

**Estimated times:**
- 1 GB: ~30 seconds
- 10 GB: ~5 minutes
- 50 GB: ~20 minutes
- 100 GB: ~40 minutes

#### 11. Verify Data Copy

```bash
# Check data was copied
ansible dev -i hcloud.yml -m shell -a "\
    du -sh /mnt/nextcloud-data/data"

# Verify file count matches
ansible dev -i hcloud.yml -m shell -a "\
    find /var/lib/docker/volumes/nextcloud-data/_data/data -type f | wc -l && \
    find /mnt/nextcloud-data/data -type f | wc -l"
```

Both counts should match.

#### 12. Fix Permissions

```bash
# Ensure correct ownership
ansible dev -i hcloud.yml -m shell -a "\
    chown -R www-data:www-data /mnt/nextcloud-data/data" -b
```

### Phase 5: Update Configuration and Restart

#### 13. Update Docker Compose

Already done if you're following the issue #18 implementation. The new template uses:

```yaml
volumes:
  - /mnt/nextcloud-data/data:/var/www/html/data
```

#### 14. Deploy Updated Configuration

```bash
# Deploy updated docker-compose.yml
ansible-playbook -i hcloud.yml playbooks/deploy.yml \
    --limit dev \
    --tags nextcloud,docker
```

This will:
- Update docker-compose.yml
- Restart Nextcloud with new volume mounts

#### 15. Disable Maintenance Mode

```bash
# Turn off maintenance mode
ansible dev -i hcloud.yml -m shell -a "\
    docker exec -u www-data nextcloud php occ maintenance:mode --off"
```

### Phase 6: Verification

#### 16. Test Nextcloud Access

```bash
# Check containers are running
ansible dev -i hcloud.yml -m shell -a "docker ps | grep nextcloud"

# Test HTTPS endpoint
curl -I https://nextcloud.dev.vrije.cloud
```

Expected: HTTP 200 OK

#### 17. Login and Verify Files

1. Open https://nextcloud.dev.vrije.cloud in browser
2. Login with admin credentials
3. Navigate to Files
4. Check that all files are visible
5. Try uploading a new file
6. Try downloading an existing file

#### 18. Run Files Scan

```bash
# Scan all files to update Nextcloud's database
ansible dev -i hcloud.yml -m shell -a "\
    docker exec -u www-data nextcloud php occ files:scan --all"
```

#### 19. Check for Errors

```bash
# Check Nextcloud logs
ansible dev -i hcloud.yml -m shell -a "\
    docker logs nextcloud --tail 50"

# Check for any errors in admin panel
# Login → Settings → Administration → Logging
```

### Phase 7: Cleanup (Optional)

⚠️ **Wait at least 24-48 hours before cleanup to ensure everything works!**

#### 20. Remove Old Docker Volume

After confirming everything works:

```bash
# Remove old Docker volume (THIS IS IRREVERSIBLE!)
ansible dev -i hcloud.yml -m shell -a "\
    docker volume rm nextcloud-data"
```

You'll get an error if any container is still using it (good safety check).

## Rollback Procedure

If something goes wrong, you can rollback:

### Quick Rollback (During Migration)

If you haven't removed the old Docker volume:

```bash
# 1. Stop containers
ansible dev -i hcloud.yml -m shell -a "docker stop nextcloud nextcloud-cron"

# 2. Revert docker-compose.yml to use old volume
# (restore from git or manually edit)

# 3. Restart containers
ansible dev -i hcloud.yml -m shell -a "cd /opt/docker/nextcloud && docker-compose up -d"

# 4. Disable maintenance mode
ansible dev -i hcloud.yml -m shell -a "\
    docker exec -u www-data nextcloud php occ maintenance:mode --off"
```

### Full Rollback (After Cleanup)

If you've removed the old volume but have a backup:

```bash
# 1. Restore from backup to new volume
# 2. Continue with Phase 5 (restart with new config)
```

## Verification Checklist

After migration, verify:

- [ ] Nextcloud web interface loads
- [ ] Can login with existing credentials
- [ ] All files and folders visible
- [ ] Can upload new files
- [ ] Can download existing files
- [ ] Can edit files (if Collabora Online installed)
- [ ] Sharing links still work
- [ ] Mobile apps can sync
- [ ] Desktop clients can sync
- [ ] No errors in Nextcloud logs
- [ ] No errors in admin panel
- [ ] Volume is mounted in `/etc/fstab`
- [ ] Volume mounts after server reboot

## Common Issues

### Issue: "Permission denied" errors

**Cause:** Wrong ownership on volume

**Fix:**
```bash
ansible dev -i hcloud.yml -m shell -a "\
    chown -R www-data:www-data /mnt/nextcloud-data/data" -b
```

### Issue: "Volume not found" in Docker

**Cause:** Docker compose still referencing old volume name

**Fix:**
```bash
# Check docker-compose.yml has correct mount
ansible dev -i hcloud.yml -m shell -a "cat /opt/docker/nextcloud/docker-compose.yml | grep mnt"

# Should show: /mnt/nextcloud-data/data:/var/www/html/data
```

### Issue: Files missing after migration

**Cause:** Incomplete rsync

**Fix:**
```bash
# Re-run rsync (it will only copy missing files)
ansible dev -i hcloud.yml -m shell -a "\
    rsync -avh \
    /var/lib/docker/volumes/nextcloud-data/_data/data/ \
    /mnt/nextcloud-data/data/" -b
```

### Issue: Volume unmounted after reboot

**Cause:** Not in `/etc/fstab`

**Fix:**
```bash
# Re-run volume mounting tasks
ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit dev --tags volume
```

## Post-Migration Benefits

After successful migration:

- ✅ Can resize storage independently: `./scripts/resize-client-volume.sh dev 200`
- ✅ Can snapshot data separately from system
- ✅ Can move data to new server if needed
- ✅ Better separation of application and data
- ✅ Clearer backup strategy

## Timeline Example

Real-world timeline for 10 GB Nextcloud instance:

| Step | Duration | Notes |
|------|----------|-------|
| Preparation | 5 min | Check status, plan |
| Create volume (OpenTofu) | 2 min | Automated |
| Stop services | 1 min | Quick |
| Mount volume | 2 min | Ansible tasks |
| Copy data (10 GB) | 5 min | Depends on size |
| Update config | 2 min | Ansible deploy |
| Restart services | 2 min | Docker restart |
| Verification | 10 min | Manual testing |
| **Total** | **~30 min** | Includes safety checks |

## Related Documentation

- [Storage Architecture](storage-architecture.md) - Understanding volumes
- [Deployment Guide](deployment.md) - New deployments with volumes
- [Client Registry](client-registry.md) - Track migration status
