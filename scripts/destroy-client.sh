#!/usr/bin/env bash
#
# Destroy a client's infrastructure
#
# Usage: ./scripts/destroy-client.sh <client_name>
#
# This script will:
# 1. Remove all Docker containers and volumes on the server
# 2. Destroy the VPS server via OpenTofu
# 3. Remove DNS records
#
# WARNING: This is DESTRUCTIVE and IRREVERSIBLE!

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    exit 1
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

# Confirmation prompt
echo -e "${RED}========================================${NC}"
echo -e "${RED}WARNING: DESTRUCTIVE OPERATION${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "This will ${RED}PERMANENTLY DELETE${NC}:"
echo "  - VPS server for client: $CLIENT_NAME"
echo "  - All Docker containers and volumes"
echo "  - All DNS records"
echo "  - All data on the server"
echo ""
echo -e "${YELLOW}This operation CANNOT be undone!${NC}"
echo ""
read -p "Type the client name '$CLIENT_NAME' to confirm: " confirmation

if [ "$confirmation" != "$CLIENT_NAME" ]; then
    echo -e "${RED}Confirmation failed. Aborting.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Starting destruction of client: $CLIENT_NAME${NC}"
echo ""

# Step 1: Delete Mailgun SMTP credentials
echo -e "${YELLOW}[1/3] Deleting Mailgun SMTP credentials...${NC}"

cd "$PROJECT_ROOT/ansible"

# Run cleanup playbook to delete SMTP credentials
~/.local/bin/ansible-playbook -i hcloud.yml playbooks/cleanup.yml --limit "$CLIENT_NAME" 2>/dev/null || echo -e "${YELLOW}⚠ Could not delete SMTP credentials (API key may not be configured)${NC}"

echo -e "${GREEN}✓ SMTP credentials cleanup attempted${NC}"
echo ""

# Step 2: Clean up Docker containers and volumes on the server (if reachable)
echo -e "${YELLOW}[2/7] Cleaning up Docker containers and volumes...${NC}"

# Try to use per-client SSH key if it exists
SSH_KEY_ARG=""
if [ -f "$PROJECT_ROOT/keys/ssh/${CLIENT_NAME}" ]; then
    SSH_KEY_ARG="--private-key=$PROJECT_ROOT/keys/ssh/${CLIENT_NAME}"
fi

if ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" $SSH_KEY_ARG -m ping -o &>/dev/null; then
    echo "Server is reachable, cleaning up Docker resources..."

    # Stop and remove all containers
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" $SSH_KEY_ARG -m shell -a "docker ps -aq | xargs -r docker stop" -b 2>/dev/null || true
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" $SSH_KEY_ARG -m shell -a "docker ps -aq | xargs -r docker rm -f" -b 2>/dev/null || true

    # Remove all volumes
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" $SSH_KEY_ARG -m shell -a "docker volume ls -q | xargs -r docker volume rm -f" -b 2>/dev/null || true

    # Remove all networks (except defaults)
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" $SSH_KEY_ARG -m shell -a "docker network ls --filter type=custom -q | xargs -r docker network rm" -b 2>/dev/null || true

    echo -e "${GREEN}✓ Docker cleanup complete${NC}"
else
    echo -e "${YELLOW}⚠ Server not reachable, skipping Docker cleanup${NC}"
fi

echo ""

# Step 3: Destroy infrastructure with OpenTofu
echo -e "${YELLOW}[3/7] Destroying infrastructure with OpenTofu...${NC}"

cd "$PROJECT_ROOT/tofu"

# Destroy all resources for this client (server, volume, SSH key, DNS)
echo "Checking current infrastructure..."
tofu plan -destroy -var-file="terraform.tfvars" \
    -target="hcloud_server.client[\"$CLIENT_NAME\"]" \
    -target="hcloud_volume.nextcloud_data[\"$CLIENT_NAME\"]" \
    -target="hcloud_volume_attachment.nextcloud_data[\"$CLIENT_NAME\"]" \
    -target="hcloud_ssh_key.client_keys[\"$CLIENT_NAME\"]" \
    -target="hetznerdns_record.client_domain[\"$CLIENT_NAME\"]" \
    -target="hetznerdns_record.client_wildcard[\"$CLIENT_NAME\"]" \
    -out=destroy.tfplan

