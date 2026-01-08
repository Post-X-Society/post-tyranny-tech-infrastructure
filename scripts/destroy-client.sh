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

# Step 1: Clean up Docker containers and volumes on the server (if reachable)
echo -e "${YELLOW}[1/2] Cleaning up Docker containers and volumes...${NC}"

cd "$PROJECT_ROOT/ansible"

if ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m ping -o &>/dev/null; then
    echo "Server is reachable, cleaning up Docker resources..."

    # Stop and remove all containers
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker ps -aq | xargs -r docker stop" -b 2>/dev/null || true
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker ps -aq | xargs -r docker rm -f" -b 2>/dev/null || true

    # Remove all volumes
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker volume ls -q | xargs -r docker volume rm -f" -b 2>/dev/null || true

    # Remove all networks (except defaults)
    ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker network ls --filter type=custom -q | xargs -r docker network rm" -b 2>/dev/null || true

    echo -e "${GREEN}✓ Docker cleanup complete${NC}"
else
    echo -e "${YELLOW}⚠ Server not reachable, skipping Docker cleanup${NC}"
fi

echo ""

# Step 2: Destroy infrastructure with OpenTofu
echo -e "${YELLOW}[2/2] Destroying infrastructure with OpenTofu...${NC}"

cd "$PROJECT_ROOT/tofu"

# Get current infrastructure state
echo "Checking current infrastructure..."
tofu plan -destroy -var-file="terraform.tfvars" -target="hcloud_server.client[\"$CLIENT_NAME\"]" -out=destroy.tfplan

echo ""
echo "Applying destruction..."
tofu apply destroy.tfplan

# Cleanup plan file
rm -f destroy.tfplan

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Client '$CLIENT_NAME' destroyed successfully${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The following have been removed:"
echo "  ✓ VPS server"
echo "  ✓ DNS records (if managed by OpenTofu)"
echo "  ✓ Firewall rules (if not shared)"
echo ""
echo -e "${YELLOW}Note: Secrets file still exists at:${NC}"
echo "  $SECRETS_FILE"
echo ""
echo "To rebuild this client, run:"
echo "  ./scripts/deploy-client.sh $CLIENT_NAME"
echo ""
