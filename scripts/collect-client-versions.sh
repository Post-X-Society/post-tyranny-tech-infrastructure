#!/usr/bin/env bash
#
# Collect deployed software versions from a client and update registry
#
# Usage: ./scripts/collect-client-versions.sh <client_name>
#
# Queries the deployed server for actual running versions:
# - Docker container image versions
# - Ubuntu OS version
# - Updates the client registry with collected versions

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
REGISTRY_FILE="$PROJECT_ROOT/clients/registry.yml"

# Check arguments
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Client name required${NC}"
    echo "Usage: $0 <client_name>"
    echo ""
    echo "Example: $0 dev"
    exit 1
fi

CLIENT_NAME="$1"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo -e "${RED}Error: 'yq' not found. Install with: brew install yq${NC}"
    exit 1
fi

# Load Hetzner API token from SOPS if not already set
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    # shellcheck source=scripts/load-secrets-env.sh
    source "$SCRIPT_DIR/load-secrets-env.sh" > /dev/null 2>&1
fi

# Check if registry exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: Registry file not found: $REGISTRY_FILE${NC}"
    exit 1
fi

# Check if client exists in registry
if yq eval ".clients.\"$CLIENT_NAME\"" "$REGISTRY_FILE" | grep -q "null"; then
    echo -e "${RED}Error: Client '$CLIENT_NAME' not found in registry${NC}"
    exit 1
fi

echo -e "${BLUE}Collecting versions for client: $CLIENT_NAME${NC}"
echo ""

cd "$PROJECT_ROOT/ansible"

# Check if server is reachable
if ! timeout 10 ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m ping -o &>/dev/null; then
    echo -e "${RED}Error: Cannot reach server for client '$CLIENT_NAME'${NC}"
    echo "Server may not be deployed or network is unreachable"
    exit 1
fi

echo -e "${YELLOW}Querying deployed versions...${NC}"
echo ""

# Query Docker container versions
echo "Collecting Docker container versions..."

# Function to extract version from image tag
extract_version() {
    local image=$1
    # Extract version after the colon, or return "latest"
    if [[ $image == *":"* ]]; then
        echo "$image" | awk -F: '{print $2}'
    else
        echo "latest"
    fi
}

# Collect Authentik version
AUTHENTIK_IMAGE=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker inspect authentik-server 2>/dev/null | jq -r '.[0].Config.Image' 2>/dev/null || echo 'unknown'" -o 2>/dev/null | tail -1 | awk '{print $NF}')
AUTHENTIK_VERSION=$(extract_version "$AUTHENTIK_IMAGE")

# Collect Nextcloud version
NEXTCLOUD_IMAGE=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker inspect nextcloud 2>/dev/null | jq -r '.[0].Config.Image' 2>/dev/null || echo 'unknown'" -o 2>/dev/null | tail -1 | awk '{print $NF}')
NEXTCLOUD_VERSION=$(extract_version "$NEXTCLOUD_IMAGE")

# Collect Traefik version
TRAEFIK_IMAGE=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker inspect traefik 2>/dev/null | jq -r '.[0].Config.Image' 2>/dev/null || echo 'unknown'" -o 2>/dev/null | tail -1 | awk '{print $NF}')
TRAEFIK_VERSION=$(extract_version "$TRAEFIK_IMAGE")

# Collect Ubuntu version
UBUNTU_VERSION=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "lsb_release -rs 2>/dev/null || echo 'unknown'" -o 2>/dev/null | tail -1 | awk '{print $NF}')

echo -e "${GREEN}✓ Versions collected${NC}"
echo ""

# Display collected versions
echo "Collected versions:"
echo "  Authentik:  $AUTHENTIK_VERSION"
echo "  Nextcloud:  $NEXTCLOUD_VERSION"
echo "  Traefik:    $TRAEFIK_VERSION"
echo "  Ubuntu:     $UBUNTU_VERSION"
echo ""

# Update registry
echo -e "${YELLOW}Updating registry...${NC}"

# Update versions in registry
yq eval -i ".clients.\"$CLIENT_NAME\".versions.authentik = \"$AUTHENTIK_VERSION\"" "$REGISTRY_FILE"
yq eval -i ".clients.\"$CLIENT_NAME\".versions.nextcloud = \"$NEXTCLOUD_VERSION\"" "$REGISTRY_FILE"
yq eval -i ".clients.\"$CLIENT_NAME\".versions.traefik = \"$TRAEFIK_VERSION\"" "$REGISTRY_FILE"
yq eval -i ".clients.\"$CLIENT_NAME\".versions.ubuntu = \"$UBUNTU_VERSION\"" "$REGISTRY_FILE"

echo -e "${GREEN}✓ Registry updated${NC}"
echo ""
echo "Updated: $REGISTRY_FILE"
echo ""
echo "To view registry:"
echo "  ./scripts/client-status.sh $CLIENT_NAME"
