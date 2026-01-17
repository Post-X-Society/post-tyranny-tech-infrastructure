#!/usr/bin/env bash
#
# Report software versions across all clients
#
# Usage: ./scripts/check-client-versions.sh [options]
#
# Options:
#   --format=table    Show as colorized table (default)
#   --format=csv      Export as CSV
#   --format=json     Export as JSON
#   --app=<name>      Filter by application (authentik|nextcloud|traefik|ubuntu)
#   --outdated        Show only clients with outdated versions

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

# Default options
FORMAT="table"
FILTER_APP=""
SHOW_OUTDATED=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --format=*)
            FORMAT="${arg#*=}"
            ;;
        --app=*)
            FILTER_APP="${arg#*=}"
            ;;
        --outdated)
            SHOW_OUTDATED=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--format=table|csv|json] [--app=<name>] [--outdated]"
            exit 1
            ;;
    esac
done

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

# Get list of clients
CLIENTS=$(yq eval '.clients | keys | .[]' "$REGISTRY_FILE" 2>/dev/null)

if [ -z "$CLIENTS" ]; then
    echo -e "${YELLOW}No clients found in registry${NC}"
    exit 0
fi

# Determine latest versions (from canary/dev or most common)
declare -A LATEST_VERSIONS
LATEST_VERSIONS[authentik]=$(yq eval '.clients | to_entries | .[].value.versions.authentik' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[nextcloud]=$(yq eval '.clients | to_entries | .[].value.versions.nextcloud' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[traefik]=$(yq eval '.clients | to_entries | .[].value.versions.traefik' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[ubuntu]=$(yq eval '.clients | to_entries | .[].value.versions.ubuntu' "$REGISTRY_FILE" | sort -V | tail -1)

# Function to check if version is outdated
is_outdated() {
    local app=$1
    local version=$2
    local latest=${LATEST_VERSIONS[$app]}

    if [ "$version" != "$latest" ] && [ "$version" != "null" ] && [ "$version" != "unknown" ]; then
        return 0
    else
        return 1
    fi
}

case $FORMAT in
    table)
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}                         CLIENT VERSION REPORT${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""

        # Header
        printf "${CYAN}%-15s %-15s %-15s %-15s %-15s %-15s${NC}\n" \
            "CLIENT" "STATUS" "AUTHENTIK" "NEXTCLOUD" "TRAEFIK" "UBUNTU"
        echo -e "${CYAN}$(printf '─%.0s' {1..90})${NC}"

        # Rows
        for client in $CLIENTS; do
            status=$(yq eval ".clients.\"$client\".status" "$REGISTRY_FILE")
            authentik=$(yq eval ".clients.\"$client\".versions.authentik" "$REGISTRY_FILE")
            nextcloud=$(yq eval ".clients.\"$client\".versions.nextcloud" "$REGISTRY_FILE")
            traefik=$(yq eval ".clients.\"$client\".versions.traefik" "$REGISTRY_FILE")
            ubuntu=$(yq eval ".clients.\"$client\".versions.ubuntu" "$REGISTRY_FILE")

            # Skip if filtering by outdated and not outdated
            if [ "$SHOW_OUTDATED" = true ]; then
                has_outdated=false
                is_outdated "authentik" "$authentik" && has_outdated=true
                is_outdated "nextcloud" "$nextcloud" && has_outdated=true
                is_outdated "traefik" "$traefik" && has_outdated=true
                is_outdated "ubuntu" "$ubuntu" && has_outdated=true

                if [ "$has_outdated" = false ]; then
                    continue
                fi
            fi

            # Colorize versions (red if outdated)
            authentik_color=$NC
            is_outdated "authentik" "$authentik" && authentik_color=$RED

            nextcloud_color=$NC
            is_outdated "nextcloud" "$nextcloud" && nextcloud_color=$RED

            traefik_color=$NC
            is_outdated "traefik" "$traefik" && traefik_color=$RED

            ubuntu_color=$NC
            is_outdated "ubuntu" "$ubuntu" && ubuntu_color=$RED

            # Status color
            status_color=$GREEN
            [ "$status" != "deployed" ] && status_color=$YELLOW

            printf "%-15s ${status_color}%-15s${NC} ${authentik_color}%-15s${NC} ${nextcloud_color}%-15s${NC} ${traefik_color}%-15s${NC} ${ubuntu_color}%-15s${NC}\n" \
                "$client" "$status" "$authentik" "$nextcloud" "$traefik" "$ubuntu"
        done

        echo ""
        echo -e "${CYAN}Latest versions:${NC}"
        echo "  Authentik: ${LATEST_VERSIONS[authentik]}"
        echo "  Nextcloud: ${LATEST_VERSIONS[nextcloud]}"
        echo "  Traefik:   ${LATEST_VERSIONS[traefik]}"
        echo "  Ubuntu:    ${LATEST_VERSIONS[ubuntu]}"
        echo ""
        echo -e "${YELLOW}Note: ${RED}Red${NC} indicates outdated version${NC}"
        echo ""
        ;;

    csv)
        # CSV header
        echo "client,status,authentik,nextcloud,traefik,ubuntu,last_update,outdated"

        # CSV rows
        for client in $CLIENTS; do
            status=$(yq eval ".clients.\"$client\".status" "$REGISTRY_FILE")
            authentik=$(yq eval ".clients.\"$client\".versions.authentik" "$REGISTRY_FILE")
            nextcloud=$(yq eval ".clients.\"$client\".versions.nextcloud" "$REGISTRY_FILE")
            traefik=$(yq eval ".clients.\"$client\".versions.traefik" "$REGISTRY_FILE")
            ubuntu=$(yq eval ".clients.\"$client\".versions.ubuntu" "$REGISTRY_FILE")
            last_update=$(yq eval ".clients.\"$client\".maintenance.last_full_update" "$REGISTRY_FILE")

            # Check if any version is outdated
            outdated="no"
            is_outdated "authentik" "$authentik" && outdated="yes"
            is_outdated "nextcloud" "$nextcloud" && outdated="yes"
            is_outdated "traefik" "$traefik" && outdated="yes"
            is_outdated "ubuntu" "$ubuntu" && outdated="yes"

            # Skip if filtering by outdated
            if [ "$SHOW_OUTDATED" = true ] && [ "$outdated" = "no" ]; then
                continue
            fi

            echo "$client,$status,$authentik,$nextcloud,$traefik,$ubuntu,$last_update,$outdated"
        done
        ;;

    json)
        # Build JSON array
        echo "{"
        echo "  \"latest_versions\": {"
        echo "    \"authentik\": \"${LATEST_VERSIONS[authentik]}\","
        echo "    \"nextcloud\": \"${LATEST_VERSIONS[nextcloud]}\","
        echo "    \"traefik\": \"${LATEST_VERSIONS[traefik]}\","
        echo "    \"ubuntu\": \"${LATEST_VERSIONS[ubuntu]}\""
        echo "  },"
        echo "  \"clients\": ["

        first=true
        for client in $CLIENTS; do
            status=$(yq eval ".clients.\"$client\".status" "$REGISTRY_FILE")
            authentik=$(yq eval ".clients.\"$client\".versions.authentik" "$REGISTRY_FILE")
            nextcloud=$(yq eval ".clients.\"$client\".versions.nextcloud" "$REGISTRY_FILE")
            traefik=$(yq eval ".clients.\"$client\".versions.traefik" "$REGISTRY_FILE")
            ubuntu=$(yq eval ".clients.\"$client\".versions.ubuntu" "$REGISTRY_FILE")
            last_update=$(yq eval ".clients.\"$client\".maintenance.last_full_update" "$REGISTRY_FILE")

            # Check if any version is outdated
            outdated=false
            is_outdated "authentik" "$authentik" && outdated=true
            is_outdated "nextcloud" "$nextcloud" && outdated=true
            is_outdated "traefik" "$traefik" && outdated=true
            is_outdated "ubuntu" "$ubuntu" && outdated=true

            # Skip if filtering by outdated
            if [ "$SHOW_OUTDATED" = true ] && [ "$outdated" = false ]; then
                continue
            fi

            if [ "$first" = false ]; then
                echo "    ,"
            fi
            first=false

            cat <<EOF
    {
      "name": "$client",
      "status": "$status",
      "versions": {
        "authentik": "$authentik",
        "nextcloud": "$nextcloud",
        "traefik": "$traefik",
        "ubuntu": "$ubuntu"
      },
      "last_update": "$last_update",
      "outdated": $outdated
    }
EOF
        done

        echo ""
        echo "  ]"
        echo "}"
        ;;

    *)
        echo -e "${RED}Error: Unknown format '$FORMAT'${NC}"
        echo "Valid formats: table, csv, json"
        exit 1
        ;;
esac
