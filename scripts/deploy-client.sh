#!/usr/bin/env bash
#
# Deploy a fresh client from scratch
#
# Usage: ./scripts/deploy-client.sh <client_name>
#
# This script will:
# 1. Provision new VPS server (if not exists)
# 2. Setup base system (Docker, Traefik)
# 3. Deploy applications (Authentik, Nextcloud)
# 4. Configure SSO integration
#
# Result: Fully functional Authentik + Nextcloud with automated SSO

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check arguments
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Client name required${NC}"
    echo "Usage: $0 <client_name>"
    echo ""
    echo "Example: $0 test"
    exit 1
fi

CLIENT_NAME="$1"

# Check if SSH key exists, generate if missing
SSH_KEY_FILE="$PROJECT_ROOT/keys/ssh/${CLIENT_NAME}"
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo -e "${YELLOW}SSH key not found for client: $CLIENT_NAME${NC}"
    echo "Generating SSH key pair automatically..."
    echo ""

    # Generate SSH key
    "$SCRIPT_DIR/generate-client-keys.sh" "$CLIENT_NAME"

    echo ""
    echo -e "${GREEN}✓ SSH key generated${NC}"
    echo ""
fi

# Check if secrets file exists, create from template if missing
SECRETS_FILE="$PROJECT_ROOT/secrets/clients/${CLIENT_NAME}.sops.yaml"
TEMPLATE_FILE="$PROJECT_ROOT/secrets/clients/template.sops.yaml"

if [ ! -f "$SECRETS_FILE" ]; then
    echo -e "${YELLOW}Secrets file not found for client: $CLIENT_NAME${NC}"
    echo "Creating from template and opening for editing..."
    echo ""

    # Check if template exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo -e "${RED}Error: Template file not found: $TEMPLATE_FILE${NC}"
        exit 1
    fi

    # Copy template
    cp "$TEMPLATE_FILE" "$SECRETS_FILE"
    echo -e "${GREEN}✓ Copied template to $SECRETS_FILE${NC}"
    echo ""

    # Open in SOPS for editing
    echo -e "${BLUE}Opening secrets file in SOPS for editing...${NC}"
    echo ""
    echo "Please update the following fields:"
    echo "  - client_name: $CLIENT_NAME"
    echo "  - client_domain: ${CLIENT_NAME}.vrije.cloud"
    echo "  - authentik_domain: auth.${CLIENT_NAME}.vrije.cloud"
    echo "  - nextcloud_domain: nextcloud.${CLIENT_NAME}.vrije.cloud"
    echo "  - REGENERATE all passwords and tokens!"
    echo ""
    echo "Press Enter to open editor..."
    read -r

    # Open in SOPS
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
        export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
    fi

    sops "$SECRETS_FILE"

    echo ""
    echo -e "${GREEN}✓ Secrets file configured${NC}"
    echo ""
fi

# Check required environment variables
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo -e "${RED}Error: HCLOUD_TOKEN environment variable not set${NC}"
    echo "Export your Hetzner Cloud API token:"
    echo "  export HCLOUD_TOKEN='your-token-here'"
    exit 1
fi

if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
    echo -e "${YELLOW}Warning: SOPS_AGE_KEY_FILE not set, using default${NC}"
    export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
fi

# Verify client is defined in terraform.tfvars
cd "$PROJECT_ROOT/tofu"

if ! grep -q "\"$CLIENT_NAME\"" terraform.tfvars 2>/dev/null; then
    echo -e "${YELLOW}⚠ Client '$CLIENT_NAME' not found in terraform.tfvars${NC}"
    echo ""
    echo "Add the following to tofu/terraform.tfvars:"
    echo ""
    echo "clients = {"
    echo "  \"$CLIENT_NAME\" = {"
    echo "    server_type = \"cx22\"     # 2 vCPU, 4GB RAM"
    echo "    location    = \"nbg1\"     # Nuremberg, Germany"
    echo "  }"
    echo "}"
    echo ""
    read -p "Continue anyway? (yes/no): " continue_confirm
    if [ "$continue_confirm" != "yes" ]; then
        exit 1
    fi
fi

# Start timer
START_TIME=$(date +%s)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploying fresh client: $CLIENT_NAME${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Provision infrastructure
echo -e "${YELLOW}[1/3] Provisioning infrastructure with OpenTofu...${NC}"

cd "$PROJECT_ROOT/tofu"

# Check if already exists
if tofu state list 2>/dev/null | grep -q "hcloud_server.client\[\"$CLIENT_NAME\"\]"; then
    echo -e "${YELLOW}⚠ Server already exists, applying any missing DNS records...${NC}"
    tofu apply -auto-approve -var-file="terraform.tfvars"
else
    # Apply full infrastructure (server + DNS)
    tofu apply -auto-approve -var-file="terraform.tfvars"

    echo ""
    echo -e "${GREEN}✓ Infrastructure provisioned${NC}"
    echo ""

    # Wait for server to be ready
    echo -e "${YELLOW}Waiting 60 seconds for server to initialize...${NC}"
    sleep 60
fi

echo ""

# Step 2: Setup base system
echo -e "${YELLOW}[2/3] Setting up base system (Docker, Traefik)...${NC}"

cd "$PROJECT_ROOT/ansible"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/setup.yml --limit "$CLIENT_NAME"

echo ""
echo -e "${GREEN}✓ Base system configured${NC}"
echo ""

# Step 3: Deploy applications
echo -e "${YELLOW}[3/3] Deploying applications (Authentik, Nextcloud, SSO)...${NC}"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit "$CLIENT_NAME"

echo ""
echo -e "${GREEN}✓ Applications deployed${NC}"
echo ""

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Success summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Time taken: ${MINUTES}m ${SECONDS}s${NC}"
echo ""
echo "Services deployed:"

# Load client domains from secrets
CLIENT_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^client_domain:" | awk '{print $2}')
AUTHENTIK_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^authentik_domain:" | awk '{print $2}')
NEXTCLOUD_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^nextcloud_domain:" | awk '{print $2}')
BOOTSTRAP_PASSWORD=$(sops -d "$SECRETS_FILE" | grep "^authentik_bootstrap_password:" | awk '{print $2}')
NEXTCLOUD_PASSWORD=$(sops -d "$SECRETS_FILE" | grep "^nextcloud_admin_password:" | awk '{print $2}')

echo "  ✓ Authentik SSO: https://$AUTHENTIK_DOMAIN"
echo "  ✓ Nextcloud:     https://$NEXTCLOUD_DOMAIN"
echo ""
echo "Admin credentials:"
echo "  Authentik:"
echo "    Username: akadmin"
echo "    Password: $BOOTSTRAP_PASSWORD"
echo ""
echo "  Nextcloud:"
echo "    Username: admin"
echo "    Password: $NEXTCLOUD_PASSWORD"
echo ""
echo -e "${GREEN}✓ SSO Integration: Fully automated and configured${NC}"
echo "  Users can login to Nextcloud with Authentik credentials"
echo "  'Login with Authentik' button is already visible"
echo ""
echo -e "${GREEN}Ready to use! No manual configuration required.${NC}"
echo ""
echo "Next steps:"
echo "  1. Login to Authentik: https://$AUTHENTIK_DOMAIN"
echo "  2. Create user accounts in Authentik"
echo "  3. Users can login to Nextcloud with those credentials"
echo ""
echo "Management commands:"
echo "  View secrets:    sops $SECRETS_FILE"
echo "  Rebuild server:  ./scripts/rebuild-client.sh $CLIENT_NAME"
echo "  Destroy server:  ./scripts/destroy-client.sh $CLIENT_NAME"
echo ""
