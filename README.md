# Post-X Society Multi-Tenant Infrastructure

Infrastructure as Code for a scalable multi-tenant VPS platform running Zitadel (identity provider) and Nextcloud (file sync/share) on Hetzner Cloud.

## 🏗️ Architecture

- **Provisioning**: OpenTofu (open source Terraform fork)
- **Configuration**: Ansible with dynamic inventory
- **Secrets**: SOPS + Age encryption
- **Hosting**: Hetzner Cloud (EU-based, GDPR-compliant)
- **Identity**: Zitadel (Swiss company, AGPL 3.0)
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

### Initial Setup

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

4. **Provision infrastructure**:
   ```bash
   cd tofu
   tofu init
   tofu plan
   tofu apply
   ```

5. **Deploy applications**:
   ```bash
   cd ../ansible
   ansible-playbook playbooks/setup.yml
   ```

## 🎯 Project Principles

1. **EU/GDPR-first**: European vendors and data residency
2. **Truly open source**: Avoid source-available or restrictive licenses
3. **Client isolation**: Full separation between tenants
4. **Infrastructure as Code**: All changes via version control
5. **Security by default**: Encryption, hardening, least privilege

## 📖 Documentation

- **[PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)** - Essential information and common operations
- [Architecture Decision Record](docs/architecture-decisions.md) - Complete design rationale
- [Agent Definitions](.claude/agents/) - Specialized AI agent instructions

## 🤝 Contributing

This project uses specialized AI agents for development:

- **Architect**: High-level design decisions
- **Infrastructure**: OpenTofu + Ansible implementation
- **Zitadel**: Identity provider configuration
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
- `agent:zitadel` - Identity provider
- `agent:nextcloud` - File sync/share
