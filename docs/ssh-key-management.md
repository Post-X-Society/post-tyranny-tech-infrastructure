# SSH Key Management

Per-client SSH key isolation ensures that compromise of one client server does not grant access to other client servers.

## Architecture

Each client gets a **dedicated SSH key pair**:
- **Private key**: `keys/ssh/<client_name>` (gitignored, never committed)
- **Public key**: `keys/ssh/<client_name>.pub` (committed to repository)

## Security Benefits

| Benefit | Description |
|---------|-------------|
| **Isolation** | Compromising one client ≠ compromising others |
| **Granular Rotation** | Rotate keys per-client without affecting others |
| **Access Control** | Different teams can have access to different client keys |
| **Auditability** | Track which key accessed which server |

## Generating Keys for New Clients

### Automated (Recommended)

```bash
# Generate key pair for new client
./scripts/generate-client-keys.sh newclient

# Output:
# ✓ SSH key pair generated successfully
# Private key: keys/ssh/newclient
# Public key:  keys/ssh/newclient.pub
```

### Manual

```bash
# Create keys directory
mkdir -p keys/ssh

# Generate ED25519 key pair
ssh-keygen -t ed25519 \
  -f keys/ssh/newclient \
  -C "client-newclient-deploy-key" \
  -N ""

# Verify generation
ls -la keys/ssh/newclient*
```

## Using Client SSH Keys

### With SSH Command

```bash
# Connect to client server
ssh -i keys/ssh/dev root@78.47.191.38

# Run command on client server
ssh -i keys/ssh/dev root@78.47.191.38 "docker ps"
```

### With Ansible

Ansible automatically uses the correct key per client:

```bash
# Deploy to specific client (uses client-specific key)
ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit dev
```

The dynamic inventory provides the correct host, and OpenTofu ensures the server has the matching public key.

### Adding to SSH Config

```bash
# ~/.ssh/config
Host dev.vrije.cloud
    User root
    IdentityFile ~/path/to/infrastructure/keys/ssh/dev
    StrictHostKeyChecking no

Host newclient.vrije.cloud
    User root
    IdentityFile ~/path/to/infrastructure/keys/ssh/newclient
    StrictHostKeyChecking no
```

Then simply: `ssh dev.vrije.cloud`

## Key Rotation

### When to Rotate

- **Annually**: Routine rotation (best practice)
- **On Compromise**: Immediately if key suspected compromised
- **On Departure**: When team member with key access leaves
- **On Audit**: During security audits

### Rotation Procedure

1. **Generate new key**:
   ```bash
   # Backup old key
   cp keys/ssh/dev keys/ssh/dev.old
   cp keys/ssh/dev.pub keys/ssh/dev.pub.old

   # Generate new key (overwrites old)
   ./scripts/generate-client-keys.sh dev
   ```

2. **Update OpenTofu** (will recreate server):
   ```bash
   cd tofu
   tofu apply
   # Server will be recreated with new key
   ```

3. **Test new key**:
   ```bash
   ssh -i keys/ssh/dev root@<new_ip> hostname
   ```

4. **Remove old key backup**:
   ```bash
   rm keys/ssh/dev.old keys/ssh/dev.pub.old
   ```

### Zero-Downtime Rotation (Advanced)

For production clients where downtime is unacceptable:

1. Generate new key with temporary name
2. Add both keys to server via OpenTofu
3. Test new key works
4. Remove old key from OpenTofu
5. Update local key file

## Key Storage & Backup

### Local Storage

```
keys/ssh/
├── .gitignore          # Protects private keys from git
├── dev                 # Private key (gitignored)
├── dev.pub             # Public key (committed)
├── client1             # Private key (gitignored)
├── client1.pub         # Public key (committed)
└── README.md           # Documentation (to be created)
```

### Backup Strategy

**Private keys must be backed up securely:**

1. **Password Manager** (Recommended):
   - Store in 1Password, Bitwarden, or similar
   - Tag with "ssh-key" and client name
   - Include server IP and hostname

