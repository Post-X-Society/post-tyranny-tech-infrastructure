# Post-X Society Multi-Tenant Infrastructure

Infrastructure as Code for a scalable multi-tenant VPS platform running Nextcloud (file sync/share) on Hetzner Cloud.

## 🏗️ Architecture

- **Provisioning**: OpenTofu (open source Terraform fork)
- **Configuration**: Ansible with dynamic inventory
- **Secrets**: SOPS + Age encryption
- **Hosting**: Hetzner Cloud (EU-based, GDPR-compliant)
- **Identity**: Authentik (OAuth2/OIDC SSO, MIT license)
- **Storage**: Nextcloud (German company, AGPL 3.0)

## 📁 Repository Structure

```
infrastructure/
├── .claude/agents/          # AI agent definitions for specialized tasks
├── docs/                    # Architecture decisions and runbooks
├── tofu/                    # OpenTofu configurations for Hetzner
├── ansible/                 # Ansible playbooks and roles
├── secrets/                 # SOPS-encrypted secrets (git-safe)
├── docker/                  # Docker Compose configurations
└── scripts/                 # Deployment and management scripts
```

## 🚀 Quick Start

### Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.6
- [Ansible](https://docs.ansible.com/) >= 2.15
- [SOPS](https://github.com/getsops/sops) + [Age](https://github.com/FiloSottile/age)
- [Hetzner Cloud account](https://www.hetzner.com/cloud)

### Automated Deployment (Recommended)

**The fastest way to deploy a client:**

```bash
# 1. Set environment variables
export HCLOUD_TOKEN="your-hetzner-api-token"
export SOPS_AGE_KEY_FILE="./keys/age-key.txt"

# 2. Deploy client (fully automated, ~10-15 minutes)
./scripts/deploy-client.sh <client_name>
```

This automatically:
- ✅ Provisions VPS on Hetzner Cloud
- ✅ Deploys Authentik (SSO/identity provider)
- ✅ Deploys Nextcloud (file storage)
- ✅ Configures OAuth2/OIDC integration
- ✅ Sets up SSL certificates
- ✅ Creates admin accounts

**Result**: Fully functional system, ready to use immediately!

### Management Scripts

```bash
# Deploy a fresh client
./scripts/deploy-client.sh <client_name>

# Rebuild existing client (destroy + redeploy)
./scripts/rebuild-client.sh <client_name>

# Destroy client infrastructure
./scripts/destroy-client.sh <client_name>
```

See [scripts/README.md](scripts/README.md) for detailed documentation.

### Manual Setup (Advanced)

<details>
<summary>Click to expand manual setup instructions</summary>

1. **Clone repository**:
   ```bash
   git clone <repo-url>
   cd infrastructure
   ```

2. **Generate Age encryption key**:
   ```bash
   age-keygen -o keys/age-key.txt
   # Store securely in password manager!
   ```

3. **Configure OpenTofu variables**:
   ```bash
   cp tofu/terraform.tfvars.example tofu/terraform.tfvars
   # Edit with your Hetzner API token and configuration
   ```

4. **Create client secrets**:
   ```bash
   cp secrets/clients/test.sops.yaml secrets/clients/<client>.sops.yaml
   sops secrets/clients/<client>.sops.yaml
   # Update client_name, domains, regenerate all passwords
   ```

5. **Provision infrastructure**:
   ```bash
   cd tofu
   tofu init
   tofu apply
   ```

6. **Deploy applications**:
   ```bash
   cd ../ansible
   export HCLOUD_TOKEN="your-token"
   export SOPS_AGE_KEY_FILE="../keys/age-key.txt"

   ansible-playbook -i hcloud.yml playbooks/setup.yml --limit <client>
   ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit <client>
   ```

</details>

## 🎯 Project Principles

1. **EU/GDPR-first**: European vendors and data residency
2. **Truly open source**: Avoid source-available or restrictive licenses
3. **Client isolation**: Full separation between tenants
4. **Infrastructure as Code**: All changes via version control
5. **Security by default**: Encryption, hardening, least privilege

## 📖 Documentation

- **[PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)** - Essential information and common operations
- **[scripts/README.md](scripts/README.md)** - Management scripts documentation
- **[AUTOMATION_STATUS.md](docs/AUTOMATION_STATUS.md)** - Full automation details
- [Architecture Decision Record](docs/architecture-decisions.md) - Complete design rationale
- [SSO Automation](docs/sso-automation.md) - OAuth2/OIDC integration workflow
- [Agent Definitions](.claude/agents/) - Specialized AI agent instructions

## 🤝 Contributing

This project uses specialized AI agents for development:

- **Architect**: High-level design decisions
- **Infrastructure**: OpenTofu + Ansible implementation
- **Authentik**: Identity provider and SSO configuration
- **Nextcloud**: File sync/share configuration

See individual agent files in `.claude/agents/` for responsibilities.

## 🔒 Security

- Secrets are encrypted with SOPS + Age before committing
- Age private keys are **NEVER** stored in this repository
- See `.gitignore` for protected files

## 📝 License

TBD

## 🙋 Support

For issues or questions, please create a GitHub issue with the appropriate label:
- `agent:architect` - Architecture/design questions
- `agent:infrastructure` - IaC implementation
- `agent:authentik` - Identity provider/SSO
- `agent:nextcloud` - File sync/share
