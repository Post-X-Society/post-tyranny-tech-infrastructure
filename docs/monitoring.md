# Uptime Monitoring with Uptime Kuma

**Status**: ✅ Deployed
**URL**: http://94.130.231.155:3001 (will be https://status.postxsociety.cloud after DNS setup)
**Server**: External monitoring server (94.130.231.155)

## Overview

Uptime Kuma provides centralized monitoring for all Post-Tyranny Tech (PTT) client services.

## Architecture

```
External Monitoring Server (94.130.231.155)
└── Uptime Kuma (Docker container)
    ├── Port: 3001
    ├── Volume: uptime-kuma-data
    └── Network: proxy (nginx-proxy)
```

**Why external server?**
- ✅ Independent from PTT infrastructure
- ✅ Can monitor infrastructure failures
- ✅ Monitors dev server too
- ✅ Single point of monitoring for all clients

## Deployment

### Server Configuration

- **Host**: 94.130.231.155
- **OS**: Ubuntu 22.04
- **Docker Compose**: `/opt/docker/uptime-kuma/docker-compose.yml`
- **SSH Access**: `ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155`

### Docker Compose Configuration

```yaml
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    volumes:
      - uptime-kuma-data:/app/data
    ports:
      - "3001:3001"
    restart: unless-stopped
    environment:
      - TZ=Europe/Amsterdam
    labels:
      - "VIRTUAL_HOST=status.postxsociety.cloud"
      - "LETSENCRYPT_HOST=status.postxsociety.cloud"
      - "LETSENCRYPT_EMAIL=admin@postxsociety.cloud"
    networks:
      - proxy

volumes:
  uptime-kuma-data:

networks:
  proxy:
    external: true
```

## Initial Setup

### 1. Access Uptime Kuma

Open in browser:
```
http://94.130.231.155:3001
```

### 2. Create Admin Account

On first access, you'll be prompted to create an admin account:
- **Username**: admin (or your preferred username)
- **Password**: Use a strong password (store in password manager)

### 3. Configure Monitors for PTT Clients

Create the following monitors:

#### Dev Client Monitors

| Name | Type | URL | Interval |
|------|------|-----|----------|
| Dev - Authentik | HTTP(S) | https://auth.dev.vrije.cloud | 5 min |
| Dev - Nextcloud | HTTP(S) | https://nextcloud.dev.vrije.cloud | 5 min |
| Dev - Authentik SSL | Certificate | auth.dev.vrije.cloud:443 | 1 day |
| Dev - Nextcloud SSL | Certificate | nextcloud.dev.vrije.cloud:443 | 1 day |

#### Green Client Monitors

| Name | Type | URL | Interval |
|------|------|-----|----------|
| Green - Authentik | HTTP(S) | https://auth.green.vrije.cloud | 5 min |
| Green - Nextcloud | HTTP(S) | https://nextcloud.green.vrije.cloud | 5 min |
| Green - Authentik SSL | Certificate | auth.green.vrije.cloud:443 | 1 day |
| Green - Nextcloud SSL | Certificate | nextcloud.green.vrije.cloud:443 | 1 day |

### 4. Configure HTTP(S) Monitor Settings

For each HTTP(S) monitor:
- **Monitor Type**: HTTP(S)
- **Friendly Name**: [As per table above]
- **URL**: [As per table above]
- **Heartbeat Interval**: 300 seconds (5 minutes)
- **Retries**: 3
- **Retry Interval**: 60 seconds
- **HTTP Method**: GET
- **Expected Status Code**: 200-299
- **Follow Redirects**: Yes
- **Ignore TLS/SSL Error**: No
- **Timeout**: 48 seconds

### 5. Configure SSL Certificate Monitors