echo ""
echo "Applying destruction..."
tofu apply destroy.tfplan

# Cleanup plan file
rm -f destroy.tfplan

echo -e "${GREEN}✓ Infrastructure destroyed${NC}"
echo ""

# Step 4: Remove client from terraform.tfvars
echo -e "${YELLOW}[4/7] Removing client from terraform.tfvars...${NC}"

TFVARS_FILE="$PROJECT_ROOT/tofu/terraform.tfvars"
if grep -q "^[[:space:]]*${CLIENT_NAME}[[:space:]]*=" "$TFVARS_FILE"; then
    # Create backup
    cp "$TFVARS_FILE" "$TFVARS_FILE.bak"

    # Remove the client block (from "client_name = {" to the closing "}")
    # This uses awk to find and remove the entire block
    awk -v client="$CLIENT_NAME" '
        BEGIN { skip=0; in_block=0 }
        /^[[:space:]]*#.*[Cc]lient/ { if (skip==0) print; next }
        $0 ~ "^[[:space:]]*" client "[[:space:]]*=" { skip=1; in_block=1; brace_count=0; next }
        skip==1 {
            for(i=1; i<=length($0); i++) {
                c=substr($0,i,1)
                if(c=="{") brace_count++
                if(c=="}") brace_count--
            }
            if(brace_count<0 || (brace_count==0 && $0 ~ /^[[:space:]]*}/)) {
                skip=0
                in_block=0
                next
            }
            next
        }
        { print }
    ' "$TFVARS_FILE" > "$TFVARS_FILE.tmp"

    mv "$TFVARS_FILE.tmp" "$TFVARS_FILE"
    echo -e "${GREEN}✓ Removed $CLIENT_NAME from terraform.tfvars${NC}"
else
    echo -e "${YELLOW}⚠ Client not found in terraform.tfvars${NC}"
fi

echo ""

# Step 5: Remove SSH keys
echo -e "${YELLOW}[5/7] Removing SSH keys...${NC}"

SSH_PRIVATE="$PROJECT_ROOT/keys/ssh/${CLIENT_NAME}"
SSH_PUBLIC="$PROJECT_ROOT/keys/ssh/${CLIENT_NAME}.pub"

if [ -f "$SSH_PRIVATE" ]; then
    rm -f "$SSH_PRIVATE"
    echo -e "${GREEN}✓ Removed private key: $SSH_PRIVATE${NC}"
else
    echo -e "${YELLOW}⚠ Private key not found${NC}"
fi

if [ -f "$SSH_PUBLIC" ]; then
    rm -f "$SSH_PUBLIC"
    echo -e "${GREEN}✓ Removed public key: $SSH_PUBLIC${NC}"
else
    echo -e "${YELLOW}⚠ Public key not found${NC}"
fi

echo ""

# Step 6: Remove secrets file
echo -e "${YELLOW}[6/7] Removing secrets file...${NC}"

if [ -f "$SECRETS_FILE" ]; then
    rm -f "$SECRETS_FILE"
    echo -e "${GREEN}✓ Removed secrets file: $SECRETS_FILE${NC}"
else
    echo -e "${YELLOW}⚠ Secrets file not found${NC}"
fi

echo ""

# Step 7: Update client registry
echo -e "${YELLOW}[7/7] Updating client registry...${NC}"

"$SCRIPT_DIR/update-registry.sh" "$CLIENT_NAME" destroy

echo ""
echo -e "${GREEN}✓ Registry updated${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Client '$CLIENT_NAME' destroyed successfully${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The following have been removed:"
echo "  ✓ Mailgun SMTP credentials"
echo "  ✓ VPS server"
echo "  ✓ Hetzner Volume"
echo "  ✓ SSH keys (Hetzner + local)"
echo "  ✓ DNS records"
echo "  ✓ Firewall rules"
echo "  ✓ Secrets file"
echo "  ✓ terraform.tfvars entry"
echo "  ✓ Registry entry"
echo ""
echo "The client has been completely removed from the infrastructure."
echo ""
