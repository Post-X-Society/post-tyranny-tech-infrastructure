# Security Note: Hetzner API Token Placement

**Date**: 2026-01-17
**Severity**: INFORMATIONAL
**Status**: SAFE (but can be improved)

## Current Situation

The Hetzner Cloud API token is currently stored in:
- `tofu/terraform.tfvars` (gitignored, NOT committed)

## Assessment

✅ **Current Setup is SAFE**:
- `tofu/terraform.tfvars` is properly gitignored (line 15 in `.gitignore`: `tofu/*.tfvars`)
- Token has NOT been committed to git history
- File is local-only

⚠️ **However, Best Practice Would Be**:
- Store token in `secrets/shared.sops.yaml` (encrypted with SOPS)
- Reference it from terraform.tfvars as a variable
- Keep terraform.tfvars minimal (only client configs)

## Recommended Improvement (Optional)

### Option 1: Keep Current Approach (Acceptable)
**Pros**:
- Simple
- Works with OpenTofu's native variable system
- Already gitignored
- Easy to use

**Cons**:
- Token stored in plaintext on disk
- Not encrypted at rest
- Can't be safely backed up to cloud storage

### Option 2: Move to SOPS (More Secure)
**Pros**:
- Token encrypted at rest
- Can be safely backed up
- Consistent with other secrets
- Better security posture

**Cons**:
- Slightly more complex workflow
- Need to decrypt before running tofu

#### Implementation (if desired):

1. Add token to shared.sops.yaml:
```bash
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/shared.sops.yaml
# Add: hcloud_token: <your-token>
```

2. Update terraform.tfvars to be minimal:
```hcl
# No sensitive data here
# Token loaded from environment variable

clients = {
  # ... client configs only ...
}
```

3. Update deployment scripts to load token:
```bash
# Before running tofu:
export TF_VAR_hcloud_token=$(sops -d secrets/shared.sops.yaml | yq .hcloud_token)
tofu apply
```

## Recommendation

**For current usage**: ✅ No action required - current setup is safe

**For enhanced security** (optional): Consider moving to Option 2 when time permits

## Verification

Confirmed `terraform.tfvars` is NOT in git:
```bash
$ git ls-files | grep terraform.tfvars
tofu/terraform.tfvars.example  # Only the example is tracked ✓
```

Confirmed `.gitignore` is properly configured:
```
tofu/*.tfvars                   # Ignores all tfvars ✓
!tofu/terraform.tfvars.example  # Except the example ✓
```

## Related

- [secrets/README.md](secrets/README.md) - SOPS secrets management
- [.gitignore](.gitignore) - Git ignore rules
- OpenTofu variables: [tofu/variables.tf](tofu/variables.tf)
