#!/usr/bin/env bash
#
# Remove client monitors from Uptime Kuma
#
# Usage: ./scripts/remove-client-from-monitoring.sh <client_name>
#
# This script removes HTTP(S) and SSL monitors for a destroyed client
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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Remove Client from Monitoring${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Client: ${CLIENT_NAME}${NC}"
echo ""

# TODO: Implement automated monitor removal via Uptime Kuma API
# For now, provide manual instructions

echo -e "${YELLOW}Manual Removal Required:${NC}"
echo ""
echo "Please remove the following monitors from Uptime Kuma:"
echo "🔗 Access: https://status.vrije.cloud"
echo ""
echo "Monitors to delete:"
echo "  • ${CLIENT_NAME} - Authentik"
echo "  • ${CLIENT_NAME} - Nextcloud"
echo "  • ${CLIENT_NAME} - Authentik SSL"
echo "  • ${CLIENT_NAME} - Nextcloud SSL"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Note: Automated monitor removal via API is planned for future enhancement.${NC}"
echo ""
