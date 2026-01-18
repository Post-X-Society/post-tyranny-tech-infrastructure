#!/usr/bin/env bash
#
# Add client monitors to Uptime Kuma
#
# Usage: ./scripts/add-client-to-monitoring.sh <client_name>
#
# This script creates HTTP(S) and SSL monitors for a client's services
# Currently uses manual instructions - future: use Uptime Kuma API

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
    exit 1
fi

CLIENT_NAME="$1"
BASE_DOMAIN="vrije.cloud"

# Calculate URLs
AUTH_URL="https://auth.${CLIENT_NAME}.${BASE_DOMAIN}"
NEXTCLOUD_URL="https://nextcloud.${CLIENT_NAME}.${BASE_DOMAIN}"
AUTH_DOMAIN="auth.${CLIENT_NAME}.${BASE_DOMAIN}"
NEXTCLOUD_DOMAIN="nextcloud.${CLIENT_NAME}.${BASE_DOMAIN}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Add Client to Monitoring${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Client: ${CLIENT_NAME}${NC}"
echo ""

# TODO: Implement automated monitor creation via Uptime Kuma API
# For now, provide manual instructions

echo -e "${YELLOW}Manual Setup Required:${NC}"
echo ""
echo "Please add the following monitors in Uptime Kuma:"
echo "🔗 Access: https://status.vrije.cloud"
echo ""
echo -e "${GREEN}HTTP(S) Monitors:${NC}"
echo ""
echo "1. ${CLIENT_NAME} - Authentik"
echo "   Type: HTTP(S)"
echo "   URL: ${AUTH_URL}"
echo "   Interval: 300 seconds (5 min)"
echo "   Retries: 3"
echo ""
echo "2. ${CLIENT_NAME} - Nextcloud"
echo "   Type: HTTP(S)"
echo "   URL: ${NEXTCLOUD_URL}"
echo "   Interval: 300 seconds (5 min)"
echo "   Retries: 3"
echo ""
echo -e "${GREEN}SSL Certificate Monitors:${NC}"
echo ""
echo "3. ${CLIENT_NAME} - Authentik SSL"
echo "   Type: Certificate Expiry"
echo "   Hostname: ${AUTH_DOMAIN}"
echo "   Port: 443"
echo "   Expiry Days: 30"
echo "   Interval: 86400 seconds (1 day)"
echo ""
echo "4. ${CLIENT_NAME} - Nextcloud SSL"
echo "   Type: Certificate Expiry"
echo "   Hostname: ${NEXTCLOUD_DOMAIN}"
echo "   Port: 443"
echo "   Expiry Days: 30"
echo "   Interval: 86400 seconds (1 day)"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Note: Automated monitor creation via API is planned for future enhancement.${NC}"
echo ""
