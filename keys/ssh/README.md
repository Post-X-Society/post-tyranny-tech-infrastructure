# SSH Keys Directory

This directory contains **per-client SSH key pairs** for server access.

## Purpose

Each client gets a dedicated SSH key pair to ensure:
- **Isolation**: Compromise of one client ≠ access to others
- **Granular control**: Rotate or revoke keys per-client
- **Security**: Defense in depth, minimize blast radius

## Files

```
keys/ssh/
├── .gitignore          # Protects private keys from git
├── README.md           # This file
├── dev                 # Private key for dev server (gitignored)
├── dev.pub             # Public key for dev server (committed)
├── client1             # Private key for client1 (gitignored)
└── client1.pub         # Public key for client1 (committed)
```

## Generating Keys

Use the helper script:

```bash
./scripts/generate-client-keys.sh <client_name>
```

Or manually:

```bash
ssh-keygen -t ed25519 -f keys/ssh/<client_name> -C "client-<client_name>-deploy-key" -N ""
```

## Security

### What Gets Committed

- ✅ **Public keys** (`*.pub`) - Safe to commit
- ✅ **README.md** - Documentation
- ✅ **`.gitignore`** - Protection rules

### What NEVER Gets Committed

- ❌ **Private keys** (no `.pub` extension) - Gitignored
- ❌ **Temporary files** - Gitignored
- ❌ **Backup keys** - Gitignored

The `.gitignore` file in this directory ensures private keys are never committed:

```gitignore
# NEVER commit SSH private keys
*

# Allow README and public keys only
!.gitignore
!README.md
!*.pub
```

## Backup Strategy

**⚠️ IMPORTANT: Backup private keys securely!**

Private keys must be backed up to prevent lockout:

1. **Password Manager** (Recommended):
   - Store in 1Password, Bitwarden, etc.
   - Tag with client name and server IP

2. **Encrypted Archive**:
   ```bash
   tar czf - keys/ssh/ | gpg -c > ssh-keys-backup.tar.gz.gpg
   ```

3. **Team Vault**:
   - Share securely with team members who need access
   - Document key ownership

## Usage

### SSH Connection

```bash
# Connect to client server
ssh -i keys/ssh/dev root@<server_ip>

# Run command
ssh -i keys/ssh/dev root@<server_ip> "docker ps"
```

### Ansible

Ansible automatically uses the correct key (via dynamic inventory and OpenTofu):

```bash
ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit dev
```

### SSH Config

Add to `~/.ssh/config` for convenience:

```
Host dev.vrije.cloud
    User root
    IdentityFile ~/path/to/infrastructure/keys/ssh/dev
```

Then: `ssh dev.vrije.cloud`

## Key Rotation

Rotate keys annually or on security events:

```bash
# Generate new key (backs up old automatically)
./scripts/generate-client-keys.sh dev

# Apply to server (recreates server with new key)
cd tofu && tofu apply

# Test new key
ssh -i keys/ssh/dev root@<new_ip> hostname
```

## Verification

### Check Key Fingerprint

```bash
# Show fingerprint of private key
ssh-keygen -lf keys/ssh/dev

# Show fingerprint of public key
ssh-keygen -lf keys/ssh/dev.pub

# Should match!
```

### Check What's in Git

```bash
# Verify no private keys committed
git ls-files keys/ssh/

# Should only show:
# keys/ssh/.gitignore
# keys/ssh/README.md
# keys/ssh/*.pub
```

### Check Permissions

```bash
# Private keys must be 600
ls -la keys/ssh/dev

# Should show: -rw------- (600)

# Fix if needed:
chmod 600 keys/ssh/*
chmod 644 keys/ssh/*.pub
```

## Troubleshooting

### "Permission denied (publickey)"

1. Check you're using the correct private key for the client
2. Verify public key is on server (check OpenTofu state)
3. Ensure private key has correct permissions (600)

### "No such file or directory"

Generate the key first:
```bash
./scripts/generate-client-keys.sh <client_name>
```

### "Bad permissions"

Fix key permissions:
```bash
chmod 600 keys/ssh/<client_name>
chmod 644 keys/ssh/<client_name>.pub
```

## See Also

- [../docs/ssh-key-management.md](../../docs/ssh-key-management.md) - Complete SSH key management guide
- [../../scripts/generate-client-keys.sh](../../scripts/generate-client-keys.sh) - Key generation script
- [../../tofu/main.tf](../../tofu/main.tf) - OpenTofu SSH key resources
