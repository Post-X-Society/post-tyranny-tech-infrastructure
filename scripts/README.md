# Management Scripts

Automated scripts for managing client infrastructure.

## Prerequisites

Set required environment variables:

```bash
export HCLOUD_TOKEN="your-hetzner-cloud-api-token"
export SOPS_AGE_KEY_FILE="./keys/age-key.txt"
```

## Scripts

### 1. Deploy Fresh Client

**Purpose**: Deploy a brand new client from scratch

**Usage**:
```bash
./scripts/deploy-client.sh <client_name>
```

**What it does** (automatically):
1. **Generates SSH key** (if missing) - Unique per-client key pair
2. **Creates secrets file** (if missing) - From template, opens in editor
3. Provisions VPS server (if not exists)
4. Sets up base system (Docker, Traefik)
5. Deploys Authentik + Nextcloud
6. Configures SSO integration automatically

**Time**: ~10-15 minutes

**Example**:
```bash
# Just run the script - it handles everything!
./scripts/deploy-client.sh newclient

# Script will:
# 1. Generate keys/ssh/newclient + keys/ssh/newclient.pub
# 2. Copy secrets/clients/template.sops.yaml → secrets/clients/newclient.sops.yaml
# 3. Open SOPS editor for you to customize secrets
# 4. Continue with deployment
```

**Requirements**:
- Client must be defined in `tofu/terraform.tfvars`
- Environment variables: `HCLOUD_TOKEN`, `SOPS_AGE_KEY_FILE` (optional)

---

### 2. Rebuild Client

**Purpose**: Destroy and recreate a client's infrastructure from scratch

**Usage**:
```bash
./scripts/rebuild-client.sh <client_name>
```

**What it does**:
1. Destroys existing infrastructure (asks for confirmation)
2. Provisions new VPS server
3. Sets up base system
4. Deploys applications
5. Configures SSO

**Time**: ~10-15 minutes

**Example**:
```bash
./scripts/rebuild-client.sh test
```

**Warning**: This is **destructive** - all data on the server will be lost!

---

### 3. Destroy Client

**Purpose**: Completely remove a client's infrastructure

**Usage**:
```bash
./scripts/destroy-client.sh <client_name>
```

**What it does**:
1. Stops and removes all Docker containers
2. Removes all Docker volumes
3. Destroys VPS server via OpenTofu
4. Removes DNS records

**Time**: ~2-3 minutes

**Example**:
```bash
./scripts/destroy-client.sh test
```

**Warning**: This is **destructive and irreversible**! All data will be lost.

**Note**: Secrets file is preserved after destruction.

---

## Workflow Examples

### Deploy a New Client (Fully Automated)

```bash
# 1. Add to terraform.tfvars
vim tofu/terraform.tfvars
# Add:
#   newclient = {
#     server_type = "cx22"
#     location    = "fsn1"
#     subdomain   = "newclient"
#     apps        = ["authentik", "nextcloud"]
#   }

# 2. Deploy (script handles SSH key + secrets automatically)
./scripts/deploy-client.sh newclient

# That's it! Script will:
# - Generate SSH key if missing
# - Create secrets file from template if missing (opens editor)
# - Deploy everything
```

### Test Changes (Rebuild)

```bash
# Make changes to Ansible roles/playbooks

# Test by rebuilding
./scripts/rebuild-client.sh test

# Verify changes worked
```

### Clean Up

```bash
# Remove test infrastructure
./scripts/destroy-client.sh test
```

## Script Output

All scripts provide:
- ✓ Colored output (green = success, yellow = warning, red = error)
- Progress indicators for each step
- Total time taken
- Service URLs and credentials
- Next steps guidance

## Error Handling

Scripts will exit if:
- Required environment variables not set
- Secrets file doesn't exist
- Confirmation not provided (for destructive operations)
- Any command fails (set -e)

## Safety Features

### Destroy Script
- Requires typing client name to confirm
- Shows what will be deleted
- Preserves secrets file

### Rebuild Script
- Asks for confirmation before destroying
- 10-second delay after destroy before rebuilding
- Shows existing infrastructure before proceeding

### Deploy Script
- Checks for existing infrastructure
- Skips provisioning if server exists
- Validates secrets file exists

## Integration with CI/CD

These scripts can be used in automation:

```bash
# Non-interactive deployment
export HCLOUD_TOKEN="..."
export SOPS_AGE_KEY_FILE="..."

./scripts/deploy-client.sh production
```

For rebuild (skip confirmation):
```bash
# Modify rebuild-client.sh to accept --yes flag
./scripts/rebuild-client.sh production --yes
```

## Troubleshooting

### Script fails with "HCLOUD_TOKEN not set"

```bash
export HCLOUD_TOKEN="your-token-here"
```

### Script fails with "Secrets file not found"

Create the secrets file:
```bash
cp secrets/clients/test.sops.yaml secrets/clients/<client>.sops.yaml
sops secrets/clients/<client>.sops.yaml
```

### Server not reachable during destroy

This is normal if server is already destroyed. The script will skip Docker cleanup and proceed to OpenTofu destroy.

### OpenTofu state conflicts

If multiple people are managing infrastructure:
```bash
cd tofu
tofu state pull
tofu state push
```

Consider using remote state (S3, Terraform Cloud, etc.)

## Performance

Typical timings:

| Operation | Time |
|-----------|------|
| Deploy fresh | 10-15 min |
| Rebuild | 10-15 min |
| Destroy | 2-3 min |

Breakdown:
- Infrastructure provisioning: 2 min
- Server initialization: 1 min
- Base system setup: 3 min
- Application deployment: 5-7 min

## See Also

- [AUTOMATION_STATUS.md](../docs/AUTOMATION_STATUS.md) - Full automation details
- [sso-automation.md](../docs/sso-automation.md) - SSO integration workflow
- [architecture-decisions.md](../docs/architecture-decisions.md) - Design decisions
