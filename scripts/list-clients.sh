#!/usr/bin/env bash
#
# List all clients from the registry
#
# Usage: ./scripts/list-clients.sh [--status=<status>] [--role=<role>] [--format=<format>]
#
# Options:
#   --status=<status>  Filter by status (deployed, pending, maintenance, offboarding, destroyed)
#   --role=<role>      Filter by role (canary, production)
#   --format=<format>  Output format: table (default), json, csv, summary
#
# Examples:
#   ./scripts/list-clients.sh                          # List all clients
#   ./scripts/list-clients.sh --status=deployed        # Only deployed clients
#   ./scripts/list-clients.sh --role=production        # Only production clients
#   ./scripts/list-clients.sh --format=json            # JSON output

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REGISTRY_FILE="$PROJECT_ROOT/clients/registry.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
FILTER_STATUS=""
FILTER_ROLE=""
FORMAT="table"

for arg in "$@"; do
    case $arg in
        --status=*)
            FILTER_STATUS="${arg#*=}"
            ;;
        --role=*)
            FILTER_ROLE="${arg#*=}"
            ;;
        --format=*)
            FORMAT="${arg#*=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--status=<status>] [--role=<role>] [--format=<format>]"
            echo ""
            echo "Options:"
            echo "  --status=<status>  Filter by status (deployed, pending, maintenance, offboarding, destroyed)"
            echo "  --role=<role>      Filter by role (canary, production)"
            echo "  --format=<format>  Output format: table (default), json, csv, summary"
            exit 0
            ;;
    esac
done

# Check if registry exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: Registry file not found: $REGISTRY_FILE${NC}"
    exit 1
fi

# Check if yq is available (for YAML parsing)
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}Warning: 'yq' not found. Install with: brew install yq${NC}"
    echo "Falling back to basic grep parsing..."
    USE_YQ=false
else
    USE_YQ=true
fi

# Function to get clients using yq
list_clients_yq() {
    local clients=$(yq eval '.clients | keys | .[]' "$REGISTRY_FILE")

    for client in $clients; do
        local status=$(yq eval ".clients.\"$client\".status" "$REGISTRY_FILE")
        local role=$(yq eval ".clients.\"$client\".role" "$REGISTRY_FILE")

        # Apply filters
        if [ -n "$FILTER_STATUS" ] && [ "$status" != "$FILTER_STATUS" ]; then
            continue
        fi
        if [ -n "$FILTER_ROLE" ] && [ "$role" != "$FILTER_ROLE" ]; then
            continue
        fi

        # Get other fields
        local deployed_date=$(yq eval ".clients.\"$client\".deployed_date" "$REGISTRY_FILE")
        local server_ip=$(yq eval ".clients.\"$client\".server.ip" "$REGISTRY_FILE")
        local server_type=$(yq eval ".clients.\"$client\".server.type" "$REGISTRY_FILE")
        local apps=$(yq eval ".clients.\"$client\".apps | join(\", \")" "$REGISTRY_FILE")

        echo "$client|$status|$role|$deployed_date|$server_type|$server_ip|$apps"
    done
}

# Function to output in table format
output_table() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                              CLIENT REGISTRY                                       ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════╣${NC}"

    printf "${CYAN}%-15s ${GREEN}%-12s ${YELLOW}%-10s ${NC}%-12s %-10s %-15s %-20s\n" \
        "CLIENT" "STATUS" "ROLE" "DEPLOYED" "TYPE" "IP" "APPS"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"

    local count=0
    while IFS='|' read -r client status role deployed_date server_type server_ip apps; do
        # Color status
        local status_color=$NC
        case $status in
            deployed) status_color=$GREEN ;;
            pending) status_color=$YELLOW ;;
            maintenance) status_color=$CYAN ;;
            offboarding) status_color=$RED ;;
            destroyed) status_color=$RED ;;
        esac

        # Color role
        local role_color=$NC
        case $role in
            canary) role_color=$YELLOW ;;
            production) role_color=$GREEN ;;
        esac

        printf "%-15s ${status_color}%-12s${NC} ${role_color}%-10s${NC} %-12s %-10s %-15s %-20s\n" \
            "$client" "$status" "$role" "$deployed_date" "$server_type" "$server_ip" "${apps:0:20}"
        ((count++))
    done

    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}║${NC} Total clients: $count                                                                    ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Function to output summary
output_summary() {
    local total=0
    local deployed=0
    local pending=0
    local maintenance=0
    local canary=0
    local production=0

    while IFS='|' read -r client status role deployed_date server_type server_ip apps; do
        ((total++))
        case $status in
            deployed) ((deployed++)) ;;
            pending) ((pending++)) ;;
            maintenance) ((maintenance++)) ;;
        esac
        case $role in
            canary) ((canary++)) ;;
            production) ((production++)) ;;
        esac
    done

    echo -e "${BLUE}═══════════════════════════════════${NC}"
    echo -e "${BLUE}    CLIENT REGISTRY SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════${NC}"
    echo ""
    echo -e "Total Clients:     ${CYAN}$total${NC}"
    echo ""
    echo -e "By Status:"
    echo -e "  Deployed:        ${GREEN}$deployed${NC}"
    echo -e "  Pending:         ${YELLOW}$pending${NC}"
    echo -e "  Maintenance:     ${CYAN}$maintenance${NC}"
    echo ""
    echo -e "By Role:"
    echo -e "  Canary:          ${YELLOW}$canary${NC}"
    echo -e "  Production:      ${GREEN}$production${NC}"
    echo ""
}

# Function to output JSON
output_json() {
    if $USE_YQ; then
        yq eval -o=json '.clients' "$REGISTRY_FILE"
    else
        echo "{}"
    fi
}

# Function to output CSV
output_csv() {
    echo "client,status,role,deployed_date,server_type,server_ip,apps"
    while IFS='|' read -r client status role deployed_date server_type server_ip apps; do
        echo "$client,$status,$role,$deployed_date,$server_type,$server_ip,\"$apps\""
    done
}

# Main execution
if $USE_YQ; then
    DATA=$(list_clients_yq)
else
    echo -e "${RED}Error: yq is required for this script${NC}"
    echo "Install with: brew install yq"
    exit 1
fi

# Check if any clients found
if [ -z "$DATA" ]; then
    echo -e "${YELLOW}No clients found matching criteria${NC}"
    exit 0
fi

# Output based on format
case $FORMAT in
    table)
        echo "$DATA" | output_table
        ;;
    json)
        output_json
        ;;
    csv)
        echo "$DATA" | output_csv
        ;;
    summary)
        echo "$DATA" | output_summary
        ;;
    *)
        echo -e "${RED}Unknown format: $FORMAT${NC}"
        echo "Valid formats: table, json, csv, summary"
        exit 1
        ;;
esac
