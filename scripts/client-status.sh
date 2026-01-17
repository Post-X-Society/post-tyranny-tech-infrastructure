#!/usr/bin/env bash
#
# Show detailed status for a specific client
#
# Usage: ./scripts/client-status.sh <client_name>
#
# Displays:
# - Deployment status and metadata
# - Server information
# - Application versions
# - Maintenance history
# - URLs and access information
# - Live health checks (optional)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Check if registry exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: Registry file not found: $REGISTRY_FILE${NC}"
    exit 1
fi

# Check if client exists
if yq eval ".clients.\"$CLIENT_NAME\"" "$REGISTRY_FILE" | grep -q "null"; then
    echo -e "${RED}Error: Client '$CLIENT_NAME' not found in registry${NC}"
    echo ""
    echo "Available clients:"
    yq eval '.clients | keys | .[]' "$REGISTRY_FILE"
    exit 1
fi

# Extract client information
STATUS=$(yq eval ".clients.\"$CLIENT_NAME\".status" "$REGISTRY_FILE")
ROLE=$(yq eval ".clients.\"$CLIENT_NAME\".role" "$REGISTRY_FILE")
DEPLOYED_DATE=$(yq eval ".clients.\"$CLIENT_NAME\".deployed_date" "$REGISTRY_FILE")
DESTROYED_DATE=$(yq eval ".clients.\"$CLIENT_NAME\".destroyed_date" "$REGISTRY_FILE")

SERVER_TYPE=$(yq eval ".clients.\"$CLIENT_NAME\".server.type" "$REGISTRY_FILE")
SERVER_LOCATION=$(yq eval ".clients.\"$CLIENT_NAME\".server.location" "$REGISTRY_FILE")
SERVER_IP=$(yq eval ".clients.\"$CLIENT_NAME\".server.ip" "$REGISTRY_FILE")
SERVER_ID=$(yq eval ".clients.\"$CLIENT_NAME\".server.id" "$REGISTRY_FILE")

APPS=$(yq eval ".clients.\"$CLIENT_NAME\".apps | join(\", \")" "$REGISTRY_FILE")

AUTHENTIK_VERSION=$(yq eval ".clients.\"$CLIENT_NAME\".versions.authentik" "$REGISTRY_FILE")
NEXTCLOUD_VERSION=$(yq eval ".clients.\"$CLIENT_NAME\".versions.nextcloud" "$REGISTRY_FILE")
TRAEFIK_VERSION=$(yq eval ".clients.\"$CLIENT_NAME\".versions.traefik" "$REGISTRY_FILE")
UBUNTU_VERSION=$(yq eval ".clients.\"$CLIENT_NAME\".versions.ubuntu" "$REGISTRY_FILE")

LAST_FULL_UPDATE=$(yq eval ".clients.\"$CLIENT_NAME\".maintenance.last_full_update" "$REGISTRY_FILE")
LAST_SECURITY_PATCH=$(yq eval ".clients.\"$CLIENT_NAME\".maintenance.last_security_patch" "$REGISTRY_FILE")
LAST_OS_UPDATE=$(yq eval ".clients.\"$CLIENT_NAME\".maintenance.last_os_update" "$REGISTRY_FILE")
LAST_BACKUP_VERIFIED=$(yq eval ".clients.\"$CLIENT_NAME\".maintenance.last_backup_verified" "$REGISTRY_FILE")

AUTHENTIK_URL=$(yq eval ".clients.\"$CLIENT_NAME\".urls.authentik" "$REGISTRY_FILE")
NEXTCLOUD_URL=$(yq eval ".clients.\"$CLIENT_NAME\".urls.nextcloud" "$REGISTRY_FILE")

NOTES=$(yq eval ".clients.\"$CLIENT_NAME\".notes" "$REGISTRY_FILE")

# Display header
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  CLIENT STATUS: $CLIENT_NAME${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Status section
echo -e "${CYAN}━━━ Deployment Status ━━━${NC}"
echo ""

# Color status
STATUS_COLOR=$NC
case $STATUS in
    deployed) STATUS_COLOR=$GREEN ;;
    pending) STATUS_COLOR=$YELLOW ;;
    maintenance) STATUS_COLOR=$CYAN ;;
    offboarding) STATUS_COLOR=$RED ;;
    destroyed) STATUS_COLOR=$RED ;;
esac

# Color role
ROLE_COLOR=$NC
case $ROLE in
    canary) ROLE_COLOR=$YELLOW ;;
    production) ROLE_COLOR=$GREEN ;;
esac

echo -e "Status:        ${STATUS_COLOR}$STATUS${NC}"
echo -e "Role:          ${ROLE_COLOR}$ROLE${NC}"
echo -e "Deployed:      $DEPLOYED_DATE"
if [ "$DESTROYED_DATE" != "null" ]; then
    echo -e "Destroyed:     ${RED}$DESTROYED_DATE${NC}"