For each SSL monitor:
- **Monitor Type**: Certificate Expiry
- **Friendly Name**: [As per table above]
- **Hostname**: [As per table above - domain only, no https://]
- **Port**: 443
- **Certificate Expiry Days**: 30 (warn when < 30 days remaining)
- **Heartbeat Interval**: 86400 seconds (1 day)

### 6. Configure Notification Channels

#### Email Notifications (Recommended)

1. Go to **Settings** → **Notifications**
2. Click **Setup Notification**
3. Select **Email (SMTP)**
4. Configure SMTP settings (use existing server SMTP or service like Mailgun)
5. Test notification
6. Apply to all monitors

#### Notification Settings

Configure alerts for:
- ✅ **Service Down** - immediate notification
- ✅ **Service Up** - immediate notification (after downtime)
- ✅ **SSL Certificate** - 30 days before expiry
- ✅ **SSL Certificate** - 7 days before expiry

## Management

### View Uptime Kuma Logs

```bash
ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155
docker logs uptime-kuma --tail 100 -f
```

### Restart Uptime Kuma

```bash
ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155
cd /opt/docker/uptime-kuma
docker compose restart
```

### Stop/Start Uptime Kuma

```bash
ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155
cd /opt/docker/uptime-kuma

# Stop
docker compose down

# Start
docker compose up -d
```

### Backup Uptime Kuma Data

```bash
ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155
docker run --rm \
  -v uptime-kuma_uptime-kuma-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/uptime-kuma-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore Uptime Kuma Data

```bash
ssh -i ~/.ssh/hetzner_deploy deploy@94.130.231.155
cd /opt/docker/uptime-kuma
docker compose down

docker run --rm \
  -v uptime-kuma_uptime-kuma-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/uptime-kuma-backup-YYYYMMDD.tar.gz"

docker compose up -d
```

## Adding New Client to Monitoring

When deploying a new PTT client, add these monitors:

1. **Authentik HTTP(S)**: `https://auth.<client>.vrije.cloud`
2. **Nextcloud HTTP(S)**: `https://nextcloud.<client>.vrije.cloud`
3. **Authentik SSL**: `auth.<client>.vrije.cloud:443`
4. **Nextcloud SSL**: `nextcloud.<client>.vrije.cloud:443`

### Future Enhancement: Automated Monitor Creation

Create a script to automatically add/remove monitors via Uptime Kuma API:

```bash
# scripts/add-client-to-monitoring.sh
#!/bin/bash
CLIENT_NAME=$1
# Use Uptime Kuma API to create monitors
# See: https://github.com/louislam/uptime-kuma/wiki/API
```

## Status Page (Optional)

Uptime Kuma supports public status pages. To enable:

1. Go to **Status Pages**
2. Click **Add New Status Page**
3. Configure:
   - **Name**: PTT Service Status
   - **Slug**: ptt-status
   - **Theme**: Choose theme
4. Add monitors to display
5. Click **Save**
6. Access at: `http://94.130.231.155:3001/status/ptt-status`

## DNS Setup (Optional)

To access via friendly domain:

### Option 1: Add to vrije.cloud DNS

Add A record:
```
status.vrije.cloud → 94.130.231.155
```

Then access at: `https://status.postxsociety.cloud` (via nginx-proxy SSL)

### Option 2: Use postxsociety.cloud

The server already has nginx-proxy configured with:
- Virtual Host: `status.postxsociety.cloud`
- Let's Encrypt SSL auto-provisioning

Just add DNS A record:
```
status.postxsociety.cloud → 94.130.231.155
```

## Monitoring Strategy

### Check Intervals

- **HTTP(S) endpoints**: Every 5 minutes
- **SSL certificates**: Once per day

### Alert Thresholds

- **Downtime**: Immediate alert after 3 failed retries (3 minutes)
- **SSL expiry**: Warn at 30 days, critical at 7 days

### Response Times

Monitor response times to detect performance degradation:
- **Normal**: < 500ms
- **Warning**: 500ms - 2s
- **Critical**: > 2s

## Troubleshooting

### Monitor shows "Down" but service is accessible

1. Check if URL is correct
2. Verify SSL certificate is valid: `openssl s_client -connect domain:443`
3. Check if service blocks monitoring IP: `curl -I https://domain`
4. Review Uptime Kuma logs: `docker logs uptime-kuma`

### False positives

If monitors show intermittent failures:
1. Increase retry count to 5
2. Increase timeout to 60 seconds
3. Check server resources: `docker stats uptime-kuma`

### SSL certificate monitor failing

1. Verify port 443 is accessible: `nc -zv domain 443`
2. Check certificate expiry: `echo | openssl s_client -connect domain:443 2>/dev/null | openssl x509 -noout -dates`

## Metrics and Reports

Uptime Kuma tracks:
- ✅ Uptime percentage (24h, 7d, 30d, 1y)
- ✅ Response time graphs
- ✅ Incident history
- ✅ Certificate expiry dates

## Integration with PTT Deployment Scripts

### Future: Auto-add monitors on client deployment

Modify `scripts/deploy-client.sh`:

```bash
# After successful deployment
if [ -f "scripts/add-client-to-monitoring.sh" ]; then
    ./scripts/add-client-to-monitoring.sh $CLIENT_NAME
fi
```

### Future: Auto-remove monitors on client destruction

Modify `scripts/destroy-client.sh`:

```bash
# Before destroying client
if [ -f "scripts/remove-client-from-monitoring.sh" ]; then
    ./scripts/remove-client-from-monitoring.sh $CLIENT_NAME
fi
```

## Security Considerations

1. **Access Control**: Only authorized users should access Uptime Kuma
2. **Strong Passwords**: Use strong admin password
3. **HTTPS**: Use HTTPS for web access (via nginx-proxy)
4. **Backup**: Regular backups of monitoring data
5. **Monitor the Monitor**: Consider external monitor for Uptime Kuma itself

## Resources

- **Official Docs**: https://github.com/louislam/uptime-kuma/wiki
- **API Documentation**: https://github.com/louislam/uptime-kuma/wiki/API
- **Docker Hub**: https://hub.docker.com/r/louislam/uptime-kuma

## Related

- Issue #17: Deploy Uptime Kuma for service monitoring
- Client Registry: Track which clients are deployed
- Deployment Scripts: Automated client lifecycle management
