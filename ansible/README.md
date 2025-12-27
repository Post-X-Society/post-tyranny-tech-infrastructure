# Ansible Configuration Management

Ansible playbooks and roles for configuring and managing the multi-tenant VPS infrastructure.

## Prerequisites

### 1. Install Ansible (via pipx - isolated environment)

**Why pipx?** Isolates Ansible in its own Python environment, preventing conflicts.

```bash
# Install pipx
brew install pipx
pipx ensurepath

# Install Ansible
pipx install --include-deps ansible

# Install required dependencies
pipx inject ansible requests python-dateutil

# Verify installation
ansible --version
```

### 2. Install Ansible Collections

```bash
ansible-galaxy collection install hetzner.hcloud community.sops community.general
```

### 3. Set Hetzner Cloud API Token

```bash
export HCLOUD_TOKEN="your-hetzner-cloud-api-token"
```

Or add to your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export HCLOUD_TOKEN="your-token-here"
```

## Quick Start

### Test Dynamic Inventory

```bash
cd ansible
ansible-inventory --graph
```

You should see your servers grouped by labels.

### Ping All Servers

```bash
ansible all -m ping
```

### Run Setup Playbook

```bash
# Full setup (common + docker + traefik)
ansible-playbook playbooks/setup.yml

# Specific server
ansible-playbook playbooks/setup.yml --limit test

# Dry run (check mode)
ansible-playbook playbooks/setup.yml --check
```

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── hcloud.yml               # Hetzner Cloud dynamic inventory
├── playbooks/               # Playbook definitions
│   ├── setup.yml            # Initial server setup
│   ├── deploy.yml           # Deploy/update applications
│   └── upgrade.yml          # System upgrades
├── roles/                   # Role definitions
│   ├── common/              # Base system hardening
│   ├── docker/              # Docker + Docker Compose
│   ├── traefik/             # Reverse proxy
│   ├── zitadel/             # Identity provider
│   ├── nextcloud/           # File sync/share
│   └── backup/              # Restic backup
└── group_vars/              # Group variables
    └── all.yml              # Variables for all hosts
```

## Roles

### common
Base system configuration and security hardening:
- SSH hardening (key-only auth, no root password)
- UFW firewall configuration
- Fail2ban for SSH protection
- Automatic security updates
- Timezone and locale setup

**Variables** (`roles/common/defaults/main.yml`):
- `common_timezone`: System timezone (default: `Europe/Amsterdam`)
- `common_ssh_port`: SSH port (default: `22`)
- `common_ufw_allowed_ports`: List of allowed firewall ports

### docker
Docker and Docker Compose installation:
- Latest Docker Engine from official repository
- Docker Compose V2
- Docker daemon configuration
- User permissions for Docker

### traefik
Reverse proxy with automatic SSL:
- Traefik v3 with Docker provider
- Let's Encrypt automatic certificate generation
- HTTP to HTTPS redirection
- Dashboard (optional)

### zitadel
Identity provider deployment (see Zitadel Agent for details)

### nextcloud
File sync/share deployment (see Nextcloud Agent for details)

### backup
Restic backup configuration to Hetzner Storage Box

## Playbooks

### setup.yml
Initial server provisioning and configuration:
```bash
ansible-playbook playbooks/setup.yml
```

Runs roles in order:
1. `common` - Base hardening
2. `docker` - Container platform
3. `traefik` - Reverse proxy

### deploy.yml
Deploy or update applications:
```bash
ansible-playbook playbooks/deploy.yml
```

Runs application-specific roles based on server labels.

## Dynamic Inventory

The `hcloud.yml` inventory automatically queries Hetzner Cloud API for servers.

**Server Grouping:**
- By client: `client_test`, `client_alpha`
- By role: `role_app_server`
- By location: `location_fsn1`, `location_nbg1`

**View inventory:**
```bash
ansible-inventory --graph
ansible-inventory --list
ansible-inventory --host test
```

## Common Tasks

### Check Server Connectivity
```bash
ansible all -m ping
```

### Run Ad-hoc Command
```bash
ansible all -a "uptime"
ansible all -a "df -h"
```

### Update All Packages
```bash
ansible all -m apt -a "update_cache=yes upgrade=dist"
```

### Restart Service
```bash
ansible all -m service -a "name=docker state=restarted"
```

### Limit to Specific Hosts
```bash
# Single host
ansible-playbook playbooks/setup.yml --limit test

# Multiple hosts
ansible-playbook playbooks/setup.yml --limit "test,alpha"

# Group
ansible-playbook playbooks/setup.yml --limit client_test
```

## Development Workflow

### Creating a New Role

```bash
cd ansible/roles
mkdir -p newrole/{tasks,handlers,templates,defaults,files}
```

Minimum structure:
- `defaults/main.yml` - Default variables
- `tasks/main.yml` - Main task list
- `handlers/main.yml` - Service handlers (optional)
- `templates/` - Jinja2 templates (optional)

### Testing Changes

```bash
# Syntax check
ansible-playbook playbooks/setup.yml --syntax-check

# Dry run (no changes)
ansible-playbook playbooks/setup.yml --check

# Limit to test server
ansible-playbook playbooks/setup.yml --limit test

# Verbose output
ansible-playbook playbooks/setup.yml -v
ansible-playbook playbooks/setup.yml -vvv  # Very verbose
```

## Troubleshooting

### "No inventory was parsed"
- Ensure `HCLOUD_TOKEN` environment variable is set
- Verify token has read access
- Check `hcloud.yml` syntax

### "Failed to connect to host"
- Verify server is running: `tofu show`
- Check SSH key is correct: `ssh -i ~/.ssh/ptt_infrastructure root@<ip>`
- Verify firewall allows SSH from your IP

### "Permission denied (publickey)"
- Ensure `~/.ssh/ptt_infrastructure` private key exists
- Check `ansible.cfg` points to correct key
- Verify public key was added to server via OpenTofu

### "Module not found"
- Install missing Ansible collection:
  ```bash
  ansible-galaxy collection install <collection-name>
  ```

### Ansible is slow
- Enable SSH pipelining (already configured in `ansible.cfg`)
- Use `--forks` to increase parallelism: `ansible-playbook playbooks/setup.yml --forks 20`
- Enable fact caching (already configured)

## Security Notes

- Ansible connects as `root` user via SSH key
- No passwords are used anywhere
- SSH hardening applied automatically via `common` role
- UFW firewall enabled by default
- Fail2ban protects SSH
- Automatic security updates enabled

## Next Steps

After initial setup:
1. Deploy Zitadel: Follow Zitadel Agent instructions
2. Deploy Nextcloud: Follow Nextcloud Agent instructions
3. Configure backups: Use `backup` role
4. Set up monitoring: Configure Uptime Kuma

## Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Hetzner Cloud Ansible Collection](https://github.com/ansible-collections/hetzner.hcloud)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
