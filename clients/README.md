# Client Registry

This directory contains the client registry system for tracking all deployed infrastructure.

## Files

- **[registry.yml](registry.yml)** - Single source of truth for all clients
  - Deployment status and lifecycle
  - Server specifications
  - Application versions
  - Maintenance history
  - Access URLs

## Management Scripts

All scripts are located in [`../scripts/`](../scripts/):

### View Clients

```bash
# List all clients
../scripts/list-clients.sh

# Filter by status
../scripts/list-clients.sh --status=deployed

# Filter by role
../scripts/list-clients.sh --role=canary

# Different formats
../scripts/list-clients.sh --format=table    # Default
../scripts/list-clients.sh --format=json     # JSON
../scripts/list-clients.sh --format=csv      # CSV export
../scripts/list-clients.sh --format=summary  # Statistics
```

### View Client Details

```bash
# Show detailed status with live health checks
../scripts/client-status.sh <client_name>
```

### Update Registry

The registry is **automatically updated** by deployment scripts:
- `deploy-client.sh` - Creates/updates entry on deployment
- `rebuild-client.sh` - Updates entry on rebuild
- `destroy-client.sh` - Marks as destroyed

For manual updates:
```bash
../scripts/update-registry.sh <client_name> <action> [options]
```

## Registry Structure

Each client entry tracks:
- **Status**: `pending` → `deployed` → `maintenance` → `offboarding` → `destroyed`
- **Role**: `canary` (testing) or `production` (live)
- **Server**: Type, location, IP, Hetzner ID
- **Apps**: Installed applications
- **Versions**: Application and OS versions
- **Maintenance**: Update and backup history
- **URLs**: Access endpoints
- **Notes**: Operational documentation

## Canary Deployment

The `dev` client has role `canary` and is used for testing:

```bash
# 1. Test on canary first
../scripts/deploy-client.sh dev

# 2. Verify it works
../scripts/client-status.sh dev

# 3. Roll out to production
for client in $(../scripts/list-clients.sh --role=production --format=csv | tail -n +2 | cut -d, -f1); do
    ../scripts/rebuild-client.sh "$client"
done
```

## Documentation

See [docs/client-registry.md](../docs/client-registry.md) for:
- Complete registry structure reference
- Management script usage
- Best practices
- Integration examples
- Troubleshooting guide

## Requirements

- **yq**: YAML processor (`brew install yq`)
- **jq**: JSON processor (`brew install jq`)
