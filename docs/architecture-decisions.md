# Infrastructure Architecture Decision Record

## Post-X Society Multi-Tenant VPS Platform

**Document Status:** Living document
**Created:** December 2024
**Last Updated:** December 2025

---

## Executive Summary

This document captures architectural decisions for a scalable, multi-tenant infrastructure platform starting with 10 identical VPS instances running Keycloak and Nextcloud, with plans to expand both server count and application offerings.

**Key Technology Choices:**
- **OpenTofu** over Terraform (truly open source, MPL 2.0)
- **SOPS + Age** over HashiCorp Vault (simple, no server, European-friendly)
- **Hetzner** for all infrastructure (GDPR-compliant, EU-based)

---

## 1. Infrastructure Provisioning

### Decision: OpenTofu + Ansible with Dynamic Inventory

**Choice:** Infrastructure as Code using OpenTofu for resource provisioning and Ansible for configuration management.

**Why OpenTofu over Terraform:**
- Truly open source (MPL 2.0) vs HashiCorp's BSL 1.1
- Drop-in replacement - same syntax, same providers
- Linux Foundation governance - no single company can close the license
- Active community after HashiCorp's 2023 license change
- No risk of future license restrictions

**Approach:**
- **OpenTofu** manages Hetzner resources (VPS instances, networks, firewalls, DNS)
- **Ansible** configures servers using the `hcloud` dynamic inventory plugin
- No static inventory files - Ansible queries Hetzner API at runtime

**Rationale:**
- 10+ identical servers makes manual management unsustainable
- Version-controlled infrastructure in Git
- Dynamic inventory eliminates sync issues between OpenTofu and Ansible
- Skills transfer to other providers if needed

**Implementation:**
```yaml
# ansible.cfg
[inventory]
enable_plugins = hetzner.hcloud.hcloud

# hcloud.yml (inventory config)
plugin: hetzner.hcloud.hcloud
locations:
  - fsn1
keyed_groups:
  - key: labels.role
    prefix: role
  - key: labels.client
    prefix: client
```

---

## 2. Application Deployment

### Decision: Modular Ansible Roles with Feature Flags

**Choice:** Each application is a separate Ansible role, enabled per-server via inventory variables.

