#!/usr/bin/env bash
#
# Resize a client's Nextcloud data volume
#
# Usage: ./scripts/resize-client-volume.sh <client_name> <new_size_gb>
#
# This script will:
# 1. Resize the Hetzner Volume via API
# 2. Expand the filesystem on the server
# 3. Verify the new size
#
# Note: Volumes can only be increased in size, never decreased

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
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Client name and new size required${NC}"
    echo "Usage: $0 <client_name> <new_size_gb>"
    echo ""
    echo "Example: $0 dev 200"
    echo ""
    echo "Note: You can only INCREASE volume size, never decrease"
    exit 1
fi

CLIENT_NAME="$1"
NEW_SIZE="$2"

# Validate new size is a number
if ! [[ "$NEW_SIZE" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Size must be a number${NC}"
    exit 1
fi

# Check minimum size
if [ "$NEW_SIZE" -lt 10 ]; then
    echo -e "${RED}Error: Minimum volume size is 10 GB${NC}"
    exit 1
fi

# Check maximum size
if [ "$NEW_SIZE" -gt 10000 ]; then
    echo -e "${RED}Error: Maximum volume size is 10,000 GB (10 TB)${NC}"
    exit 1
fi

# Check required environment variables
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo -e "${RED}Error: HCLOUD_TOKEN environment variable not set${NC}"
    echo "Export your Hetzner Cloud API token:"
    echo "  export HCLOUD_TOKEN='your-token-here'"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Resizing Nextcloud Volume${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Client: $CLIENT_NAME"
echo "New size: ${NEW_SIZE} GB"
echo ""

# Step 1: Get volume ID from Hetzner API
echo -e "${YELLOW}[1/4] Looking up volume...${NC}"

VOLUME_NAME="nextcloud-data-${CLIENT_NAME}"

# Get volume info
VOLUME_INFO=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/volumes?name=$VOLUME_NAME")

VOLUME_ID=$(echo "$VOLUME_INFO" | jq -r '.volumes[0].id // empty')
CURRENT_SIZE=$(echo "$VOLUME_INFO" | jq -r '.volumes[0].size // empty')

if [ -z "$VOLUME_ID" ] || [ "$VOLUME_ID" = "null" ]; then
    echo -e "${RED}Error: Volume '$VOLUME_NAME' not found${NC}"
    echo "Make sure the client exists and has been deployed with volume support"
    exit 1
fi

echo "Volume ID: $VOLUME_ID"
echo "Current size: ${CURRENT_SIZE} GB"
echo ""

# Check if new size is larger
if [ "$NEW_SIZE" -le "$CURRENT_SIZE" ]; then
    echo -e "${RED}Error: New size ($NEW_SIZE GB) must be larger than current size ($CURRENT_SIZE GB)${NC}"
    echo "Volumes can only be increased in size, never decreased"
    exit 1
fi

# Calculate cost increase
COST_INCREASE=$(echo "scale=2; ($NEW_SIZE - $CURRENT_SIZE) * 0.054" | bc)

echo -e "${YELLOW}Warning: This will increase monthly costs by approximately €${COST_INCREASE}${NC}"
echo ""
read -p "Continue with resize? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Resize cancelled"
    exit 0
fi

echo ""

# Step 2: Resize volume via API
echo -e "${YELLOW}[2/4] Resizing volume via Hetzner API...${NC}"

RESIZE_RESULT=$(curl -s -X POST \
    -H "Authorization: Bearer $HCLOUD_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"size\": $NEW_SIZE}" \
    "https://api.hetzner.cloud/v1/volumes/$VOLUME_ID/actions/resize")

ACTION_ID=$(echo "$RESIZE_RESULT" | jq -r '.action.id // empty')

if [ -z "$ACTION_ID" ] || [ "$ACTION_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to resize volume${NC}"
    echo "$RESIZE_RESULT" | jq .
    exit 1
fi

# Wait for resize action to complete
echo "Waiting for resize action to complete..."
while true; do
    ACTION_STATUS=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/volumes/actions/$ACTION_ID" | jq -r '.action.status')

    if [ "$ACTION_STATUS" = "success" ]; then
        break
    elif [ "$ACTION_STATUS" = "error" ]; then
        echo -e "${RED}Error: Resize action failed${NC}"
        exit 1
    fi

    sleep 2
done

echo -e "${GREEN}✓ Volume resized${NC}"
echo ""

# Step 3: Expand filesystem on the server
echo -e "${YELLOW}[3/4] Expanding filesystem on server...${NC}"

cd "$PROJECT_ROOT/ansible"

# Find the device
DEVICE_CMD="ls -1 /dev/disk/by-id/scsi-0HC_Volume_* 2>/dev/null | grep -i 'nextcloud-data-${CLIENT_NAME}' | head -1"
DEVICE=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "$DEVICE_CMD" -o 2>/dev/null | tail -1 | awk '{print $NF}')

if [ -z "$DEVICE" ]; then
    echo -e "${RED}Error: Could not find volume device on server${NC}"
    exit 1
fi

echo "Device: $DEVICE"

# Resize filesystem
~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "resize2fs $DEVICE" -b

echo -e "${GREEN}✓ Filesystem expanded${NC}"
echo ""

# Step 4: Verify new size
echo -e "${YELLOW}[4/4] Verifying new size...${NC}"

DF_OUTPUT=$(~/.local/bin/ansible -i hcloud.yml "$CLIENT_NAME" -m shell -a "df -h /mnt/nextcloud-data" -o 2>/dev/null | tail -1)

echo "$DF_OUTPUT"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Resize complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Volume resized from ${CURRENT_SIZE} GB to ${NEW_SIZE} GB"
echo "Additional monthly cost: €${COST_INCREASE}"
echo ""
echo "The new storage is immediately available to Nextcloud."
echo ""
