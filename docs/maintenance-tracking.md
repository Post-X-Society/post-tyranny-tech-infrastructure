# Maintenance and Version Tracking

Comprehensive guide to tracking software versions, maintenance history, and detecting version drift across all deployed clients.

## Overview

The infrastructure tracks:
- **Software versions** - Authentik, Nextcloud, Traefik, Ubuntu
- **Maintenance dates** - Last update, security patches, OS updates
- **Version drift** - Clients running different versions
- **Update history** - Audit trail of changes

All version and maintenance data is stored in [`clients/registry.yml`](../clients/registry.yml).

## Registry Structure

Each client tracks versions and maintenance:

```yaml
clients:
  myclient:
    versions:
      authentik: "2025.10.3"
      nextcloud: "30.0.17"
      traefik: "v3.0"
      ubuntu: "24.04"

    maintenance:
      last_full_update: 2026-01-17
      last_security_patch: 2026-01-17
      last_os_update: 2026-01-17
      last_backup_verified: null
```

## Version Management Scripts

### Collect Client Versions

Query actual deployed versions from a running server:

```bash
# Collect versions from dev client
./scripts/collect-client-versions.sh dev
```

This script:
- Connects to the server via Ansible
- Queries Docker container image tags
- Queries Ubuntu OS version
- Updates the registry automatically

**Output:**
```
Collecting versions for client: dev

Querying deployed versions...
Collecting Docker container versions...
✓ Versions collected

Collected versions:
  Authentik:  2025.10.3
  Nextcloud:  30.0.17
  Traefik:    v3.0
  Ubuntu:     24.04

✓ Registry updated
```

**Requirements:**
- Server must be deployed and reachable
- `HCLOUD_TOKEN` environment variable set
- Ansible configured with dynamic inventory

### Check All Client Versions

Compare versions across all clients:

```bash
# Default: Table format with color coding
./scripts/check-client-versions.sh

# Export as CSV
./scripts/check-client-versions.sh --format=csv

# Export as JSON
./scripts/check-client-versions.sh --format=json

# Show only clients with outdated versions
./scripts/check-client-versions.sh --outdated
```

**Table output:**
```
═══════════════════════════════════════════════════════════════════════════════
                         CLIENT VERSION REPORT
═══════════════════════════════════════════════════════════════════════════════

CLIENT          STATUS          AUTHENTIK       NEXTCLOUD       TRAEFIK         UBUNTU
──────────────────────────────────────────────────────────────────────────────────────────────
dev             deployed        2025.10.3       30.0.17         v3.0            24.04
client1         deployed        2025.10.2       30.0.16         v3.0            24.04

Latest versions:
  Authentik: 2025.10.3
  Nextcloud: 30.0.17
  Traefik:   v3.0
  Ubuntu:    24.04

Note: Red indicates outdated version
```

**CSV output:**
```csv
client,status,authentik,nextcloud,traefik,ubuntu,last_update,outdated
dev,deployed,2025.10.3,30.0.17,v3.0,24.04,2026-01-17,no
client1,deployed,2025.10.2,30.0.16,v3.0,24.04,2026-01-10,yes
```

**JSON output:**
```json
{
  "latest_versions": {
    "authentik": "2025.10.3",
    "nextcloud": "30.0.17",
    "traefik": "v3.0",
    "ubuntu": "24.04"
  },
  "clients": [
    {
      "name": "dev",
      "status": "deployed",
      "versions": {
        "authentik": "2025.10.3",
        "nextcloud": "30.0.17",
        "traefik": "v3.0",
        "ubuntu": "24.04"
      },
      "last_update": "2026-01-17",
      "outdated": false
    }
  ]
}
```

### Detect Version Drift

Identify clients with outdated versions:

```bash
# Default: Check all deployed clients
./scripts/detect-version-drift.sh

# Check clients not updated in 30+ days
./scripts/detect-version-drift.sh --threshold=30

# Check specific application only
./scripts/detect-version-drift.sh --app=authentik

# Summary output for monitoring
./scripts/detect-version-drift.sh --format=summary
```

