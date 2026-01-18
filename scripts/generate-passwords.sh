#!/usr/bin/env bash
#
# Generate secure random passwords and tokens for a client
# Usage: ./generate-passwords.sh <client-name>
#
# This script generates unique credentials for each client and updates their SOPS-encrypted secrets file.
# All passwords are cryptographically secure (43 characters, base64-encoded random data).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function to generate a secure random password/token
generate_password() {
    # Generate 32 random bytes and encode as base64, removing padding and special chars
    openssl rand -base64 32 | tr -d '\n=' | head -c 43
}

# Function to generate an API token (with ak_ prefix for Authentik)
generate_api_token() {
    echo "ak_$(openssl rand -base64 32 | tr -d '\n=' | head -c 46)"
}

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

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}Password Generator for Client: ${CLIENT_NAME}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""

    # Check if secrets file exists
    if [ ! -f "$SECRETS_FILE" ]; then
        echo -e "${RED}Error: Secrets file not found: $SECRETS_FILE${NC}"
        echo ""
        echo "Create the secrets file first with:"
        echo "  ./scripts/deploy-client.sh $CLIENT_NAME"
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

    echo -e "${GREEN}Generating unique passwords for ${CLIENT_NAME}...${NC}"
    echo ""

    # Generate all passwords
    AUTHENTIK_BOOTSTRAP_PASSWORD=$(generate_password)
    AUTHENTIK_BOOTSTRAP_TOKEN=$(generate_api_token)
    AUTHENTIK_SECRET_KEY=$(generate_password)
    AUTHENTIK_DB_PASSWORD=$(generate_password)
    NEXTCLOUD_ADMIN_PASSWORD=$(generate_password)
    NEXTCLOUD_DB_PASSWORD=$(generate_password)

    echo "Generated credentials:"
    echo "  ✓ Authentik bootstrap password (43 chars)"
    echo "  ✓ Authentik bootstrap token (49 chars with ak_ prefix)"
    echo "  ✓ Authentik secret key (43 chars)"
    echo "  ✓ Authentik database password (43 chars)"
    echo "  ✓ Nextcloud admin password (43 chars)"
    echo "  ✓ Nextcloud database password (43 chars)"
    echo ""

    # Create a temporary decrypted file
    TEMP_PLAIN=$(mktemp)
    sops -d "$SECRETS_FILE" > "$TEMP_PLAIN"

    # Update passwords in the decrypted file
    # Using perl for in-place editing because it handles special characters better
    perl -pi -e "s|^(authentik_bootstrap_password:).*|\$1 $AUTHENTIK_BOOTSTRAP_PASSWORD|" "$TEMP_PLAIN"
    perl -pi -e "s|^(authentik_bootstrap_token:).*|\$1 $AUTHENTIK_BOOTSTRAP_TOKEN|" "$TEMP_PLAIN"
    perl -pi -e "s|^(authentik_secret_key:).*|\$1 $AUTHENTIK_SECRET_KEY|" "$TEMP_PLAIN"
    perl -pi -e "s|^(authentik_db_password:).*|\$1 $AUTHENTIK_DB_PASSWORD|" "$TEMP_PLAIN"
    perl -pi -e "s|^(nextcloud_admin_password:).*|\$1 $NEXTCLOUD_ADMIN_PASSWORD|" "$TEMP_PLAIN"
    perl -pi -e "s|^(nextcloud_db_password:).*|\$1 $NEXTCLOUD_DB_PASSWORD|" "$TEMP_PLAIN"

    # Re-encrypt the file
    # We need to use a temp file that matches the .sops.yaml creation rules
    TEMP_SOPS="${SECRETS_FILE%.sops.yaml}-temp.sops.yaml"
    cp "$TEMP_PLAIN" "$TEMP_SOPS"

    # Encrypt in place
    sops --encrypt --in-place "$TEMP_SOPS"

    # Replace original file
    mv "$TEMP_SOPS" "$SECRETS_FILE"

    # Cleanup
    rm "$TEMP_PLAIN"

    echo -e "${GREEN}✓ Updated $SECRETS_FILE with unique passwords${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Passwords are now stored encrypted in SOPS.${NC}"
    echo ""
    echo "To view passwords:"
    echo -e "  ${BLUE}SOPS_AGE_KEY_FILE=\"keys/age-key.txt\" sops -d secrets/clients/${CLIENT_NAME}.sops.yaml${NC}"
    echo ""
    echo "Or use the retrieval script:"
    echo -e "  ${BLUE}./scripts/get-passwords.sh ${CLIENT_NAME}${NC}"
    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}Password generation complete!${NC}"
    echo -e "${GREEN}==================================================${NC}"
}

main "$@"
