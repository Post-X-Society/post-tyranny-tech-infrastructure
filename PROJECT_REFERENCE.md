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
│   └── roles/           # Ansible roles (traefik, authentik, nextcloud, etc.)
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
- **Authentik SSO**: https://auth.test.vrije.cloud
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
```

### Check Service Status
```bash
# List inventory hosts
export HCLOUD_TOKEN="..."
~/.local/bin/ansible-inventory -i hcloud.yml --list

# Run ad-hoc commands
~/.local/bin/ansible test -i hcloud.yml -m shell -a "docker ps"
~/.local/bin/ansible test -i hcloud.yml -m shell -a "docker logs nextcloud 2>&1 | tail -50"
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
- **Authentik 2025.10.3**: Identity provider (OAuth2/OIDC, SAML, LDAP)
- **PostgreSQL 16**: Database for Authentik
- **Nextcloud 30.0.17**: File sync and collaboration
- **Redis**: Caching for Nextcloud
- **MariaDB**: Database for Nextcloud

### Docker Networks
- `traefik`: External network for all web-accessible services
- `authentik-internal`: Internal network for Authentik ↔ PostgreSQL
- `nextcloud-internal`: Internal network for Nextcloud ↔ Redis/DB

### Volumes
- `authentik_authentik-db-data`: Authentik PostgreSQL data
- `authentik_authentik-media`: Authentik uploaded media
- `authentik_authentik-templates`: Custom Authentik templates
- `nextcloud_nextcloud-data`: Nextcloud files and database

## Service Credentials

### Authentik Admin
- **URL**: https://auth.test.vrije.cloud
- **Setup**: Complete initial setup at `/if/flow/initial-setup/`
- **Username**: akadmin (recommended)

### Nextcloud Admin
- **URL**: https://nextcloud.test.vrije.cloud
- **Username**: admin
- **Password**: In `secrets/clients/test.sops.yaml` → `nextcloud_admin_password`
- **SSO**: Login with Authentik button (auto-configured)