2. **Encrypted Backup**:
   ```bash
   # Create encrypted archive
   tar czf - keys/ssh/ | gpg -c > ssh-keys-backup.tar.gz.gpg

   # Store backup in secure location (NOT in git)
   ```

3. **Team Shared Vault**:
   - Use team password manager
   - Ensure key escrow for bus factor
   - Document who has access

**⚠️ NEVER commit private keys to git!**

The `.gitignore` file protects you, but double-check:
```bash
# Verify no private keys in git
git ls-files keys/ssh/

# Should only show:
# keys/ssh/.gitignore
# keys/ssh/README.md
# keys/ssh/*.pub (public keys only)
```

## Troubleshooting

### "Permission denied (publickey)"

**Cause**: Server doesn't have the public key or wrong private key used.

**Solution**:
```bash
# 1. Verify public key is in OpenTofu state
cd tofu
tofu state show 'hcloud_ssh_key.client["dev"]'

# 2. Verify server has the key
ssh-keygen -lf keys/ssh/dev.pub  # Get fingerprint
# Compare with Hetzner Cloud Console → Server → SSH Keys

# 3. Use correct private key
ssh -i keys/ssh/dev root@<server_ip>
```

### "No such file or directory: keys/ssh/dev"

**Cause**: SSH key not generated yet.

**Solution**:
```bash
./scripts/generate-client-keys.sh dev
```

### "Connection refused"

**Cause**: Server not yet booted or firewall blocking SSH.

**Solution**:
```bash
# Wait for server to boot (check Hetzner Console)
# Check firewall rules allow your IP
cd tofu
tofu state show 'hcloud_firewall.client_firewall'
```

### Key Permissions Wrong

**Cause**: Private key has incorrect permissions.

**Solution**:
```bash
# Private keys must be 600
chmod 600 keys/ssh/dev

# Public keys should be 644
chmod 644 keys/ssh/dev.pub
```

## Migration from Shared Key

If migrating from a shared SSH key setup:

1. **Generate per-client keys**:
   ```bash
   for client in dev client1 client2; do
       ./scripts/generate-client-keys.sh $client
   done
   ```

2. **Update OpenTofu**:
   - Remove `hcloud_ssh_key.default` resource
   - Update `hcloud_server.client` to use `hcloud_ssh_key.client[each.key].id`

3. **Apply changes** (will recreate servers):
   ```bash
   cd tofu
   tofu apply
   ```

4. **Update Ansible/scripts** to use new keys

5. **Remove old shared key** from Hetzner Cloud Console

## Best Practices

✅ **DO**:
- Generate unique keys per client
- Use ED25519 algorithm (modern, secure, fast)
- Backup private keys securely
- Rotate keys annually
- Document key ownership
- Use descriptive comments in keys

❌ **DON'T**:
- Reuse keys between clients
- Share private keys via email/Slack
- Commit private keys to git
- Use weak SSH algorithms (RSA < 4096, DSA)
- Store keys in unencrypted cloud storage
- Forget to backup keys

## Key Specifications

| Property | Value | Rationale |
|----------|-------|-----------|
| Algorithm | ED25519 | Modern, secure, fast, small keys |
| Key Size | 256 bits | Standard for ED25519 |
| Comment | `client-<name>-deploy-key` | Identifies key purpose |
| Passphrase | None (empty) | Automation requires no passphrase |
| Permissions | 600 (private), 644 (public) | Standard SSH security |

**Note on Passphrases**: Automation keys typically have no passphrase. If adding a passphrase, use `ssh-agent` to avoid prompts during deployment.

## See Also

- [OpenTofu Configuration](../tofu/main.tf) - SSH key resources
- [Deployment Scripts](../scripts/deploy-client.sh) - Uses client keys
- [Issue #14](https://github.com/Post-X-Society/post-tyranny-tech-infrastructure/issues/14) - Original requirement
- [Architecture Decisions](./architecture-decisions.md) - Security baseline
