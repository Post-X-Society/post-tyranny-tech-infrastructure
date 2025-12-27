# Age Encryption Keys

⚠️ **CRITICAL**: This directory contains encryption keys that are **NOT committed to Git**.

## Key Files

- `age-key.txt` - Age private key for SOPS encryption (GITIGNORED)

## Backup Checklist

Before proceeding with any infrastructure work, ensure you have:

- [ ] Copied `age-key.txt` to password manager
- [ ] Created offline backup (printed or encrypted USB)
- [ ] Verified backup can decrypt secrets successfully

## Key Recovery

If you lose access to `age-key.txt`:

1. **Check password manager** for backup
2. **Check offline backups** (printed copy, USB drive)
3. **If no backup exists**: Secrets are PERMANENTLY LOST
   - You will need to regenerate all secrets
   - Re-encrypt all `.sops.yaml` files
   - Update all services with new credentials

## Generating a New Key

Only do this if you've lost the original key or need to rotate for security:

```bash
# Generate new Age key
age-keygen -o age-key.txt

# Extract public key
grep "public key:" age-key.txt

# Update .sops.yaml in repository root with new public key

# Re-encrypt all secrets
cd ..
for file in secrets/**/*.sops.yaml; do
  SOPS_AGE_KEY_FILE=keys/age-key.txt sops updatekeys -y "$file"
done
```

## Security Notes

- This directory is in `.gitignore`
- Keys should never be shared via email, Slack, or unencrypted channels
- Always use secure methods for key distribution (password manager, encrypted channels)
