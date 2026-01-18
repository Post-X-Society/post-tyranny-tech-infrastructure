#!/usr/bin/env bash
#
# Retrieve passwords for a client from SOPS-encrypted secrets
# Usage: ./get-passwords.sh <client-name>
#
# This script decrypts and displays passwords in a readable format.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Main script
main() {
    if [ $# -ne 1 ]; then
        echo -e "${RED}Usage: $0 <client-name>${NC}"
        echo ""
        echo "Example: $0 green"
        exit 1
    fi

    CLIENT_NAME="$1"
    SECRETS_FILE="$PROJECT_ROOT/secrets/clients/${CLIENT_NAME}.sops.yaml"

    # Check if secrets file exists
    if [ ! -f "$SECRETS_FILE" ]; then
        echo -e "${RED}Error: Secrets file not found: $SECRETS_FILE${NC}"
        exit 1
    fi

    # Check for SOPS_AGE_KEY_FILE
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
        export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
    fi

    if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
        echo -e "${RED}Error: SOPS age key not found: $SOPS_AGE_KEY_FILE${NC}"
        exit 1
    fi

    # Decrypt and parse secrets
    TEMP_PLAIN=$(mktemp)
    sops -d "$SECRETS_FILE" > "$TEMP_PLAIN"

    # Extract values
    CLIENT_DOMAIN=$(grep "^client_domain:" "$TEMP_PLAIN" | awk '{print $2}')
    AUTHENTIK_DOMAIN=$(grep "^authentik_domain:" "$TEMP_PLAIN" | awk '{print $2}')
    NEXTCLOUD_DOMAIN=$(grep "^nextcloud_domain:" "$TEMP_PLAIN" | awk '{print $2}')
    AUTHENTIK_BOOTSTRAP_PASSWORD=$(grep "^authentik_bootstrap_password:" "$TEMP_PLAIN" | awk '{print $2}')
    AUTHENTIK_BOOTSTRAP_TOKEN=$(grep "^authentik_bootstrap_token:" "$TEMP_PLAIN" | awk '{print $2}')
    NEXTCLOUD_ADMIN_USER=$(grep "^nextcloud_admin_user:" "$TEMP_PLAIN" | awk '{print $2}')
    NEXTCLOUD_ADMIN_PASSWORD=$(grep "^nextcloud_admin_password:" "$TEMP_PLAIN" | awk '{print $2}')

    # Cleanup
    rm "$TEMP_PLAIN"

    # Display formatted output
    echo ""
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${CYAN}          Credentials for Client: ${GREEN}${CLIENT_NAME}${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo ""
    echo -e "${BLUE}Service URLs:${NC}"
    echo -e "  Client Domain:    ${GREEN}https://${CLIENT_DOMAIN}${NC}"
    echo -e "  Authentik SSO:    ${GREEN}https://${AUTHENTIK_DOMAIN}${NC}"
    echo -e "  Nextcloud:        ${GREEN}https://${NEXTCLOUD_DOMAIN}${NC}"
    echo ""
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${BLUE}Authentik Admin Access:${NC}"
    echo -e "  URL:              ${GREEN}https://${AUTHENTIK_DOMAIN}${NC}"
    echo -e "  Username:         ${GREEN}akadmin${NC}"
    echo -e "  Password:         ${YELLOW}${AUTHENTIK_BOOTSTRAP_PASSWORD}${NC}"
    echo -e "  API Token:        ${YELLOW}${AUTHENTIK_BOOTSTRAP_TOKEN}${NC}"
    echo ""
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${BLUE}Nextcloud Admin Access:${NC}"
    echo -e "  URL:              ${GREEN}https://${NEXTCLOUD_DOMAIN}${NC}"
    echo -e "  Username:         ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
    echo -e "  Password:         ${YELLOW}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
    echo ""
    echo -e "${CYAN}==============================================================${NC}"
    echo ""
    echo -e "${BLUE}💡 Tip: Copy passwords carefully - they are case-sensitive!${NC}"
    echo ""
}

main "$@"
