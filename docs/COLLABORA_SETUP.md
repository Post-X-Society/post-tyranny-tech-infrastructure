# Collabora Office Setup

## Password Configuration

Add the following to `secrets/clients/test.sops.yaml`:

```bash
cd infrastructure
export SOPS_AGE_KEY_FILE="$PWD/keys/age-key.txt"
sops secrets/clients/test.sops.yaml
```

Then add this line:

```yaml
collabora_admin_password: <generate-strong-password-here>
```

Replace `<generate-strong-password-here>` with a strong password generated using:
```bash
openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
```

Save and exit. SOPS will automatically re-encrypt the file.

## Features Added

### 1. Collabora Office Container
- Online document editing (Word, Excel, PowerPoint)
- Integrated with Nextcloud via WOPI protocol
- Accessible at: https://office.{client}.vrije.cloud
- Resource limits: 1GB RAM, 2 CPUs

### 2. Separate Cron Container
- Dedicated container for background jobs
- Uses same image as Nextcloud
- Shares data volume
- Runs `/cron.sh` entrypoint

### 3. Two-Factor Authentication
Apps installed:
- `twofactor_totp` - TOTP authenticator apps (Google Authenticator, Authy, etc.)
- `twofactor_admin` - Admin enforcement
- `twofactor_backupcodes` - Backup codes for account recovery

Configuration:
- 2FA enforced for all users
- Users must set up 2FA on first login (after SSO)

### 4. Dual-Cache Strategy
- **APCu**: Local in-memory cache (fast, single-server)
- **Redis**: Distributed cache and file locking (shared across containers)

Configuration:
```php
'memcache.local' => '\\OC\\Memcache\\APCu',
'memcache.distributed' => '\\OC\\Memcache\\Redis',
'memcache.locking' => '\\OC\\Memcache\\Redis',
```

### 5. Maintenance Window
- Set to 2:00 AM for automatic maintenance tasks
- Minimizes user disruption

## Deployment

After adding the Collabora password, redeploy:

```bash
cd infrastructure/ansible
export SOPS_AGE_KEY_FILE="../keys/age-key.txt"
export HCLOUD_TOKEN="..."

ansible-playbook -i hcloud.yml playbooks/deploy.yml
```

## Collabora Configuration in Nextcloud

The automation configures:
- WOPI URL: `https://office.{client}.vrije.cloud`
- WOPI Allowlist: Docker internal networks (172.18.0.0/16, 172.21.0.0/16)
- SSL termination: Handled by Traefik

## Testing

### 1. Test Collabora Office

1. Login to Nextcloud
2. Create a new document (File → New → Document)
3. Should open Collabora Online editor
4. If it doesn't load, check:
   - Collabora container is running: `docker ps | grep collabora`
   - WOPI URL is configured: `docker exec -u www-data nextcloud php occ config:app:get richdocuments wopi_url`
   - Network connectivity between containers

### 2. Test Two-Factor Authentication

1. Login to Nextcloud (via SSO or direct)
2. Should be prompted to set up 2FA
3. Use authenticator app to scan QR code
4. Enter TOTP code to verify
5. Save backup codes

### 3. Test Cron Jobs

Check if cron is running:
```bash
docker logs nextcloud-cron
```

Should see periodic job execution logs.

### 4. Test Caching

Check configuration:
```bash
docker exec -u www-data nextcloud php occ config:list system
```

Should show APCu and Redis configuration.

## Troubleshooting

### Collabora Not Loading

**Symptom**: Blank page or "Failed to load" when creating documents

**Solutions**:
1. Check Collabora is running: `docker ps | grep collabora`
2. Check Collabora logs: `docker logs collabora`
3. Verify WOPI URL: Should be `https://office.{client}.vrije.cloud`
4. Check network allowlist includes Nextcloud container IP
5. Test Collabora directly: Visit `https://office.{client}.vrije.cloud` (should show Collabora page)

### 2FA Not Enforcing

**Symptom**: Users can skip 2FA setup

**Solution**:
```bash
docker exec -u www-data nextcloud php occ config:system:set twofactor_enforced --value="true" --type=boolean
```

### Cron Not Running

**Symptom**: Background jobs not executing

**Solutions**:
1. Check container: `docker ps | grep nextcloud-cron`
2. Check logs: `docker logs nextcloud-cron`
3. Restart: `docker restart nextcloud-cron`

### Cache Not Working

**Symptom**: Slow performance

**Solutions**:
1. Verify APCu is installed: `docker exec nextcloud php -m | grep apcu`
2. Verify Redis connection: `docker exec nextcloud-redis redis-cli ping`
3. Check config: `docker exec -u www-data nextcloud php occ config:list system`

## Security Considerations

### Collabora Admin Password

The Collabora admin interface is protected by username/password:
- Username: `admin`
- Password: Stored in secrets (SOPS encrypted)
- Access: https://office.{client}.vrije.cloud/browser/dist/admin/admin.html

**Recommendation**: Change password after first deployment.

### 2FA Backup Codes

Users receive backup codes when setting up 2FA. These should be:
- Stored securely (password manager or printed)
- Used only if TOTP device is lost
- Regenerated after use

### Network Isolation

Collabora and Nextcloud communicate over Docker internal network:
- Not exposed to public internet
- WOPI protocol secured by allowlist
- SSL termination at Traefik edge

## Performance Tuning

### Collabora Resource Limits

Default: 1GB RAM, 2 CPUs

Adjust in `docker-compose.nextcloud.yml.j2`:
```yaml
deploy:
  resources:
    limits:
      memory: 2g  # Increase for heavy usage
      cpus: '4'   # More CPUs for concurrent users
```

### Nextcloud PHP Memory

Default: 512M

Increase in `defaults/main.yml`:
```yaml
nextcloud_php_memory_limit: "1G"
```

### Redis Memory

Redis uses system memory dynamically. Monitor with:
```bash
docker exec nextcloud-redis redis-cli INFO memory
```

## References

- [Collabora Online Documentation](https://www.collaboraoffice.com/code/)
- [Nextcloud WOPI Integration](https://docs.nextcloud.com/server/latest/admin_manual/office/configuration.html)
- [Nextcloud Two-Factor Auth](https://docs.nextcloud.com/server/latest/admin_manual/configuration_user/two_factor-auth.html)
- [Nextcloud Caching](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html)
