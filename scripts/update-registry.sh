#!/usr/bin/env bash
#
# Update the client registry with deployment information
#
# Usage: ./scripts/update-registry.sh <client_name> <action> [options]
#
# Actions:
#   deploy    - Mark client as deployed (creates/updates entry)
#   destroy   - Mark client as destroyed
#   status    - Update status field
#
# Options:
#   --status=<status>          Set status (pending|deployed|maintenance|offboarding|destroyed)
#   --role=<role>              Set role (canary|production)
#   --server-ip=<ip>           Set server IP
#   --server-id=<id>           Set server ID
#   --server-type=<type>       Set server type
#   --server-location=<loc>    Set server location

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REGISTRY_FILE="$PROJECT_ROOT/clients/registry.yml"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: 'yq' not found. Install with: brew install yq"
    exit 1
fi

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <client_name> <action> [options]"
    exit 1
fi

CLIENT_NAME="$1"
ACTION="$2"
shift 2

# Parse options
STATUS=""
ROLE=""
SERVER_IP=""
SERVER_ID=""
SERVER_TYPE=""
SERVER_LOCATION=""

for arg in "$@"; do
    case $arg in
        --status=*)
            STATUS="${arg#*=}"
            ;;
        --role=*)
            ROLE="${arg#*=}"
            ;;
        --server-ip=*)
            SERVER_IP="${arg#*=}"
            ;;
        --server-id=*)
            SERVER_ID="${arg#*=}"
            ;;
        --server-type=*)
            SERVER_TYPE="${arg#*=}"
            ;;
        --server-location=*)
            SERVER_LOCATION="${arg#*=}"
            ;;
    esac
done

# Ensure registry file exists
if [ ! -f "$REGISTRY_FILE" ]; then
    cat > "$REGISTRY_FILE" <<'EOF'
# Client Registry
#
# Single source of truth for all clients in the infrastructure.

clients: {}
EOF
fi

TODAY=$(date +%Y-%m-%d)

case $ACTION in
    deploy)
        # Check if client exists
        if yq eval ".clients.\"$CLIENT_NAME\"" "$REGISTRY_FILE" | grep -q "null"; then
            # Create new client entry
            echo "Creating new registry entry for $CLIENT_NAME"

            # Start with minimal structure
            yq eval -i ".clients.\"$CLIENT_NAME\" = {}" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".status = \"deployed\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".deployed_date = \"$TODAY\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".destroyed_date = null" "$REGISTRY_FILE"

            # Add role
            if [ -n "$ROLE" ]; then
                yq eval -i ".clients.\"$CLIENT_NAME\".role = \"$ROLE\"" "$REGISTRY_FILE"
            else
                yq eval -i ".clients.\"$CLIENT_NAME\".role = \"production\"" "$REGISTRY_FILE"
            fi

            # Add server info
            yq eval -i ".clients.\"$CLIENT_NAME\".server = {}" "$REGISTRY_FILE"
            [ -n "$SERVER_TYPE" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.type = \"$SERVER_TYPE\"" "$REGISTRY_FILE"
            [ -n "$SERVER_LOCATION" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.location = \"$SERVER_LOCATION\"" "$REGISTRY_FILE"
            [ -n "$SERVER_IP" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.ip = \"$SERVER_IP\"" "$REGISTRY_FILE"
            [ -n "$SERVER_ID" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.id = \"$SERVER_ID\"" "$REGISTRY_FILE"

            # Add apps
            yq eval -i ".clients.\"$CLIENT_NAME\".apps = [\"authentik\", \"nextcloud\"]" "$REGISTRY_FILE"

            # Add maintenance tracking
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance = {}" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance.last_full_update = \"$TODAY\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance.last_security_patch = \"$TODAY\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance.last_os_update = \"$TODAY\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance.last_backup_verified = null" "$REGISTRY_FILE"

            # Add URLs (will be determined from secrets file)
            yq eval -i ".clients.\"$CLIENT_NAME\".urls = {}" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".urls.authentik = \"https://auth.$CLIENT_NAME.vrije.cloud\"" "$REGISTRY_FILE"
            yq eval -i ".clients.\"$CLIENT_NAME\".urls.nextcloud = \"https://nextcloud.$CLIENT_NAME.vrije.cloud\"" "$REGISTRY_FILE"

            # Add notes
            yq eval -i ".clients.\"$CLIENT_NAME\".notes = \"\"" "$REGISTRY_FILE"
        else
            # Update existing client
            echo "Updating registry entry for $CLIENT_NAME"

            yq eval -i ".clients.\"$CLIENT_NAME\".status = \"deployed\"" "$REGISTRY_FILE"

            # Update server info if provided
            [ -n "$SERVER_IP" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.ip = \"$SERVER_IP\"" "$REGISTRY_FILE"
            [ -n "$SERVER_ID" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.id = \"$SERVER_ID\"" "$REGISTRY_FILE"
            [ -n "$SERVER_TYPE" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.type = \"$SERVER_TYPE\"" "$REGISTRY_FILE"
            [ -n "$SERVER_LOCATION" ] && yq eval -i ".clients.\"$CLIENT_NAME\".server.location = \"$SERVER_LOCATION\"" "$REGISTRY_FILE"

            # Update maintenance date
            yq eval -i ".clients.\"$CLIENT_NAME\".maintenance.last_full_update = \"$TODAY\"" "$REGISTRY_FILE"
        fi
        ;;

    destroy)
        echo "Marking $CLIENT_NAME as destroyed in registry"

        if yq eval ".clients.\"$CLIENT_NAME\"" "$REGISTRY_FILE" | grep -q "null"; then
            echo "Warning: Client $CLIENT_NAME not found in registry"
            exit 0
        fi

        yq eval -i ".clients.\"$CLIENT_NAME\".status = \"destroyed\"" "$REGISTRY_FILE"
        yq eval -i ".clients.\"$CLIENT_NAME\".destroyed_date = \"$TODAY\"" "$REGISTRY_FILE"
        ;;

    status)
        if [ -z "$STATUS" ]; then
            echo "Error: --status=<status> required for status action"
            exit 1
        fi

        echo "Updating status of $CLIENT_NAME to $STATUS"

        if yq eval ".clients.\"$CLIENT_NAME\"" "$REGISTRY_FILE" | grep -q "null"; then
            echo "Error: Client $CLIENT_NAME not found in registry"
            exit 1
        fi

        yq eval -i ".clients.\"$CLIENT_NAME\".status = \"$STATUS\"" "$REGISTRY_FILE"
        ;;

    *)
        echo "Error: Unknown action '$ACTION'"
        echo "Valid actions: deploy, destroy, status"
        exit 1
        ;;
esac

echo "✓ Registry updated successfully"
