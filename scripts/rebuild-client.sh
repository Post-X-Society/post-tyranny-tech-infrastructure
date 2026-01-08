#!/usr/bin/env bash
#
# Rebuild a client's infrastructure from scratch
#
# Usage: ./scripts/rebuild-client.sh <client_name>
#
# This script will:
# 1. Destroy existing infrastructure (if exists)
# 2. Provision new VPS server
# 3. Deploy and configure all services
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

# Check if secrets file exists
SECRETS_FILE="$PROJECT_ROOT/secrets/clients/${CLIENT_NAME}.sops.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
    echo -e "${RED}Error: Secrets file not found: $SECRETS_FILE${NC}"
    echo ""
    echo "Create a secrets file first:"
    echo "  cp secrets/clients/test.sops.yaml secrets/clients/${CLIENT_NAME}.sops.yaml"
    echo "  sops secrets/clients/${CLIENT_NAME}.sops.yaml"
    exit 1
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

# Start timer
START_TIME=$(date +%s)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Rebuilding client: $CLIENT_NAME${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check if infrastructure exists and destroy it
echo -e "${YELLOW}[1/4] Checking existing infrastructure...${NC}"

cd "$PROJECT_ROOT/tofu"

if tofu state list 2>/dev/null | grep -q "hcloud_server.client\[\"$CLIENT_NAME\"\]"; then
    echo -e "${YELLOW}⚠ Existing infrastructure found${NC}"
    echo ""
    read -p "Destroy existing infrastructure? (yes/no): " destroy_confirm

    if [ "$destroy_confirm" = "yes" ]; then
        echo "Destroying existing infrastructure..."
        "$SCRIPT_DIR/destroy-client.sh" "$CLIENT_NAME"
        echo ""
        echo -e "${GREEN}✓ Existing infrastructure destroyed${NC}"
        echo ""
        echo "Waiting 10 seconds for cleanup to complete..."
        sleep 10
    else
        echo -e "${RED}Cannot proceed without destroying existing infrastructure${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ No existing infrastructure found${NC}"
fi

echo ""

# Step 2: Provision infrastructure
echo -e "${YELLOW}[2/4] Provisioning infrastructure with OpenTofu...${NC}"

cd "$PROJECT_ROOT/tofu"

# Apply full configuration to create server AND DNS records
tofu apply -auto-approve -var-file="terraform.tfvars"

echo ""
echo -e "${GREEN}✓ Infrastructure provisioned (server + DNS)${NC}"
echo ""

# Wait for server to be ready
echo -e "${YELLOW}Waiting 60 seconds for server to initialize...${NC}"
sleep 60

echo ""

# Step 3: Setup base system
echo -e "${YELLOW}[3/4] Setting up base system (Docker, Traefik)...${NC}"

cd "$PROJECT_ROOT/ansible"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/setup.yml --limit "$CLIENT_NAME"

echo ""
echo -e "${GREEN}✓ Base system configured${NC}"
echo ""

# Step 4: Deploy applications
echo -e "${YELLOW}[4/4] Deploying applications (Authentik, Nextcloud, SSO)...${NC}"

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
echo -e "${GREEN}✓ Rebuild complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Time taken: ${MINUTES}m ${SECONDS}s${NC}"
echo ""
echo "Services deployed:"

# Load client domain from secrets
CLIENT_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^client_domain:" | awk '{print $2}')
AUTHENTIK_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^authentik_domain:" | awk '{print $2}')
NEXTCLOUD_DOMAIN=$(sops -d "$SECRETS_FILE" | grep "^nextcloud_domain:" | awk '{print $2}')

echo "  ✓ Authentik SSO: https://$AUTHENTIK_DOMAIN"
echo "  ✓ Nextcloud:     https://$NEXTCLOUD_DOMAIN"
echo ""
echo "Admin credentials:"
echo "  Authentik: akadmin / (see secrets file)"
echo "  Nextcloud: admin / (see secrets file)"
echo ""
echo -e "${GREEN}Ready to use! No manual configuration required.${NC}"
echo ""
echo "To view secrets:"
echo "  sops $SECRETS_FILE"
echo ""
echo "To destroy this client:"
echo "  ./scripts/destroy-client.sh $CLIENT_NAME"
echo ""
