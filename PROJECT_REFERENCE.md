# Project Reference

Quick reference for essential project information and common operations.

## Project Structure

```
infrastructure/
├── ansible/              # Ansible playbooks and roles
│   ├── hcloud.yml       # Dynamic inventory (Hetzner Cloud)
│   ├── playbooks/       # Main playbooks
│   │   ├── deploy.yml   # Deploy applications to clients
│   │   └── setup.yml    # Setup base server infrastructure
│   └── roles/           # Ansible roles (traefik, zitadel, nextcloud, etc.)
├── keys/
│   └── age-key.txt      # SOPS encryption key (gitignored)
├── secrets/
│   ├── clients/         # Per-client encrypted secrets
│   │   └── test.sops.yaml
│   └── shared.sops.yaml # Shared secrets
└── terraform/           # Infrastructure as Code (Hetzner)
```

## Essential Configuration

### SOPS Age Key
**Location**: `infrastructure/keys/age-key.txt`
**Usage**: Always set before running Ansible:
```bash
export SOPS_AGE_KEY_FILE="../keys/age-key.txt"
```

### Hetzner Cloud Token
**Usage**: Required for dynamic inventory:
```bash
export HCLOUD_TOKEN="MlURmliUzLcGyzCWXWWsZt3DeWxKcQH9ZMGiaaNrFM3VcgnASlEWKhhxLHdWAl0J"
```

### Ansible Paths
**Working Directory**: `infrastructure/ansible/`
**Inventory**: `hcloud.yml` (dynamic, pulls from Hetzner Cloud API)
**Python**: `~/.local/bin/ansible-playbook` (user-local installation)

## Current Deployment

### Client: test
- **Hostname**: test (from Hetzner Cloud)
- **Zitadel**: https://zitadel.test.vrije.cloud
- **Nextcloud**: https://nextcloud.test.vrije.cloud
- **Secrets**: `secrets/clients/test.sops.yaml`

## Common Operations

### Deploy Applications
```bash
cd infrastructure/ansible
export HCLOUD_TOKEN="MlURmliUzLcGyzCWXWWsZt3DeWxKcQH9ZMGiaaNrFM3VcgnASlEWKhhxLHdWAl0J"
export SOPS_AGE_KEY_FILE="../keys/age-key.txt"

# Deploy everything to test client
~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit test

# Force recreate Zitadel (clean database)
~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit test \
  --extra-vars "zitadel_force_recreate=true"
```

### Check Service Status
```bash
# List inventory hosts
export HCLOUD_TOKEN="..."
~/.local/bin/ansible-inventory -i hcloud.yml --list

# Run ad-hoc commands
~/.local/bin/ansible test -i hcloud.yml -m shell -a "docker ps"
~/.local/bin/ansible test -i hcloud.yml -m shell -a "docker logs zitadel 2>&1 | tail -50"
```

### Edit Secrets
```bash
cd infrastructure
export SOPS_AGE_KEY_FILE="keys/age-key.txt"

# Edit client secrets
sops secrets/clients/test.sops.yaml

# View decrypted secrets
sops --decrypt secrets/clients/test.sops.yaml
```

## Architecture Notes

### Service Stack
- **Traefik**: Reverse proxy with automatic Let's Encrypt certificates
- **Zitadel v2.63.7**: Identity provider (OIDC/OAuth2)
- **PostgreSQL 16**: Database for Zitadel
- **Nextcloud 30.0.17**: File sync and collaboration
- **Redis**: Caching for Nextcloud

### Docker Networks
- `traefik`: External network for all web-accessible services
- `zitadel-internal`: Internal network for Zitadel ↔ PostgreSQL
- `nextcloud-internal`: Internal network for Nextcloud ↔ Redis

### Volumes
- `zitadel_zitadel-db-data`: PostgreSQL data
- `zitadel_zitadel-machinekey`: JWT keys for service accounts
- `nextcloud_nextcloud-data`: Nextcloud files and database

## Known Issues

### Zitadel FirstInstance Configuration Bug
**Issue**: ALL `ZITADEL_FIRSTINSTANCE_*` environment variables cause migration errors in v2.63.7:
```
ERROR: duplicate key value violates unique constraint "unique_constraints_pkey"
Errors.Instance.Domain.AlreadyExists
```

**Root Cause**: Bug in Zitadel v2.63.7 FirstInstance migration logic
**Workaround**: Remove all FirstInstance variables; complete initial setup via web UI
**Upstream Issue**: https://github.com/zitadel/zitadel/issues/8791
**Status**: Waiting for upstream fix

### OIDC Automation
**Issue**: Automatic OIDC app provisioning requires manual one-time setup
**Workaround**:
1. Complete Zitadel web UI setup wizard (first access)
2. Create service user with JWT key via web UI
3. Store JWT key in secrets for automated provisioning

**Status**: Manual one-time setup required per Zitadel instance

## Service Credentials

### Zitadel Admin
- **URL**: https://zitadel.test.vrije.cloud
- **Setup**: Complete wizard on first visit (no predefined credentials)

### Nextcloud Admin
- **URL**: https://nextcloud.test.vrije.cloud
- **Username**: admin
- **Password**: In `secrets/clients/test.sops.yaml` → `nextcloud_admin_password`
