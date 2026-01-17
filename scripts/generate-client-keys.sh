#!/usr/bin/env bash
#
# Generate SSH key pair for a client
#
# Usage: ./scripts/generate-client-keys.sh <client_name>
#
# This script generates a dedicated ED25519 SSH key pair for a client,
# ensuring proper isolation between client servers.

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
KEY_DIR="$PROJECT_ROOT/keys/ssh"

# Check arguments
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Client name required${NC}"
    echo "Usage: $0 <client_name>"
    echo ""
    echo "Example: $0 newclient"
    exit 1
fi

CLIENT_NAME="$1"

# Validate client name (alphanumeric and hyphens only)
if ! [[ "$CLIENT_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}Error: Invalid client name${NC}"
    echo "Client name must contain only lowercase letters, numbers, and hyphens"
    exit 1
fi

# Check if key already exists
if [ -f "$KEY_DIR/$CLIENT_NAME" ]; then
    echo -e "${YELLOW}⚠ Warning: SSH key already exists for client: $CLIENT_NAME${NC}"
    echo ""
    echo "Existing key: $KEY_DIR/$CLIENT_NAME"
    echo ""
    read -p "Overwrite existing key? This will break SSH access to the server! [yes/NO] " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted"
        exit 1
    fi
    echo ""
fi

# Create keys directory if it doesn't exist
mkdir -p "$KEY_DIR"

echo -e "${BLUE}Generating SSH key pair for client: $CLIENT_NAME${NC}"
echo ""

# Generate ED25519 key pair
ssh-keygen -t ed25519 \
  -f "$KEY_DIR/$CLIENT_NAME" \
  -C "client-$CLIENT_NAME-deploy-key" \
  -N ""

echo ""
echo -e "${GREEN}✓ SSH key pair generated successfully${NC}"
echo ""
echo "Private key: $KEY_DIR/$CLIENT_NAME"
echo "Public key:  $KEY_DIR/$CLIENT_NAME.pub"
echo ""
echo "Key fingerprint:"
ssh-keygen -lf "$KEY_DIR/$CLIENT_NAME.pub"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Add client to tofu/terraform.tfvars"
echo "2. Apply OpenTofu: cd tofu && tofu apply"
echo "3. Deploy client: ./scripts/deploy-client.sh $CLIENT_NAME"
echo ""
echo -e "${YELLOW}⚠ IMPORTANT: Backup this key securely!${NC}"
echo "   Store in password manager or secure backup location"
echo ""
