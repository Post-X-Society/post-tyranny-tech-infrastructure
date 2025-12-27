# OpenTofu Configuration for Hetzner Cloud

This directory contains Infrastructure as Code using OpenTofu to provision VPS instances on Hetzner Cloud.

## Quick Start

### 1. Prerequisites

- OpenTofu installed (`brew install opentofu`)
- Hetzner Cloud account
- Domain registered and added to Hetzner DNS

### 2. Get Hetzner API Tokens

#### Cloud API Token:
1. Go to https://console.hetzner.cloud/
2. Select your project (or create one)
3. Navigate to **Security** → **API tokens**
4. Click **Generate API token**
5. Name: `infrastructure-provisioning`
6. Permissions: **Read & Write**
7. Copy the token (shown only once!)

#### DNS API Token:
1. Go to https://dns.hetzner.com/
2. Click on your account name → **API Tokens**
3. Click **Create access token**
4. Name: `infrastructure-dns`
5. Copy the token

> **Note**: You can use the same token for both if it has the necessary permissions.

### 3. Add Your Domain to Hetzner DNS

1. Go to https://dns.hetzner.com/
2. Click **Add new zone**
3. Enter your domain (e.g., `platform.nl`)
4. Update your domain registrar's nameservers to:
   - `hydrogen.ns.hetzner.com`
   - `oxygen.ns.hetzner.com`
   - `helium.ns.hetzner.de`

### 4. Configure OpenTofu

Create `terraform.tfvars` from the example:

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
hcloud_token     = "YOUR_ACTUAL_HETZNER_CLOUD_TOKEN"
hetznerdns_token = "YOUR_ACTUAL_HETZNER_DNS_TOKEN"

# Your SSH public key (e.g., from ~/.ssh/id_ed25519.pub)
ssh_public_key = "ssh-ed25519 AAAA... user@hostname"

# Your domain registered in Hetzner DNS
base_domain = "your-domain.com"

# Start with one test client
clients = {
  test = {
    server_type = "cx22"        # 2 vCPU, 4 GB RAM - €6.25/month
    location    = "fsn1"        # Falkenstein, Germany
    subdomain   = "test"        # Will create test.your-domain.com
    apps        = ["zitadel", "nextcloud"]
  }
}

enable_snapshots = true
```

### 5. Initialize OpenTofu

```bash
tofu init
```

This downloads the Hetzner provider plugins.

### 6. Plan Infrastructure

```bash
tofu plan
```

Review what will be created:
- SSH key resource
- Firewall rules
- VPS server(s)
- DNS records (A, AAAA, wildcard)

### 7. Apply Configuration

```bash
tofu apply
```

Type `yes` when prompted. This will:
- Upload your SSH key to Hetzner
- Create firewall rules
- Provision VPS instance(s)
- Create DNS records

### 8. View Outputs

```bash
tofu output
```

Shows:
- Client IP addresses
- FQDNs
- Complete client information

## Server Sizes

| Type | vCPU | RAM | Disk | Price/month | Use Case |
|------|------|-----|------|-------------|----------|
| cx22 | 2 | 4 GB | 40 GB | €6.25 | Small clients (1-10 users) |
| cx32 | 4 | 8 GB | 80 GB | €12.50 | Medium clients (10-50 users) |
| cx42 | 8 | 16 GB | 160 GB | €24.90 | Large clients (50+ users) |

## Locations

- `fsn1` - Falkenstein, Germany
- `nbg1` - Nuremberg, Germany
- `hel1` - Helsinki, Finland

## Important Files

- `terraform.tfvars` - **GITIGNORED** - Your secrets and configuration
- `versions.tf` - Provider versions
- `variables.tf` - Input variable definitions
- `main.tf` - Server and firewall resources
- `dns.tf` - DNS record management
- `outputs.tf` - Output values for Ansible

## Adding a New Client

Edit `terraform.tfvars` and add to the `clients` map:

```hcl
clients = {
  existing-client = { ... }

  new-client = {
    server_type = "cx22"
    location    = "fsn1"
    subdomain   = "newclient"
    apps        = ["zitadel", "nextcloud"]
  }
}
```

Then run:
```bash
tofu plan   # Review changes
tofu apply  # Provision new server
```

## Removing a Client

Remove the client from `terraform.tfvars`, then:

```bash
tofu plan   # Verify what will be destroyed
tofu apply  # Remove server and DNS records
```

**Warning**: This permanently deletes the server. Ensure backups are taken first!

## State Management

OpenTofu state is stored locally in `terraform.tfstate` (gitignored).

For production with multiple team members, consider:
- Remote state backend (S3, Terraform Cloud, etc.)
- State locking
- Encrypted state storage

## Troubleshooting

### "Zone not found" error
- Ensure your domain is added to Hetzner DNS
- Wait for DNS propagation (can take 24-48 hours)
- Verify zone name matches exactly (no trailing dot)

### SSH key errors
- Ensure `ssh_public_key` is the **public** key content
- Format: `ssh-ed25519 AAAA... comment` or `ssh-rsa AAAA... comment`
- No newlines or extra whitespace

### API token errors
- Ensure Read & Write permissions
- Check token hasn't expired
- Verify correct project selected in Hetzner console

## Next Steps

After provisioning:
1. SSH to server: `ssh root@<server-ip>`
2. Run Ansible configuration: `cd ../ansible && ansible-playbook playbooks/setup.yml`
3. Applications will be deployed via Ansible