fi
echo ""

# Server section
echo -e "${CYAN}━━━ Server Information ━━━${NC}"
echo ""
echo -e "Server Type:   $SERVER_TYPE"
echo -e "Location:      $SERVER_LOCATION"
echo -e "IP Address:    $SERVER_IP"
echo -e "Server ID:     $SERVER_ID"
echo ""

# Applications section
echo -e "${CYAN}━━━ Applications ━━━${NC}"
echo ""
echo -e "Installed:     $APPS"
echo ""

# Versions section
echo -e "${CYAN}━━━ Versions ━━━${NC}"
echo ""
echo -e "Authentik:     $AUTHENTIK_VERSION"
echo -e "Nextcloud:     $NEXTCLOUD_VERSION"
echo -e "Traefik:       $TRAEFIK_VERSION"
echo -e "Ubuntu:        $UBUNTU_VERSION"
echo ""

# Maintenance section
echo -e "${CYAN}━━━ Maintenance History ━━━${NC}"
echo ""
echo -e "Last Full Update:      $LAST_FULL_UPDATE"
echo -e "Last Security Patch:   $LAST_SECURITY_PATCH"
echo -e "Last OS Update:        $LAST_OS_UPDATE"
if [ "$LAST_BACKUP_VERIFIED" != "null" ]; then
    echo -e "Last Backup Verified:  $LAST_BACKUP_VERIFIED"
else
    echo -e "Last Backup Verified:  ${YELLOW}Never${NC}"
fi
echo ""

# URLs section
echo -e "${CYAN}━━━ Access URLs ━━━${NC}"
echo ""
echo -e "Authentik:     $AUTHENTIK_URL"
echo -e "Nextcloud:     $NEXTCLOUD_URL"
echo ""

# Notes section
if [ "$NOTES" != "null" ] && [ -n "$NOTES" ]; then
    echo -e "${CYAN}━━━ Notes ━━━${NC}"
    echo ""
    echo "$NOTES" | sed 's/^/  /'
    echo ""
fi

# Live health check (if server is deployed and reachable)
if [ "$STATUS" = "deployed" ]; then
    echo -e "${CYAN}━━━ Live Health Check ━━━${NC}"
    echo ""

    # Check if server is reachable via SSH (if Ansible is configured)
    if command -v ansible &> /dev/null && [ -n "${HCLOUD_TOKEN:-}" ]; then
        cd "$PROJECT_ROOT/ansible"
        if timeout 10 ~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m ping -o &>/dev/null; then
            echo -e "SSH Access:    ${GREEN}✓ Reachable${NC}"

            # Get Docker status
            DOCKER_STATUS=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "docker ps --format '{{.Names}}' 2>/dev/null | wc -l" -o 2>/dev/null | tail -1 | awk '{print $NF}' || echo "0")
            if [ "$DOCKER_STATUS" != "0" ]; then
                echo -e "Docker:        ${GREEN}✓ Running ($DOCKER_STATUS containers)${NC}"
            else
                echo -e "Docker:        ${RED}✗ No containers running${NC}"
            fi
        else
            echo -e "SSH Access:    ${RED}✗ Not reachable${NC}"
        fi
    else
        echo -e "${YELLOW}Note: Install Ansible and set HCLOUD_TOKEN for live health checks${NC}"
    fi

    echo ""

    # Check HTTPS endpoints
    echo -e "HTTPS Endpoints:"

    # Check Authentik
    if command -v curl &> /dev/null; then
        if timeout 10 curl -sSf -o /dev/null "$AUTHENTIK_URL" 2>/dev/null; then
            echo -e "  Authentik:   ${GREEN}✓ Responding${NC}"
        else
            echo -e "  Authentik:   ${RED}�� Not responding${NC}"
        fi

        # Check Nextcloud
        if timeout 10 curl -sSf -o /dev/null "$NEXTCLOUD_URL" 2>/dev/null; then
            echo -e "  Nextcloud:   ${GREEN}✓ Responding${NC}"
        else
            echo -e "  Nextcloud:   ${RED}✗ Not responding${NC}"
        fi
    else
        echo -e "  ${YELLOW}Install curl for endpoint checks${NC}"
    fi

    echo ""
fi

# Management commands section
echo -e "${CYAN}━━━ Management Commands ━━━${NC}"
echo ""
echo -e "View secrets:    ${BLUE}sops secrets/clients/${CLIENT_NAME}.sops.yaml${NC}"
echo -e "Rebuild server:  ${BLUE}./scripts/rebuild-client.sh $CLIENT_NAME${NC}"
echo -e "Destroy server:  ${BLUE}./scripts/destroy-client.sh $CLIENT_NAME${NC}"
echo -e "List all:        ${BLUE}./scripts/list-clients.sh${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
