#!/usr/bin/env bash
#
# Add a new client to OpenTofu configuration
#
# Usage: ./scripts/add-client-to-terraform.sh <client_name> [options]
#
# Options:
#   --server-type=TYPE      Server type (default: cpx22)
#   --location=LOC          Data center location (default: fsn1)
#   --volume-size=SIZE      Nextcloud volume size in GB (default: 100)
#   --apps=APP1,APP2        Applications to deploy (default: zitadel,nextcloud)
#   --non-interactive       Don't prompt, use defaults

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
TFVARS_FILE="$PROJECT_ROOT/tofu/terraform.tfvars"

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Client name required${NC}"
    echo "Usage: $0 <client_name> [options]"
    echo ""
    echo "Options:"
    echo "  --server-type=TYPE      Server type (default: cpx22)"
    echo "  --location=LOC          Data center (default: fsn1)"
    echo "  --volume-size=SIZE      Nextcloud volume GB (default: 100)"
    echo "  --apps=APP1,APP2        Apps (default: zitadel,nextcloud)"
    echo "  --non-interactive       Use defaults, don't prompt"
    echo ""
    echo "Example: $0 blue --server-type=cx22 --location=nbg1 --volume-size=50"
    exit 1
fi

CLIENT_NAME="$1"
shift

# Default values
SERVER_TYPE="cpx22"
LOCATION="fsn1"
VOLUME_SIZE="100"
APPS="zitadel,nextcloud"
NON_INTERACTIVE=false

# Parse options
for arg in "$@"; do
    case $arg in
        --server-type=*)
            SERVER_TYPE="${arg#*=}"
            ;;
        --location=*)
            LOCATION="${arg#*=}"
            ;;
        --volume-size=*)
            VOLUME_SIZE="${arg#*=}"
            ;;
        --apps=*)
            APPS="${arg#*=}"
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

# Validate client name
if [[ ! "$CLIENT_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}Error: Client name must contain only lowercase letters, numbers, and hyphens${NC}"
    exit 1
fi

# Check if tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: terraform.tfvars not found at $TFVARS_FILE${NC}"
    exit 1
fi

# Check if client already exists
if grep -q "^[[:space:]]*${CLIENT_NAME}[[:space:]]*=" "$TFVARS_FILE"; then
    echo -e "${YELLOW}⚠ Client '${CLIENT_NAME}' already exists in terraform.tfvars${NC}"
    echo ""
    echo "Existing configuration:"
    grep -A 7 "^[[:space:]]*${CLIENT_NAME}[[:space:]]*=" "$TFVARS_FILE" | head -8
    echo ""
    read -p "Update configuration? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Remove existing entry
    # This is complex - for now just error and let user handle manually
    echo -e "${RED}Error: Updating existing clients not yet implemented${NC}"
    echo "Please manually edit $TFVARS_FILE"
    exit 1
fi

# Interactive prompts (if not non-interactive)
if [ "$NON_INTERACTIVE" = false ]; then
    echo -e "${BLUE}Adding client '${CLIENT_NAME}' to OpenTofu configuration${NC}"
    echo ""
    echo "Current defaults:"
    echo "  Server type: $SERVER_TYPE"
    echo "  Location: $LOCATION"
    echo "  Volume size: $VOLUME_SIZE GB"
    echo "  Apps: $APPS"
    echo ""
    read -p "Use these defaults? (yes/no): " use_defaults

    if [ "$use_defaults" != "yes" ]; then
        # Prompt for each value
        echo ""
        read -p "Server type [$SERVER_TYPE]: " input
        SERVER_TYPE="${input:-$SERVER_TYPE}"

        read -p "Location [$LOCATION]: " input
        LOCATION="${input:-$LOCATION}"

        read -p "Volume size GB [$VOLUME_SIZE]: " input
        VOLUME_SIZE="${input:-$VOLUME_SIZE}"

        read -p "Apps (comma-separated) [$APPS]: " input
        APPS="${input:-$APPS}"
    fi
fi

# Convert apps list to array format
APPS_ARRAY=$(echo "$APPS" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')

# Find the closing brace of the clients block
CLIENTS_CLOSE_LINE=$(grep -n "^}" "$TFVARS_FILE" | head -1 | cut -d: -f1)

if [ -z "$CLIENTS_CLOSE_LINE" ]; then
    echo -e "${RED}Error: Could not find closing brace in terraform.tfvars${NC}"
    exit 1
fi

# Create the new client configuration
NEW_CLIENT_CONFIG="
  # ${CLIENT_NAME} server
  ${CLIENT_NAME} = {
    server_type            = \"${SERVER_TYPE}\"
    location               = \"${LOCATION}\"
    subdomain              = \"${CLIENT_NAME}\"
    apps                   = ${APPS_ARRAY}
    nextcloud_volume_size  = ${VOLUME_SIZE}
  }"

# Create temporary file with new config inserted before closing brace
TMP_FILE=$(mktemp)
head -n $((CLIENTS_CLOSE_LINE - 1)) "$TFVARS_FILE" > "$TMP_FILE"
echo "$NEW_CLIENT_CONFIG" >> "$TMP_FILE"
tail -n +$CLIENTS_CLOSE_LINE "$TFVARS_FILE" >> "$TMP_FILE"

# Show the diff
echo ""
echo -e "${CYAN}Configuration to be added:${NC}"
echo "$NEW_CLIENT_CONFIG"
echo ""

# Confirm
if [ "$NON_INTERACTIVE" = false ]; then
    read -p "Add this configuration to terraform.tfvars? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        rm "$TMP_FILE"
        echo "Cancelled"
        exit 0
    fi
fi

# Apply changes
mv "$TMP_FILE" "$TFVARS_FILE"

echo ""
echo -e "${GREEN}✓ Client '${CLIENT_NAME}' added to terraform.tfvars${NC}"
echo ""
echo "Configuration added:"
echo "  Server: $SERVER_TYPE in $LOCATION"
echo "  Volume: $VOLUME_SIZE GB"
echo "  Apps: $APPS"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "1. Review changes: cat tofu/terraform.tfvars"
echo "2. Plan infrastructure: cd tofu && tofu plan"
echo "3. Apply infrastructure: cd tofu && tofu apply"
echo "4. Deploy services: ./scripts/deploy-client.sh $CLIENT_NAME"
echo ""
