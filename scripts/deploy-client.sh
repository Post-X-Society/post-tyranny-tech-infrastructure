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

    # Copy template and decrypt to temporary file
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
        export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
    fi

    # Decrypt template to temp file
    TEMP_PLAIN=$(mktemp)
    sops -d "$TEMPLATE_FILE" > "$TEMP_PLAIN"

    # Replace client name placeholders
    sed -i '' "s/test/${CLIENT_NAME}/g" "$TEMP_PLAIN"

    # Create unencrypted file in correct location (matching .sops.yaml regex)
    # This is necessary because SOPS needs the file path to match creation rules
    TEMP_SOPS="${SECRETS_FILE%.sops.yaml}-unenc.sops.yaml"
    cat "$TEMP_PLAIN" > "$TEMP_SOPS"

    # Encrypt in-place (SOPS finds creation rules because path matches regex)
    sops --encrypt --in-place "$TEMP_SOPS"

    # Rename to final name
    mv "$TEMP_SOPS" "$SECRETS_FILE"

    # Cleanup
    rm "$TEMP_PLAIN"

    echo -e "${GREEN}✓ Created secrets file with client-specific domains${NC}"
    echo ""

    # Automatically generate unique passwords
    echo -e "${BLUE}Generating unique passwords for ${CLIENT_NAME}...${NC}"
    echo ""

    # Call the password generator script
    "$SCRIPT_DIR/generate-passwords.sh" "$CLIENT_NAME"

    echo ""
    echo -e "${GREEN}✓ Secrets file configured with unique passwords${NC}"
    echo ""
    echo -e "${YELLOW}To view credentials:${NC}"
    echo -e "  ${BLUE}./scripts/get-passwords.sh ${CLIENT_NAME}${NC}"
    echo ""
fi

# Load Hetzner API token from SOPS if not already set
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo -e "${BLUE}Loading Hetzner API token from SOPS...${NC}"
    # shellcheck source=scripts/load-secrets-env.sh
    source "$SCRIPT_DIR/load-secrets-env.sh"
    echo ""
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

# Check if client exists in terraform.tfvars
TFVARS_FILE="$PROJECT_ROOT/tofu/terraform.tfvars"
if ! grep -q "^[[:space:]]*${CLIENT_NAME}[[:space:]]*=" "$TFVARS_FILE"; then
    echo -e "${YELLOW}⚠ Client '${CLIENT_NAME}' not found in terraform.tfvars${NC}"
    echo ""
    echo "The client must be added to OpenTofu configuration before deployment."
    echo ""
    read -p "Would you like to add it now? (yes/no): " add_confirm

    if [ "$add_confirm" = "yes" ]; then
        echo ""
        "$SCRIPT_DIR/add-client-to-terraform.sh" "$CLIENT_NAME"
        echo ""
    else
        echo -e "${RED}Error: Cannot deploy without OpenTofu configuration${NC}"
        echo ""
        echo "Add the client manually to tofu/terraform.tfvars, or run:"
        echo "  ./scripts/add-client-to-terraform.sh $CLIENT_NAME"
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
echo -e "${YELLOW}[1/5] Provisioning infrastructure with OpenTofu...${NC}"

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
echo -e "${YELLOW}[2/5] Setting up base system (Docker, Traefik)...${NC}"

cd "$PROJECT_ROOT/ansible"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/setup.yml --limit "$CLIENT_NAME"

echo ""
echo -e "${GREEN}✓ Base system configured${NC}"
echo ""

# Step 3: Deploy applications
echo -e "${YELLOW}[3/5] Deploying applications (Authentik, Nextcloud, SSO)...${NC}"

~/.local/bin/ansible-playbook -i hcloud.yml playbooks/deploy.yml --limit "$CLIENT_NAME"

echo ""
echo -e "${GREEN}✓ Applications deployed${NC}"
echo ""

# Step 4: Update client registry
echo -e "${YELLOW}[4/5] Updating client registry...${NC}"

cd "$PROJECT_ROOT/tofu"

# Get server information from Terraform state
SERVER_IP=$(tofu output -json client_ips 2>/dev/null | jq -r ".\"$CLIENT_NAME\"" || echo "")
SERVER_ID=$(tofu state show "hcloud_server.client[\"$CLIENT_NAME\"]" 2>/dev/null | grep "^[[:space:]]*id[[:space:]]*=" | awk '{print $3}' | tr -d '"' || echo "")
SERVER_TYPE=$(tofu state show "hcloud_server.client[\"$CLIENT_NAME\"]" 2>/dev/null | grep "^[[:space:]]*server_type[[:space:]]*=" | awk '{print $3}' | tr -d '"' || echo "")
SERVER_LOCATION=$(tofu state show "hcloud_server.client[\"$CLIENT_NAME\"]" 2>/dev/null | grep "^[[:space:]]*location[[:space:]]*=" | awk '{print $3}' | tr -d '"' || echo "")

# Determine role (dev is canary, everything else is production by default)
ROLE="production"
if [ "$CLIENT_NAME" = "dev" ]; then
    ROLE="canary"
fi

# Update registry
"$SCRIPT_DIR/update-registry.sh" "$CLIENT_NAME" deploy \
    --role="$ROLE" \
    --server-ip="$SERVER_IP" \
    --server-id="$SERVER_ID" \
    --server-type="$SERVER_TYPE" \
    --server-location="$SERVER_LOCATION"

echo ""
echo -e "${GREEN}✓ Registry updated${NC}"
echo ""

# Collect deployed versions
echo -e "${YELLOW}Collecting deployed versions...${NC}"

"$SCRIPT_DIR/collect-client-versions.sh" "$CLIENT_NAME" 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not collect versions automatically${NC}"
    echo "Run manually later: ./scripts/collect-client-versions.sh $CLIENT_NAME"
}

echo ""

# Add to monitoring
echo -e "${YELLOW}[5/5] Adding client to monitoring...${NC}"
echo ""

if [ -f "$SCRIPT_DIR/add-client-to-monitoring.sh" ]; then
    "$SCRIPT_DIR/add-client-to-monitoring.sh" "$CLIENT_NAME"
else
    echo -e "${YELLOW}⚠ Monitoring script not found${NC}"
    echo "Manually add monitors at: https://status.vrije.cloud"
fi

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
