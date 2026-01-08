# SSO Automation Workflow

Complete guide to the automated Authentik + Nextcloud SSO integration.

## Overview

This infrastructure implements **automated OAuth2/OIDC integration** between Authentik (identity provider) and Nextcloud (application). The goal is to achieve **zero manual configuration** for SSO when deploying a new client.

## Architecture

```
┌─────────────┐                    ┌─────────────┐
│  Authentik  │◄──────OIDC────────►│  Nextcloud  │
│  (IdP)      │   OAuth2/OIDC      │   (App)     │
└─────────────┘   Discovery URI    └─────────────┘
      │                                    │
      │ 1. Create provider via API         │
      │ 2. Get client_id/secret            │
      │                                    │
      └───────────► credentials ──────────►│
                    (temporary file)       │ 3. Configure OIDC app
```

## Automation Workflow

### Phase 1: Deployment (Ansible)

1. **Deploy Authentik** (`roles/authentik/tasks/docker.yml`)
   - Start PostgreSQL database
   - Start Authentik server + worker containers
   - Wait for health check (HTTP 200/302 on root)

2. **Check for API Token** (`roles/authentik/tasks/providers.yml`)
   - Look for `client_secrets.authentik_api_token` in secrets file
   - If missing: Display manual setup instructions and skip automation
   - If present: Proceed to Phase 2

### Phase 2: OIDC Provider Creation (API)

**Script**: `roles/authentik/files/authentik_api.py`

1. **Wait for Authentik Ready**
   - Poll root endpoint until 200/302 response
   - Timeout: 300 seconds (configurable)

2. **Get Authorization Flow UUID**
   - `GET /api/v3/flows/instances/`
   - Find flow with `slug=default-authorization-flow` or `designation=authorization`

3. **Get Signing Key UUID**
   - `GET /api/v3/crypto/certificatekeypairs/`
   - Use first available certificate

4. **Create OAuth2 Provider**
   - `POST /api/v3/providers/oauth2/`
   ```json
   {
     "name": "Nextcloud",
     "authorization_flow": "<flow_uuid>",
     "client_type": "confidential",
     "redirect_uris": "https://nextcloud.example.com/apps/user_oidc/code",
     "signing_key": "<key_uuid>",
     "sub_mode": "hashed_user_id",
     "include_claims_in_id_token": true
   }
   ```

5. **Create Application**
   - `POST /api/v3/core/applications/`
   ```json
   {
     "name": "Nextcloud",
     "slug": "nextcloud",
     "provider": "<provider_id>",
     "meta_launch_url": "https://nextcloud.example.com"
   }
   ```

6. **Return Credentials**
   ```json
   {
     "success": true,
     "client_id": "...",
     "client_secret": "...",
     "discovery_uri": "https://auth.example.com/application/o/nextcloud/.well-known/openid-configuration",
     "issuer": "https://auth.example.com/application/o/nextcloud/"
   }
   ```

### Phase 3: Nextcloud Configuration

**Task**: `roles/nextcloud/tasks/oidc.yml`

1. **Install user_oidc App**
   ```bash
   docker exec -u www-data nextcloud php occ app:install user_oidc
   docker exec -u www-data nextcloud php occ app:enable user_oidc
   ```

2. **Load Credentials from Temp File**
   - Read `/tmp/authentik_oidc_credentials.json` (created by Phase 2)
   - Parse JSON to Ansible fact

3. **Configure OIDC Provider**
   ```bash
   docker exec -u www-data nextcloud php occ user_oidc:provider:add \
     --clientid="<client_id>" \
     --clientsecret="<client_secret>" \
     --discoveryuri="<discovery_uri>" \
     "Authentik"
   ```

4. **Cleanup**
   - Remove temporary credentials file

### Result

- ✅ "Login with Authentik" button appears on Nextcloud login page
- ✅ Users can log in with Authentik credentials
- ✅ Zero manual configuration required (if API token is present)

## Manual Bootstrap (One-Time Setup)

If `authentik_api_token` is not in secrets, follow these steps **once per Authentik instance**:

### Step 1: Complete Initial Setup

1. Visit: `https://auth.example.com/if/flow/initial-setup/`
2. Create admin account:
   - **Username**: `akadmin` (recommended)
   - **Password**: Secure random password
   - **Email**: Your admin email

### Step 2: Create API Token

1. Login to Authentik admin UI
2. Navigate: **Admin Interface → Tokens & App passwords**
3. Click **Create → Tokens**
4. Configure token:
   - **User**: Your admin user (akadmin)
   - **Intent**: API Token
   - **Description**: Ansible automation
   - **Expires**: Never (or far future date)
