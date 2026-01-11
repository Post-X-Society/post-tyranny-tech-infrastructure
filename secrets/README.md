# Secrets Management with SOPS + Age

This directory contains encrypted secrets for the infrastructure using [SOPS](https://github.com/getsops/sops) with [Age](https://github.com/FiloSottile/age) encryption.

## 🔐 Security Model

- **Encryption**: All secret files encrypted with Age before committing to Git
- **Key Storage**: Age private key stored OUTSIDE this repository
- **Git-Safe**: Only encrypted files (.sops.yaml) are committed
- **Decryption**: Happens at runtime by Ansible or manually with `sops`

## 📁 Directory Structure

```
secrets/
├── README.md              # This file
├── shared.sops.yaml       # Shared secrets (encrypted)
└── clients/
    └── *.sops.yaml        # Per-client secrets (encrypted)
```

## 🔑 Age Key Location

**IMPORTANT**: The Age private key is stored at:
```
keys/age-key.txt
```

This file is **gitignored** and must **NEVER** be committed.

### Key Backup Checklist

✅ **You MUST backup the Age key securely:**

1. **Password Manager**: Store in Bitwarden/1Password/etc
   ```bash
   # Copy key content
   cat keys/age-key.txt
   # Store as secure note in password manager
   ```

2. **Print Backup** (optional but recommended):
   ```bash
   # Print and store in secure physical location
   cat keys/age-key.txt | lpr
   ```

3. **Encrypted USB Drive** (optional):
   ```bash
   # Copy to encrypted USB for offline backup
   cp keys/age-key.txt /Volumes/SecureUSB/infrastructure-age-key.txt
   ```

⚠️ **WARNING**: If you lose this key, encrypted secrets are PERMANENTLY UNRECOVERABLE!

## 🚀 Quick Start

### Prerequisites

```bash
# Install SOPS and Age
brew install sops age

# Ensure you have the Age key
ls -la keys/age-key.txt
```

### View Encrypted Secrets

```bash
# View shared secrets
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/shared.sops.yaml

# View client secrets
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/clients/test.sops.yaml
```

### Edit Encrypted Secrets

```bash
# Edit shared secrets (decrypts, opens $EDITOR, re-encrypts on save)
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/shared.sops.yaml

# Edit client secrets
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/clients/test.sops.yaml
```

### Create New Client Secrets

```bash
# Copy template
cp secrets/clients/test.sops.yaml secrets/clients/newclient.sops.yaml

# Edit with generated passwords
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/clients/newclient.sops.yaml
```

### Generate Secure Passwords

```bash
# Random 32-character password
openssl rand -base64 32

# Random 24-character password
openssl rand -base64 24

# Zitadel masterkey (32-byte hex)
openssl rand -hex 32
```

## 🔧 Usage with Ansible

Ansible automatically decrypts SOPS files using the `community.sops` collection.

**In playbooks:**
```yaml
- name: Load client secrets
  community.sops.load_vars:
    file: "{{ playbook_dir }}/../secrets/clients/{{ client_name }}.sops.yaml"
    name: client_secrets

- name: Use decrypted secret
  debug:
    msg: "DB Password: {{ client_secrets.zitadel_db_password }}"
```

**Environment variable required:**
```bash
export SOPS_AGE_KEY_FILE=/path/to/infrastructure/keys/age-key.txt
```

## 📝 Secret File Structure

### shared.sops.yaml

Contains secrets shared across all infrastructure:
- Hetzner Cloud API token
- Hetzner Storage Box credentials
- ACME email for SSL certificates
- **SMTP/Email configuration** (optional):
  - `smtp_enabled`: true/false
  - `smtp_host`: SMTP server hostname
  - `smtp_port`: SMTP port (usually 587)
  - `smtp_username`: SMTP authentication username
  - `smtp_password`: SMTP authentication password
  - `smtp_use_tls`: Use STARTTLS (true/false)
  - `smtp_use_ssl`: Use implicit SSL (true/false)
  - `email_provider`: Provider name (mailgun, sendgrid, postmark, mailcow)

### clients/*.sops.yaml

Per-client secrets:
- Database passwords (Authentik, Nextcloud)
- Admin passwords
- Authentik secret key and bootstrap credentials
- Redis password
- Collabora admin password
- **Email configuration** (optional):
  - `client_email_address`: Client-specific sending address (e.g., client@vrije.cloud)
  - `authentik_bootstrap_email`: Admin user email for Authentik
  - `nextcloud_mail_from`: Nextcloud mail from prefix (e.g., "nextcloud")

## 🛠️ Common Tasks

### Decrypt to Temporary File

```bash
# Decrypt for one-time use
SOPS_AGE_KEY_FILE=keys/age-key.txt sops --decrypt secrets/shared.sops.yaml > /tmp/secrets.yaml

# Use the file
cat /tmp/secrets.yaml

# IMPORTANT: Delete when done
rm /tmp/secrets.yaml
```

### Encrypt New File

```bash
# Create plaintext file
cat > secrets/newfile.sops.yaml <<EOF
my_secret: "super-secret-value"
EOF

# Encrypt in place
SOPS_AGE_KEY_FILE=keys/age-key.txt sops --encrypt --in-place secrets/newfile.sops.yaml
```

### Re-encrypt with New Key

If you need to rotate the Age key:

```bash
# Generate new key
age-keygen -o keys/age-key-new.txt

# Get public key
grep "public key:" keys/age-key-new.txt

# Update .sops.yaml with new public key

# Re-encrypt all files
for file in secrets/**/*.sops.yaml; do
  SOPS_AGE_KEY_FILE=keys/age-key.txt sops updatekeys -y "$file"
done

# Replace old key
mv keys/age-key.txt keys/age-key-old.txt
mv keys/age-key-new.txt keys/age-key.txt
```

## 🔍 Troubleshooting

### "Failed to get the data key required to decrypt the SOPS file"

- **Cause**: Age private key not found or incorrect
- **Fix**: Ensure `SOPS_AGE_KEY_FILE` points to correct key
  ```bash
  export SOPS_AGE_KEY_FILE=/full/path/to/keys/age-key.txt
  ```

### "no matching creation rules found"

- **Cause**: File path doesn't match `.sops.yaml` regex
- **Fix**: Ensure filename ends with `.sops.yaml`

### "config file not found"

- **Cause**: `.sops.yaml` not in repository root
- **Fix**: Check `.sops.yaml` exists at repo root

## 🔒 Security Best Practices

1. ✅ **Never commit** `keys/age-key.txt`
2. ✅ **Always encrypt** before committing secrets
3. ✅ **Backup the key** in multiple secure locations
4. ✅ **Use strong passwords**: minimum 24 characters
5. ✅ **Rotate secrets** periodically
6. ✅ **Limit key access** to essential personnel only
7. ✅ **Delete temp files** after decryption

## 📚 References

- [SOPS Documentation](https://github.com/getsops/sops)
- [Age Documentation](https://github.com/FiloSottile/age)
- [Ansible SOPS Collection](https://docs.ansible.com/ansible/latest/collections/community/sops/)
