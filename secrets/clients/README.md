# Client Secrets Directory

This directory contains SOPS-encrypted secrets files for each deployed client.

## Files

### Active Clients

- **`dev.sops.yaml`** - Development/canary server secrets
  - Status: Deployed
  - Purpose: Testing and canary deployments

### Templates

- **`template.sops.yaml`** - Template for creating new client secrets
  - Status: Reference only (not deployed)
  - Purpose: Copy this file when onboarding new clients

## Creating Secrets for a New Client

```bash
# 1. Copy the template
cp secrets/clients/template.sops.yaml secrets/clients/newclient.sops.yaml

# 2. Edit with SOPS
export SOPS_AGE_KEY_FILE="./keys/age-key.txt"
sops secrets/clients/newclient.sops.yaml

# 3. Update all fields:
#    - client_name: newclient
#    - client_domain: newclient.vrije.cloud
#    - authentik_domain: auth.newclient.vrije.cloud
#    - nextcloud_domain: nextcloud.newclient.vrije.cloud
#    - REGENERATE all passwords and tokens (never reuse!)

# 4. Deploy the client
./scripts/deploy-client.sh newclient
```

## Important Security Notes

⚠️ **Never commit plaintext secrets!**

- Only `*.sops.yaml` files should be committed
- Temporary files (`*-temp.yaml`, `*.tmp`) are gitignored
- Always verify secrets are encrypted: `file secrets/clients/*.sops.yaml`

⚠️ **Always regenerate secrets for new clients!**

- Never copy passwords between clients
- Use strong random passwords (32+ characters)
- Each client must have unique credentials

## File Naming Convention

- **Production clients**: `clientname.sops.yaml`
- **Development/test**: `dev.sops.yaml`
- **Templates**: `template.sops.yaml`
- **Never commit**: `*-temp.yaml`, `*.tmp`, `*_plaintext.yaml`

## Viewing Secrets

```bash
# View encrypted file (shows SOPS metadata)
cat secrets/clients/dev.sops.yaml

# Decrypt and view (requires age key)
export SOPS_AGE_KEY_FILE="./keys/age-key.txt"
sops -d secrets/clients/dev.sops.yaml
```

## Required Secrets per Client

Each client secrets file must contain:

### Authentik (Identity Provider)
- `authentik_db_password` - PostgreSQL database password
- `authentik_secret_key` - Django secret key
- `authentik_bootstrap_password` - Initial admin (akadmin) password
- `authentik_bootstrap_token` - API token for automation
- `authentik_bootstrap_email` - Admin email address

### Nextcloud (File Storage)
- `nextcloud_admin_user` - Admin username (usually "admin")
- `nextcloud_admin_password` - Admin password
- `nextcloud_db_password` - MariaDB database password
- `nextcloud_db_root_password` - MariaDB root password
- `redis_password` - Redis cache password

### Optional
- `collabora_admin_password` - Collabora Online admin password (if using)

## Troubleshooting

### "No such file or directory: age-key.txt"
```bash
# Ensure SOPS_AGE_KEY_FILE is set correctly
export SOPS_AGE_KEY_FILE="./keys/age-key.txt"
# Or use absolute path
export SOPS_AGE_KEY_FILE="/full/path/to/infrastructure/keys/age-key.txt"
```

### "Failed to decrypt"
- Verify you have the correct age private key
- Check that `.sops.yaml` references the correct age public key
- Ensure the file was encrypted with the same age key

### "File contains plaintext secrets"
```bash
# Check if file is properly encrypted
file secrets/clients/dev.sops.yaml
# Should show: ASCII text (with SOPS encryption metadata)

# Re-encrypt if needed
sops -e -i secrets/clients/dev.sops.yaml
```

## See Also

- [../README.md](../../secrets/README.md) - Secrets management overview
- [../../docs/architecture-decisions.md](../../docs/architecture-decisions.md) - SOPS decision rationale
- [SOPS Documentation](https://github.com/getsops/sops)
