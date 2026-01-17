# Client Registry

The client registry is the single source of truth for tracking all deployed clients, their configuration, status, and maintenance history.

## Overview

The registry is stored in [`clients/registry.yml`](../clients/registry.yml) and tracks:
- Deployment status and lifecycle
- Server specifications and location
- Installed applications and versions
- Maintenance history
- Access URLs
- Operational notes

## Registry Structure

```yaml
clients:
  clientname:
    status: deployed              # pending | deployed | maintenance | offboarding | destroyed
    role: production              # canary | production
    deployed_date: 2026-01-17
    destroyed_date: null

    server:
      type: cx22                  # Hetzner server type
      location: nbg1              # Data center location
      ip: 1.2.3.4
      id: "12345678"              # Hetzner server ID

    apps:
      - authentik
      - nextcloud

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

    urls:
      authentik: "https://auth.clientname.vrije.cloud"
      nextcloud: "https://nextcloud.clientname.vrije.cloud"

    notes: ""
```

## Status Values

- **pending**: Client configuration created, not yet deployed
- **deployed**: Client is live and operational
- **maintenance**: Under maintenance, may be temporarily unavailable
- **offboarding**: Being decommissioned
- **destroyed**: Infrastructure removed, secrets archived

## Role Values

- **canary**: Used for testing updates before production rollout (e.g., `dev`)
- **production**: Live client serving real users

## Management Scripts

### List All Clients

```bash
# List all clients in table format
./scripts/list-clients.sh

# Filter by status
./scripts/list-clients.sh --status=deployed
./scripts/list-clients.sh --status=destroyed

# Filter by role
./scripts/list-clients.sh --role=canary
./scripts/list-clients.sh --role=production

# Different output formats
./scripts/list-clients.sh --format=table    # Default, colorized table
./scripts/list-clients.sh --format=json     # JSON output
./scripts/list-clients.sh --format=csv      # CSV export
./scripts/list-clients.sh --format=summary  # Summary statistics
```

### View Client Details

```bash
# Show detailed status for a specific client
./scripts/client-status.sh dev

# Includes:
# - Deployment status and metadata
# - Server specifications
# - Application versions
# - Maintenance history
# - Access URLs
# - Live health checks (if deployed)
```

### Update Registry Manually

```bash
# Mark client as deployed
./scripts/update-registry.sh myclient deploy \
    --role=production \
    --server-ip=1.2.3.4 \
    --server-id=12345678 \
    --server-type=cx22 \
    --server-location=nbg1

# Mark client as destroyed
./scripts/update-registry.sh myclient destroy

# Update status
./scripts/update-registry.sh myclient status --status=maintenance
```

## Automatic Updates

The registry is **automatically updated** by deployment scripts:

### Deploy Script

When running `./scripts/deploy-client.sh myclient`:
1. Creates registry entry if doesn't exist
2. Sets status to `deployed`
3. Records server details from OpenTofu state
4. Sets deployment date
5. Initializes maintenance tracking

### Rebuild Script

When running `./scripts/rebuild-client.sh myclient`:
1. Updates existing registry entry
2. Refreshes server details (IP, ID may change)
3. Updates `last_full_update` date
4. Maintains historical data

### Destroy Script

When running `./scripts/destroy-client.sh myclient`:
1. Sets status to `destroyed`
2. Records destruction date
3. Preserves all historical data
4. Keeps entry for audit trail

## Canary Deployment Workflow

The registry supports canary deployments for safe rollouts:

```bash
# 1. Test on canary server first
./scripts/deploy-client.sh dev

# 2. Verify canary is working
./scripts/client-status.sh dev

# 3. If successful, roll out to production
./scripts/list-clients.sh --role=production | while read client; do
    ./scripts/rebuild-client.sh "$client"
done
```

## Best Practices

### 1. Always Review Registry Before Changes

```bash
# Check current state
./scripts/list-clients.sh

# Review specific client
./scripts/client-status.sh myclient
```

### 2. Use Status Field for Coordination

Mark clients as `maintenance` before disruptive changes:

```bash
./scripts/update-registry.sh myclient status --status=maintenance
# Perform maintenance...
./scripts/update-registry.sh myclient status --status=deployed
```

### 3. Track Maintenance History

Update maintenance fields after significant operations:

```bash
# After security patches
yq eval -i ".clients.myclient.maintenance.last_security_patch = \"$(date +%Y-%m-%d)\"" clients/registry.yml

# After OS updates
yq eval -i ".clients.myclient.maintenance.last_os_update = \"$(date +%Y-%m-%d)\"" clients/registry.yml

# After backup verification
yq eval -i ".clients.myclient.maintenance.last_backup_verified = \"$(date +%Y-%m-%d)\"" clients/registry.yml
```

### 4. Add Operational Notes

Document important events:

```bash
yq eval -i ".clients.myclient.notes = \"Upgraded to Nextcloud 31 on 2026-01-20. Migration successful.\"" clients/registry.yml
```

### 5. Export for Reporting

```bash
# Generate CSV report for management
./scripts/list-clients.sh --format=csv > reports/clients-$(date +%Y%m%d).csv

# Get summary statistics
./scripts/list-clients.sh --format=summary
```

## Version Control

The registry is **version controlled** in Git:

- All changes are tracked
- Audit trail of client lifecycle
- Easy rollback if needed
- Collaborative management

Always commit registry changes:

```bash
git add clients/registry.yml
git commit -m "chore: Update client registry after deployment"
git push
```

## Querying with yq

For advanced queries, use `yq` directly:

```bash
# Find all deployed clients
yq eval '.clients | to_entries | map(select(.value.status == "deployed")) | .[].key' clients/registry.yml

# Find canary clients
yq eval '.clients | to_entries | map(select(.value.role == "canary")) | .[].key' clients/registry.yml

# Get all IPs
yq eval '.clients | to_entries | .[] | "\(.key): \(.value.server.ip)"' clients/registry.yml

# Find clients needing updates (no update in 30+ days)
# (requires date arithmetic with external tools)
```

## Integration with Monitoring

The registry can feed into monitoring systems:

```bash
# Export as JSON for consumption by monitoring tools
./scripts/list-clients.sh --format=json > /var/monitoring/clients.json

# Check health of all deployed clients
for client in $(./scripts/list-clients.sh --status=deployed --format=csv | tail -n +2 | cut -d, -f1); do
    ./scripts/client-status.sh "$client"
done
```

## Troubleshooting

### Registry Out of Sync

If registry doesn't match reality:

```bash
# Get actual state from OpenTofu
cd tofu
tofu state list

# Get actual server details
tofu state show 'hcloud_server.client["myclient"]'

# Update registry manually
./scripts/update-registry.sh myclient deploy \
    --server-ip=<actual-ip> \
    --server-id=<actual-id>
```

### Missing Registry Entry

If a client exists but not in registry:

```bash
# Create entry manually
./scripts/update-registry.sh myclient deploy

# Or rebuild to auto-create
./scripts/rebuild-client.sh myclient
```

### Corrupted Registry File

If YAML is invalid:

```bash
# Check syntax
yq eval . clients/registry.yml

# Restore from Git
git checkout clients/registry.yml

# Or restore from backup
cp clients/registry.yml.backup clients/registry.yml
```

## Related Documentation

- [SSH Key Management](ssh-key-management.md) - Per-client SSH keys
- [Secrets Management](../secrets/clients/README.md) - SOPS-encrypted secrets
- [Deployment Guide](deployment.md) - Full deployment procedures
- [Maintenance Guide](maintenance.md) - Update and patching procedures