**Output when drift detected:**
```
⚠ VERSION DRIFT DETECTED

Clients with outdated versions:

• client1
    Authentik: 2025.10.2 → 2025.10.3
    Nextcloud: 30.0.16 → 30.0.17

• client2
    Last update: 2025-12-15 (>30 days ago)

Recommended actions:

1. Test updates on canary server first:
   ./scripts/rebuild-client.sh dev

2. Verify canary health:
   ./scripts/client-status.sh dev

3. Update outdated clients:
   ./scripts/rebuild-client.sh client1
   ./scripts/rebuild-client.sh client2
```

**Exit codes:**
- `0` - No drift detected (all clients up to date)
- `1` - Drift detected (action needed)
- `2` - Error (script failure)

**Summary format** (useful for monitoring):
```
Status: DRIFT DETECTED
Drift: Yes
Clients checked: 5
Clients with outdated versions: 2
Clients not updated in 30 days: 1
Affected clients: client1 client2
```

## Automatic Version Collection

Version collection is **automatically performed** after deployments:

### On New Deployment

`./scripts/deploy-client.sh myclient`:
1. Provisions infrastructure
2. Deploys applications
3. Updates registry with server info
4. **Collects and records versions** ← Automatic

### On Rebuild

`./scripts/rebuild-client.sh myclient`:
1. Destroys old infrastructure
2. Provisions new infrastructure
3. Deploys applications
4. Updates registry
5. **Collects and records versions** ← Automatic

If automatic collection fails (server not ready, network issue):
```
⚠ Could not collect versions automatically
Run manually later: ./scripts/collect-client-versions.sh myclient
```

## Maintenance Workflows

### Security Update Workflow

1. **Check current state**
   ```bash
   ./scripts/check-client-versions.sh
   ```

2. **Update canary first** (dev server)
   ```bash
   ./scripts/rebuild-client.sh dev
   ```

3. **Verify canary**
   ```bash
   # Check health
   ./scripts/client-status.sh dev

   # Verify versions updated
   ./scripts/collect-client-versions.sh dev
   ```

4. **Detect drift** (identify outdated clients)
   ```bash
   ./scripts/detect-version-drift.sh
   ```

5. **Roll out to production**
   ```bash
   # Update each client
   ./scripts/rebuild-client.sh client1
   ./scripts/rebuild-client.sh client2

   # Or batch update (be careful!)
   for client in $(./scripts/list-clients.sh --role=production --format=csv | tail -n +2 | cut -d, -f1); do
       ./scripts/rebuild-client.sh "$client"
       sleep 300  # Wait 5 minutes between updates
   done
   ```

6. **Verify all updated**
   ```bash
   ./scripts/detect-version-drift.sh
   ```

### Monthly Maintenance Check

Run these checks monthly:

```bash
# 1. Version report
./scripts/check-client-versions.sh > reports/versions-$(date +%Y-%m).txt

# 2. Drift detection
./scripts/detect-version-drift.sh --threshold=30

# 3. Client health
for client in $(./scripts/list-clients.sh --status=deployed --format=csv | tail -n +2 | cut -d, -f1); do
    ./scripts/client-status.sh "$client"
done
```

### Update Maintenance Dates

Deployment scripts automatically update `last_full_update`. For other maintenance:

```bash
# After security patches (OS level)
yq eval -i ".clients.myclient.maintenance.last_security_patch = \"$(date +%Y-%m-%d)\"" clients/registry.yml

# After OS updates
yq eval -i ".clients.myclient.maintenance.last_os_update = \"$(date +%Y-%m-%d)\"" clients/registry.yml

# After backup verification
yq eval -i ".clients.myclient.maintenance.last_backup_verified = \"$(date +%Y-%m-%d)\"" clients/registry.yml

# Commit changes
git add clients/registry.yml
git commit -m "chore: Update maintenance dates"
git push
```

## Integration with Monitoring

### Continuous Drift Detection

Set up a cron job or CI pipeline:

