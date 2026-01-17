#!/usr/bin/env bash
#
# Detect version drift between clients
#
# Usage: ./scripts/detect-version-drift.sh [options]
#
# Options:
#   --threshold=<days>   Only report clients not updated in X days (default: 30)
#   --app=<name>         Check specific app only (authentik|nextcloud|traefik|ubuntu)
#   --format=table       Show as table (default)
#   --format=summary     Show summary only
#
# Exit codes:
#   0 - No drift detected
#   1 - Drift detected
#   2 - Error

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
THRESHOLD_DAYS=30
FILTER_APP=""
FORMAT="table"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --threshold=*)
            THRESHOLD_DAYS="${arg#*=}"
            ;;
        --app=*)
            FILTER_APP="${arg#*=}"
            ;;
        --format=*)
            FORMAT="${arg#*=}"
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--threshold=<days>] [--app=<name>] [--format=table|summary]"
            exit 2
            ;;
    esac
done

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo -e "${RED}Error: 'yq' not found. Install with: brew install yq${NC}"
    exit 2
fi

# Check if registry exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: Registry file not found: $REGISTRY_FILE${NC}"
    exit 2
fi

# Get list of deployed clients only
CLIENTS=$(yq eval '.clients | to_entries | map(select(.value.status == "deployed")) | .[].key' "$REGISTRY_FILE" 2>/dev/null)

if [ -z "$CLIENTS" ]; then
    echo -e "${YELLOW}No deployed clients found${NC}"
    exit 0
fi