5. Copy the generated token

### Step 3: Add to Secrets

Edit your client secrets file:

```bash
cd infrastructure
export SOPS_AGE_KEY_FILE="keys/age-key.txt"
sops secrets/clients/test.sops.yaml
```

Add line:
```yaml
authentik_api_token: ak_<your_token_here>
```

### Step 4: Re-run Deployment

```bash
cd infrastructure/ansible
export HCLOUD_TOKEN="..."
export SOPS_AGE_KEY_FILE="../keys/age-key.txt"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml \
  --tags authentik,oidc \
  --limit test
```

## API Token Security

### Best Practices

1. **Scope**: Token has full API access - treat as root password
2. **Storage**: Always encrypted with SOPS in secrets files
3. **Rotation**: Rotate tokens periodically (update secrets file)
4. **Audit**: Monitor token usage in Authentik logs

### Alternative: Service Account

For production, consider creating a dedicated service account:

1. Create user: `ansible-automation`
2. Assign minimal permissions (provider creation only)
3. Create token for this user
4. Use in automation

## Troubleshooting

### OIDC Provider Creation Fails

**Symptom**: Script returns error creating provider

**Check**:
```bash
# Test API connectivity
curl -H "Authorization: Bearer $TOKEN" \
     https://auth.example.com/api/v3/flows/instances/

# Check Authentik logs
docker logs authentik-server
docker logs authentik-worker
```

**Common Issues**:
- Token expired or invalid
- Authorization flow not found (check flows in admin UI)
- Certificate/key missing

### "Login with Authentik" Button Missing

**Symptom**: Nextcloud shows only username/password login

**Check**:
```bash
# List configured providers
docker exec -u www-data nextcloud php occ user_oidc:provider

# Check user_oidc app status
docker exec -u www-data nextcloud php occ app:list | grep user_oidc
```

**Fix**:
```bash
# Re-configure OIDC
cd infrastructure/ansible
~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml \
  --tags oidc \
  --limit test
```

### API Token Not Working

**Symptom**: "Authentication failed" from API script

**Check**:
1. Token format: Should start with `ak_`
2. User still exists in Authentik
3. Token not expired (check in admin UI)

**Fix**: Create new token and update secrets file

## Testing SSO Flow

### End-to-End Test

1. **Open Nextcloud**: `https://nextcloud.example.com`
2. **Click "Login with Authentik"**
3. **Redirected to Authentik**: `https://auth.example.com`
4. **Enter Authentik credentials** (created in Authentik admin UI)
5. **Redirected back to Nextcloud** (logged in)

### Create Test User in Authentik

```bash
# Access Authentik admin UI
https://auth.example.com

# Navigate: Directory → Users → Create
# Fill in:
# - Username: testuser
# - Email: test@example.com
# - Password: <secure_password>
```

### Test Login

1. Logout of Nextcloud (if logged in as admin)
2. Go to Nextcloud login page
3. Click "Login with Authentik"
4. Login with `testuser` credentials
5. First login: Nextcloud creates local account linked to Authentik
6. Subsequent logins: Automatic via SSO

## Future Improvements

### Fully Automated Bootstrap

**Goal**: Automate the initial admin account creation via API

**Approach**:
- Research Authentik bootstrap tokens
- Automate initial setup flow via HTTP POST requests
- Generate admin credentials automatically
- Store in secrets file

**Status**: Not yet implemented (initial setup still manual)

### SAML Support

Add SAML provider alongside OIDC for applications that don't support OAuth2/OIDC.

### Multi-Application Support

Extend automation to create OIDC providers for other applications:
- Collabora Online
- OnlyOffice
- Custom web applications

## Related Files

- **API Script**: `ansible/roles/authentik/files/authentik_api.py`
- **Provider Tasks**: `ansible/roles/authentik/tasks/providers.yml`
- **OIDC Config**: `ansible/roles/nextcloud/tasks/oidc.yml`
- **Main Playbook**: `ansible/playbooks/deploy.yml`
- **Secrets Template**: `secrets/clients/test.sops.yaml`
- **Agent Config**: `.claude/agents/authentik.md`

## References

- **Authentik API Docs**: https://docs.goauthentik.io/developer-docs/api
- **OAuth2 Provider**: https://docs.goauthentik.io/docs/providers/oauth2
- **Nextcloud OIDC**: https://github.com/nextcloud/user_oidc
- **OpenID Connect**: https://openid.net/specs/openid-connect-core-1_0.html