**Rationale:**
- Allows heterogeneous deployments (client A wants Pretix, client B doesn't)
- Test new applications on single server before fleet rollout
- Clear separation of concerns
- Minimal refactoring when adding new applications

**Structure:**
```
ansible/
├── roles/
│   ├── common/          # Base setup, hardening, Docker
│   ├── traefik/         # Reverse proxy, SSL
│   ├── nextcloud/       # File sync and collaboration
│   ├── pretix/          # Future: Event ticketing
│   ├── listmonk/        # Future: Newsletter/mailing
│   ├── backup/          # Restic configuration
│   └── monitoring/      # Node exporter, promtail
```

**Inventory Example:**
```yaml
all:
  children:
    clients:
      hosts:
        client-alpha:
          client_name: alpha
          domain: alpha.platform.nl
          apps:
            - nextcloud
        client-beta:
          client_name: beta
          domain: beta.platform.nl
          apps:
            - nextcloud
            - pretix
```

---

## 3. DNS Management

### Decision: Hetzner DNS via OpenTofu

**Choice:** Manage all DNS records through Hetzner DNS using OpenTofu.

**Rationale:**
- Single provider for infrastructure and DNS simplifies management
- OpenTofu provider available and well-maintained (same as Terraform provider)
- Cost-effective (included with Hetzner)
- GDPR-compliant (EU-based)

**Domain Strategy:**
- Start with subdomains: `{client}.platform.nl`
- Support custom domains later via variable override
- Wildcard approach not used - explicit records per service

**Implementation:**
```hcl
resource "hcloud_server" "client" {
  for_each    = var.clients
  name        = each.key
  server_type = each.value.server_type
  # ...
}

resource "hetznerdns_record" "client_a" {
  for_each = var.clients
  zone_id  = data.hetznerdns_zone.main.id
  name     = each.value.subdomain
  type     = "A"
  value    = hcloud_server.client[each.key].ipv4_address
}
```

**SSL Certificates:** Handled by Traefik with Let's Encrypt, automatic per-domain.

---

## 4. Identity Provider

### Decision: Removed (previously Zitadel)

**Status:** Identity provider removed from architecture.

**Reason for Removal:**
- Zitadel v2.63.7 has critical bugs with FirstInstance initialization
- ALL `ZITADEL_FIRSTINSTANCE_*` environment variables cause database migration errors
- Requires manual web UI setup for each instance (not scalable for multi-tenant deployment)
- See: https://github.com/zitadel/zitadel/issues/8791

**Future Consideration:**
- May revisit with Authentik or other identity providers when needed
- Currently focusing on Nextcloud as standalone solution

---

## 4. Backup Strategy

### Decision: Dual Backup Approach

**Choice:** Hetzner automated snapshots + Restic application-level backups to Hetzner Storage Box.

#### Layer 1: Hetzner Snapshots

**Purpose:** Disaster recovery (complete server loss)

| Aspect | Configuration |
|--------|---------------|
| Frequency | Daily (Hetzner automated) |
| Retention | 7 snapshots |
| Cost | 20% of VPS price |
| Restoration | Full server restore via Hetzner console/API |

**Limitations:**
- Crash-consistent only (may catch database mid-write)
- Same datacenter (not true off-site)
- Coarse granularity (all or nothing)

#### Layer 2: Restic to Hetzner Storage Box

**Purpose:** Granular application recovery, off-server storage

**Backend Choice:** Hetzner Storage Box

**Rationale:**
- GDPR-compliant (German/EU data residency)
- Same Hetzner network = fast transfers, no egress costs
- Cost-effective (~€3.81/month for BX10 with 1TB)
- Supports SFTP, CIFS/Samba, rsync, Restic-native
- Can be accessed from all VPSs simultaneously

**Storage Hierarchy:**
```
Storage Box (BX10 or larger)
└── /backups/
    ├── /client-alpha/
    │   ├── /restic-repo/      # Encrypted Restic repository
    │   └── /manual/           # Ad-hoc exports if needed
    ├── /client-beta/
    │   └── /restic-repo/
    └── /client-gamma/
        └── /restic-repo/
```

**Connection Method:**
- Primary: SFTP (native Restic support, encrypted in transit)
- Optional: CIFS mount for manual file access
- Each client VPS gets Storage Box sub-account or uses main credentials with path restrictions

| Aspect | Configuration |
|--------|---------------|
| Frequency | Nightly (after DB dumps) |
| Time | 03:00 local time |
| Retention | 7 daily, 4 weekly, 6 monthly |
| Encryption | Restic default (AES-256) |
| Repo passwords | Stored in SOPS-encrypted files |

**What Gets Backed Up:**
```
/opt/docker/
├── nextcloud/
│   └── data/              # ✓ User files
├── pretix/
│   └── data/              # ✓ When applicable
└── configs/               # ✓ docker-compose files, env
```

**Backup Ansible Role Tasks:**
1. Install Restic
2. Initialize repo (if not exists)
3. Configure SFTP connection to Storage Box
4. Create pre-backup script (database dumps)
5. Create backup script
6. Create systemd timer
7. Configure backup monitoring (alert on failure)

**Sizing Guidance:**
- Start with BX10 (1TB) for 10 clients
- Monitor usage monthly
- Scale to BX20 (2TB) when approaching 70% capacity

**Verification:**
- Weekly `restic check` via cron
- Monthly test restore to staging environment
- Alerts on backup job failures

---

## 5. Secrets Management

### Decision: SOPS + Age Encryption

**Choice:** File-based secrets encryption using SOPS with Age encryption, stored in Git.

**Why SOPS + Age over HashiCorp Vault:**
- No additional server to maintain
- Truly open source (MPL 2.0 for SOPS, Apache 2.0 for Age)
- Secrets versioned alongside infrastructure code
- Simple to understand and debug
- Age developed with European privacy values (FiloSottile)
- Perfect for 10-50 server scale
- No vendor lock-in concerns

**How It Works:**
1. Secrets stored in YAML files, encrypted with Age
2. Only the values are encrypted, keys remain readable
3. Decryption happens at Ansible runtime
4. One Age key per environment (or shared across all)

**Example Encrypted File:**
```yaml
# secrets/client-alpha.sops.yaml
db_password: ENC[AES256_GCM,data:kH3x9...,iv:abc...,tag:def...,type:str]
keycloak_admin: ENC[AES256_GCM,data:mN4y2...,iv:ghi...,tag:jkl...,type:str]
nextcloud_admin: ENC[AES256_GCM,data:pQ5z7...,iv:mno...,tag:pqr...,type:str]
restic_repo_password: ENC[AES256_GCM,data:rS6a1...,iv:stu...,tag:vwx...,type:str]
```

**Key Management:**
```
keys/
├── age-key.txt           # Master key (NEVER in Git, backed up securely)
└── .sops.yaml            # SOPS configuration (in Git)
```

**.sops.yaml Configuration:**
```yaml
creation_rules:
  - path_regex: secrets/.*\.sops\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Secret Structure:**
```
secrets/
├── .sops.yaml              # SOPS config
├── shared.sops.yaml        # Shared secrets (Storage Box, API tokens)
└── clients/
    ├── alpha.sops.yaml     # Client-specific secrets
    ├── beta.sops.yaml
    └── gamma.sops.yaml
```

**Ansible Integration:**
```yaml
# Using community.sops collection
- name: Load client secrets
  community.sops.load_vars:
    file: "secrets/clients/{{ client_name }}.sops.yaml"
    name: client_secrets

- name: Use decrypted secret
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: /opt/docker/docker-compose.yml
  vars:
    db_password: "{{ client_secrets.db_password }}"
```

**Daily Operations:**
```bash
# Encrypt a new file
sops --encrypt --age $(cat keys/age-key.pub) secrets/clients/new.yaml > secrets/clients/new.sops.yaml

# Edit existing secrets (decrypts, opens editor, re-encrypts)
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/clients/alpha.sops.yaml

# View decrypted content
SOPS_AGE_KEY_FILE=keys/age-key.txt sops --decrypt secrets/clients/alpha.sops.yaml
```

**Key Backup Strategy:**
- Age private key stored in password manager (Bitwarden/1Password)
- Printed paper backup in secure location
- Key never stored in Git repository
- Consider key escrow for bus factor

**Advantages for Your Setup:**
| Aspect | Benefit |
|--------|---------|
| Simplicity | No Vault server to maintain, secure, update |
| Auditability | Git history shows who changed what secrets when |
| Portability | Works offline, no network dependency |
| Reliability | No secrets server = no secrets server downtime |
| Cost | Zero infrastructure cost |

---

## 6. Monitoring

### Decision: Centralized Uptime Kuma

**Choice:** Uptime Kuma on dedicated monitoring server.

**Rationale:**
- Simple to deploy and maintain
- Beautiful UI for status overview
- Flexible alerting (email, Slack, webhook)
- Self-hosted (data stays in-house)
- Sufficient for "is it up?" monitoring at current scale

**Deployment:**
- Dedicated VPS or container on monitoring server
- Monitors all client servers and services
- Public status page optional per client

**Monitors per Client:**
- HTTPS endpoint (Nextcloud)
- TCP port checks (database, if exposed)
- Docker container health (via API or agent)

**Alerting:**
- Primary: Email
- Secondary: Slack/Mattermost webhook
- Escalation: SMS for extended downtime (future)

**Future Expansion Path:**
When deeper metrics needed:
1. Add Prometheus + Node Exporter
2. Add Grafana dashboards
3. Add Loki for log aggregation
4. Uptime Kuma remains for synthetic monitoring

---

## 7. Client Isolation

### Decision: Full Isolation

**Choice:** Maximum isolation between clients at all levels.

**Implementation:**

| Layer | Isolation Method |
|-------|------------------|
| Compute | Separate VPS per client |
| Network | Hetzner firewall rules, no inter-VPS traffic |
| Database | Separate PostgreSQL container per client |
| Storage | Separate Docker volumes |
| Backups | Separate Restic repositories |
| Secrets | Separate SOPS files per client |
| DNS | Separate records/domains |

**Network Rules:**
- Each VPS accepts traffic only on 80, 443, 22 (management IP only)
- No private network between client VPSs
- Monitoring server can reach all clients (outbound checks)

**Rationale:**
- Security: Compromise of one client cannot spread
- Compliance: Data separation demonstrable
- Operations: Can maintain/upgrade clients independently
- Billing: Clear resource attribution

---

## 8. Deployment Strategy

### Decision: Canary Deployments with Version Pinning

**Choice:** Staged rollouts with explicit version control.

#### Version Pinning

All container images use explicit tags:
```yaml
# docker-compose.yml
services:
  nextcloud:
    image: nextcloud:28.0.1  # Never use :latest
  keycloak:
    image: quay.io/keycloak/keycloak:23.0.1
  postgres:
    image: postgres:16.1
```

Version updates require explicit change and commit.

#### Canary Process

**Inventory Groups:**
```yaml
all:
  children:
    canary:
      hosts:
        client-alpha:  # Designated test client (internal or willing partner)
    production:
      hosts:
        client-beta:
        client-gamma:
        # ... remaining clients
```

**Deployment Script:**
```bash
#!/bin/bash
set -e

echo "=== Deploying to canary ==="
ansible-playbook deploy.yml --limit canary

echo "=== Waiting for verification ==="
read -p "Canary OK? Proceed to production? [y/N] " confirm
if [[ $confirm != "y" ]]; then
    echo "Deployment aborted"
    exit 1
fi

echo "=== Deploying to production ==="
ansible-playbook deploy.yml --limit production
```

#### Rollback Procedures

**Scenario 1: Bad container version**
```bash
# Revert version in docker-compose
git revert HEAD
# Redeploy
ansible-playbook deploy.yml --limit affected_hosts
```

**Scenario 2: Database migration issue**
```bash
# Restore from pre-upgrade Restic backup
restic -r sftp:user@backup-server:/client-x/restic-repo restore latest --target /tmp/restore
# Restore database dump
psql < /tmp/restore/db-dumps/keycloak.sql
# Revert and redeploy application
```

**Scenario 3: Complete server failure**
```bash
# Restore Hetzner snapshot via API
hcloud server rebuild <server-id> --image <snapshot-id>
# Or via OpenTofu
tofu apply -replace="hcloud_server.client[\"affected\"]"
```

---

## 9. Security Baseline

### Decision: Comprehensive Hardening

All servers receive the `common` Ansible role with:

#### SSH Hardening
```yaml
# /etc/ssh/sshd_config (managed by Ansible)
PermitRootLogin: no
PasswordAuthentication: no
PubkeyAuthentication: yes
AllowUsers: deploy
```

#### Firewall (UFW)
```yaml
- 22/tcp: Management IPs only
- 80/tcp: Any (redirects to 443)
- 443/tcp: Any
- All other: Deny
```

#### Automatic Updates
```yaml
# unattended-upgrades configuration
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Automatic-Reboot "false";  # Manual reboot control
```

#### Fail2ban
```yaml
# Jails enabled
- sshd
- traefik-auth (custom, for repeated 401s)
```

#### Container Security
```yaml
# Trivy scanning in CI/CD
- Scan images before deployment
- Block critical vulnerabilities
- Weekly scheduled scans of running containers
```

#### Additional Measures
- No password authentication anywhere
- Secrets encrypted with SOPS + Age, never plaintext in Git
- Regular dependency updates via Dependabot/Renovate
- SSH keys rotated annually

---

## 10. Onboarding Procedure

### New Client Checklist

```markdown
## Client Onboarding: {CLIENT_NAME}

### Prerequisites
- [ ] Client agreement signed
- [ ] Domain/subdomain confirmed: _______________
- [ ] Contact email: _______________
- [ ] Desired applications: [ ] Keycloak [ ] Nextcloud [ ] Pretix [ ] Listmonk

### Infrastructure
- [ ] Add client to `tofu/variables.tf`
- [ ] Add client to `ansible/inventory/clients.yml`
- [ ] Create secrets file: `sops secrets/clients/{name}.sops.yaml`
- [ ] Create Storage Box subdirectory for backups
- [ ] Run: `tofu apply`
- [ ] Run: `ansible-playbook playbooks/setup.yml --limit {client}`

### Verification
- [ ] HTTPS accessible
- [ ] Nextcloud admin login works
- [ ] Backup job runs successfully
- [ ] Monitoring checks green

### Handover
- [ ] Send credentials securely (1Password link, Signal, etc.)
- [ ] Schedule onboarding call if needed
- [ ] Add to status page (if applicable)
- [ ] Document any custom configuration

### Estimated Time: 30-45 minutes
```

---

## 11. Offboarding Procedure

### Client Removal Checklist

```markdown
## Client Offboarding: {CLIENT_NAME}

### Pre-Offboarding
- [ ] Confirm termination date: _______________
- [ ] Data export requested? [ ] Yes [ ] No
- [ ] Final invoice sent

### Data Export (if requested)
- [ ] Export Nextcloud data
- [ ] Confirm receipt

### Infrastructure Removal
- [ ] Disable monitoring checks (set maintenance mode first)
- [ ] Create final backup (retain per policy)
- [ ] Remove from Ansible inventory
- [ ] Remove from OpenTofu config
- [ ] Run: `tofu apply` (destroys VPS)
- [ ] Remove DNS records (automatic via OpenTofu)
- [ ] Remove/archive SOPS secrets file

### Backup Retention
- [ ] Move Restic repo to archive path
- [ ] Set deletion date: _______ (default: 90 days post-termination)
- [ ] Schedule deletion job

### Cleanup
- [ ] Remove from status page
- [ ] Update client count in documentation
- [ ] Archive client folder in documentation

### Verification
- [ ] DNS no longer resolves
- [ ] IP returns nothing
- [ ] Monitoring shows no alerts (host removed)
- [ ] Billing stopped

### Estimated Time: 15-30 minutes
```

### Data Retention Policy

| Data Type | Retention Post-Offboarding |
|-----------|---------------------------|
| Application data (Restic) | 90 days |
| Hetzner snapshots | Deleted immediately (with VPS) |
| SOPS secrets files | Archived 90 days, then deleted |
| Logs | 30 days |
| Invoices/contracts | 7 years (legal requirement) |

---

## 12. Repository Structure

```
infrastructure/
├── README.md
├── docs/
│   ├── architecture-decisions.md    # This document
│   ├── runbook.md                   # Operational procedures
│   └── clients/                     # Per-client notes
│       ├── alpha.md
│       └── beta.md
├── tofu/                            # OpenTofu configuration
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── dns.tf
│   ├── firewall.tf
│   └── versions.tf
├── ansible/
│   ├── ansible.cfg
│   ├── hcloud.yml                   # Dynamic inventory config
│   ├── playbooks/
│   │   ├── setup.yml                # Initial server setup
│   │   ├── deploy.yml               # Deploy/update applications
│   │   ├── upgrade.yml              # System updates
│   │   └── backup-restore.yml       # Manual backup/restore
│   ├── roles/
│   │   ├── common/
│   │   ├── docker/
│   │   ├── traefik/
│   │   ├── nextcloud/
│   │   ├── backup/
│   │   └── monitoring-agent/
│   └── group_vars/
│       └── all.yml
├── secrets/                         # SOPS-encrypted secrets
│   ├── .sops.yaml                   # SOPS configuration
│   ├── shared.sops.yaml             # Shared secrets
│   └── clients/
│       ├── alpha.sops.yaml
│       └── beta.sops.yaml
├── docker/
│   ├── docker-compose.base.yml      # Common services
│   └── docker-compose.apps.yml      # Application services
└── scripts/
    ├── deploy.sh                    # Canary deployment wrapper
    ├── onboard-client.sh
    └── offboard-client.sh
```

**Note:** The Age private key (`age-key.txt`) is NOT stored in this repository. It must be:
- Stored in a password manager
- Backed up securely offline
- Available on deployment machine only

---

## 13. Open Decisions / Future Considerations

### To Decide Later
- [ ] Identity provider (Authentik or other) - if SSO needed
- [ ] Prometheus metrics - when/if needed
- [ ] Custom domain SSL workflow
- [ ] Client self-service portal

### Scaling Triggers
- **20+ servers:** Consider Kubernetes or Nomad
- **Multi-region:** Add OpenTofu workspaces per region
- **Team growth:** Consider moving from SOPS to Infisical for better access control
- **Complex secret rotation:** May need dedicated secrets server

---

## 14. Technology Choices Rationale

### Why We Chose Open Source / European-Friendly Tools

| Tool | Chosen | Avoided | Reason |
|------|--------|---------|--------|
| IaC | OpenTofu | Terraform | BSL license concerns, HashiCorp trust issues |
| Secrets | SOPS + Age | HashiCorp Vault | Simplicity, no US vendor dependency, truly open source |
| Identity | (Removed) | Keycloak/Zitadel | Removed due to complexity; may add Authentik in future |
| Hosting | Hetzner | AWS/GCP/Azure | EU-based, cost-effective, GDPR-compliant |
| Backup | Restic + Hetzner Storage Box | Cloud backup services | Open source, EU data residency |

**Guiding Principles:**
1. Prefer truly open source (OSI-approved) over source-available
2. Prefer EU-based services for GDPR simplicity
3. Avoid vendor lock-in where practical
4. Choose simplicity appropriate to scale (10-50 servers)

---

## 15. Development Environment and Tooling

### Decision: Isolated Python Environments with pipx

**Choice:** Use `pipx` for installing Python CLI tools (Ansible) in isolated virtual environments.

**Why pipx:**
- Prevents dependency conflicts between tools
- Each tool has its own Python environment
- No interference with system Python packages
- Easy to upgrade/rollback individual tools
- Modern best practice for Python CLI tools

**Implementation:**
```bash
# Install pipx
brew install pipx
pipx ensurepath

# Install Ansible in isolation
pipx install --include-deps ansible

# Inject additional dependencies as needed
pipx inject ansible requests python-dateutil
```

**Benefits:**
| Aspect | Benefit |
|--------|---------|
| Isolation | No conflicts with other Python tools |
| Reproducibility | Each team member gets same isolated environment |
| Maintainability | Easy to upgrade Ansible without breaking other tools |
| Clean system | No pollution of system Python packages |

**Alternatives Considered:**
- **Homebrew Ansible** - Rejected: Can conflict with system Python, harder to manage dependencies
- **System pip install** - Rejected: Pollutes global Python environment
- **Manual venv** - Rejected: More manual work, pipx automates this

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2024-12 | Initial architecture decisions | Pieter / Claude |
| 2024-12 | Added Hetzner Storage Box as Restic backend | Pieter / Claude |
| 2024-12 | Switched from Terraform to OpenTofu (licensing concerns) | Pieter / Claude |
| 2024-12 | Switched from HashiCorp Vault to SOPS + Age (simplicity, open source) | Pieter / Claude |
| 2024-12 | Switched from Keycloak to Zitadel (Swiss company, GDPR jurisdiction) | Pieter / Claude |
| 2026-01 | Removed Zitadel due to FirstInstance bugs; may add Authentik in future | Pieter / Claude |
```