```bash
#!/bin/bash
# check-drift.sh - Run daily

cd /path/to/infrastructure

# Check for drift
if ! ./scripts/detect-version-drift.sh --format=summary; then
    # Send alert (Slack, email, etc.)
    ./scripts/detect-version-drift.sh | mail -s "Version Drift Detected" ops@example.com
fi
```

### Export for External Tools

```bash
# Export version data as JSON for monitoring tools
./scripts/check-client-versions.sh --format=json > /var/monitoring/client-versions.json

# Export drift status
./scripts/detect-version-drift.sh --format=summary > /var/monitoring/drift-status.txt
```

### Prometheus Metrics

Convert to Prometheus format:

```bash
#!/bin/bash
# export-metrics.sh

# Count clients by drift status
total=$(./scripts/list-clients.sh --status=deployed --format=csv | tail -n +2 | wc -l)
outdated=$(./scripts/check-client-versions.sh --format=csv --outdated | tail -n +2 | wc -l)
uptodate=$((total - outdated))

echo "# HELP clients_total Total number of deployed clients"
echo "# TYPE clients_total gauge"
echo "clients_total $total"

echo "# HELP clients_outdated Number of clients with outdated versions"
echo "# TYPE clients_outdated gauge"
echo "clients_outdated $outdated"

echo "# HELP clients_uptodate Number of clients with latest versions"
echo "# TYPE clients_uptodate gauge"
echo "clients_uptodate $uptodate"
```

## Version Pinning

To prevent automatic updates, pin versions in Ansible roles:

```yaml
# roles/authentik/defaults/main.yml
authentik_version: "2025.10.3"  # Pinned version

# To update:
# 1. Change pinned version
# 2. Update canary: ./scripts/rebuild-client.sh dev
# 3. Verify and roll out
```

## Troubleshooting

### Version Collection Fails

**Problem:** `collect-client-versions.sh` cannot reach server

**Solutions:**
1. Check server is deployed and running:
   ```bash
   ./scripts/client-status.sh myclient
   ```

2. Verify HCLOUD_TOKEN is set:
   ```bash
   echo $HCLOUD_TOKEN
   ```

3. Test Ansible connectivity:
   ```bash
   cd ansible
   ansible -i hcloud.yml myclient -m ping
   ```

4. Check Docker containers are running:
   ```bash
   ansible -i hcloud.yml myclient -m shell -a "docker ps"
   ```

### Incorrect Version Reported

**Problem:** Registry shows wrong version

**Solutions:**
1. Re-collect versions manually:
   ```bash
   ./scripts/collect-client-versions.sh myclient
   ```

2. Verify Docker images:
   ```bash
   ansible -i hcloud.yml myclient -m shell -a "docker images"
   ```

3. Check container inspect:
   ```bash
   ansible -i hcloud.yml myclient -m shell -a "docker inspect authentik-server | jq '.[0].Config.Image'"
   ```

### Version Drift False Positives

**Problem:** Drift detected for canary with intentionally different version

**Solution:** Use `--app` filter to check specific applications:
```bash
# Check only production-critical apps
./scripts/detect-version-drift.sh --app=authentik
./scripts/detect-version-drift.sh --app=nextcloud
```

## Best Practices

1. **Always test on canary first**
   - Update `dev` client before production
   - Verify health before wider rollout

2. **Stagger production updates**
   - Don't update all clients simultaneously
   - Wait 5-10 minutes between updates
   - Monitor each update for issues

3. **Track maintenance in registry**
   - Keep `last_full_update` current
   - Record `last_security_patch` dates
   - Document backup verification

4. **Regular drift checks**
   - Run weekly: `detect-version-drift.sh`
   - Address drift within 7 days
   - Maintain version consistency

5. **Document version changes**
   - Add notes to registry when pinning versions
   - Commit registry changes with descriptive messages
   - Track major version upgrades separately

6. **Automate reporting**
   - Export weekly version reports
   - Alert on drift detection
   - Dashboard for version overview

## Related Documentation

- [Client Registry](client-registry.md) - Registry system overview
- [Deployment Guide](deployment.md) - Deployment procedures
- [SSH Key Management](ssh-key-management.md) - Security and access