# Determine latest versions
declare -A LATEST_VERSIONS
LATEST_VERSIONS[authentik]=$(yq eval '.clients | to_entries | .[].value.versions.authentik' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[nextcloud]=$(yq eval '.clients | to_entries | .[].value.versions.nextcloud' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[traefik]=$(yq eval '.clients | to_entries | .[].value.versions.traefik' "$REGISTRY_FILE" | sort -V | tail -1)
LATEST_VERSIONS[ubuntu]=$(yq eval '.clients | to_entries | .[].value.versions.ubuntu' "$REGISTRY_FILE" | sort -V | tail -1)

# Calculate date threshold
if command -v gdate &> /dev/null; then
    # macOS with GNU coreutils
    THRESHOLD_DATE=$(gdate -d "$THRESHOLD_DAYS days ago" +%Y-%m-%d)
elif date --version &> /dev/null 2>&1; then
    # GNU date (Linux)
    THRESHOLD_DATE=$(date -d "$THRESHOLD_DAYS days ago" +%Y-%m-%d)
else
    # BSD date (macOS default)
    THRESHOLD_DATE=$(date -v-${THRESHOLD_DAYS}d +%Y-%m-%d)
fi

# Counters
DRIFT_FOUND=0
OUTDATED_COUNT=0
STALE_COUNT=0

# Arrays to store drift details
declare -a DRIFT_CLIENTS
declare -a DRIFT_DETAILS

# Analyze each client
for client in $CLIENTS; do
    authentik=$(yq eval ".clients.\"$client\".versions.authentik" "$REGISTRY_FILE")
    nextcloud=$(yq eval ".clients.\"$client\".versions.nextcloud" "$REGISTRY_FILE")
    traefik=$(yq eval ".clients.\"$client\".versions.traefik" "$REGISTRY_FILE")
    ubuntu=$(yq eval ".clients.\"$client\".versions.ubuntu" "$REGISTRY_FILE")
    last_update=$(yq eval ".clients.\"$client\".maintenance.last_full_update" "$REGISTRY_FILE")

    has_drift=false
    drift_reasons=()

    # Check version drift
    if [ -z "$FILTER_APP" ] || [ "$FILTER_APP" = "authentik" ]; then
        if [ "$authentik" != "${LATEST_VERSIONS[authentik]}" ] && [ "$authentik" != "null" ] && [ "$authentik" != "unknown" ]; then
            has_drift=true
            drift_reasons+=("Authentik: $authentik → ${LATEST_VERSIONS[authentik]}")
        fi
    fi

    if [ -z "$FILTER_APP" ] || [ "$FILTER_APP" = "nextcloud" ]; then
        if [ "$nextcloud" != "${LATEST_VERSIONS[nextcloud]}" ] && [ "$nextcloud" != "null" ] && [ "$nextcloud" != "unknown" ]; then
            has_drift=true
            drift_reasons+=("Nextcloud: $nextcloud → ${LATEST_VERSIONS[nextcloud]}")
        fi
    fi

    if [ -z "$FILTER_APP" ] || [ "$FILTER_APP" = "traefik" ]; then
        if [ "$traefik" != "${LATEST_VERSIONS[traefik]}" ] && [ "$traefik" != "null" ] && [ "$traefik" != "unknown" ]; then
            has_drift=true
            drift_reasons+=("Traefik: $traefik → ${LATEST_VERSIONS[traefik]}")
        fi
    fi

    if [ -z "$FILTER_APP" ] || [ "$FILTER_APP" = "ubuntu" ]; then
        if [ "$ubuntu" != "${LATEST_VERSIONS[ubuntu]}" ] && [ "$ubuntu" != "null" ] && [ "$ubuntu" != "unknown" ]; then
            has_drift=true
            drift_reasons+=("Ubuntu: $ubuntu → ${LATEST_VERSIONS[ubuntu]}")
        fi
    fi

    # Check if update is stale (older than threshold)
    is_stale=false
    if [ "$last_update" != "null" ] && [ -n "$last_update" ]; then
        if [[ "$last_update" < "$THRESHOLD_DATE" ]]; then
            is_stale=true
            drift_reasons+=("Last update: $last_update (>$THRESHOLD_DAYS days ago)")
        fi
    fi

    # Record drift
    if [ "$has_drift" = true ] || [ "$is_stale" = true ]; then
        DRIFT_FOUND=1
        DRIFT_CLIENTS+=("$client")
        DRIFT_DETAILS+=("$(IFS='; '; echo "${drift_reasons[*]}")")

        [ "$has_drift" = true ] && ((OUTDATED_COUNT++)) || true
        [ "$is_stale" = true ] && ((STALE_COUNT++)) || true
    fi
done

# Output results
case $FORMAT in
    table)
        if [ $DRIFT_FOUND -eq 0 ]; then
            echo -e "${GREEN}✓ No version drift detected${NC}"
            echo ""
            echo "All deployed clients are running latest versions:"
            echo "  Authentik: ${LATEST_VERSIONS[authentik]}"
            echo "  Nextcloud: ${LATEST_VERSIONS[nextcloud]}"
            echo "  Traefik:   ${LATEST_VERSIONS[traefik]}"
            echo "  Ubuntu:    ${LATEST_VERSIONS[ubuntu]}"
            echo ""
        else
            echo -e "${RED}⚠ VERSION DRIFT DETECTED${NC}"
            echo ""
            echo -e "${CYAN}Clients with outdated versions:${NC}"
            echo ""

            for i in "${!DRIFT_CLIENTS[@]}"; do
                client="${DRIFT_CLIENTS[$i]}"
                details="${DRIFT_DETAILS[$i]}"

                echo -e "${YELLOW}• $client${NC}"
                IFS=';' read -ra REASONS <<< "$details"
                for reason in "${REASONS[@]}"; do
                    echo "    $reason"
                done
                echo ""
            done

            echo -e "${CYAN}Recommended actions:${NC}"
            echo ""
            echo "1. Test updates on canary server first:"
            echo "   ${BLUE}./scripts/rebuild-client.sh dev${NC}"
            echo ""
            echo "2. Verify canary health:"
            echo "   ${BLUE}./scripts/client-status.sh dev${NC}"
            echo ""
            echo "3. Update outdated clients:"
            for client in "${DRIFT_CLIENTS[@]}"; do
                echo "   ${BLUE}./scripts/rebuild-client.sh $client${NC}"
            done
            echo ""
        fi
        ;;

    summary)
        if [ $DRIFT_FOUND -eq 0 ]; then
            echo "Status: OK"
            echo "Drift: No"
            echo "Clients checked: $(echo "$CLIENTS" | wc -l | xargs)"
        else
            echo "Status: DRIFT DETECTED"
            echo "Drift: Yes"
            echo "Clients checked: $(echo "$CLIENTS" | wc -l | xargs)"
            echo "Clients with outdated versions: $OUTDATED_COUNT"
            echo "Clients not updated in $THRESHOLD_DAYS days: $STALE_COUNT"
            echo "Affected clients: ${DRIFT_CLIENTS[*]}"
        fi
        ;;
esac

exit $DRIFT_FOUND
