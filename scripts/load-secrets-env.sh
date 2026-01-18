#!/usr/bin/env bash
#
# Load secrets from SOPS into environment variables
#
# Usage: source scripts/load-secrets-env.sh
#
# This script loads the Hetzner API token from SOPS-encrypted secrets
# and exports it as both:
#   - HCLOUD_TOKEN (for Ansible dynamic inventory)
#   - TF_VAR_hcloud_token (for OpenTofu)
#   - TF_VAR_hetznerdns_token (for OpenTofu DNS provider)

# Determine script directory
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Set SOPS key file if not already set
if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
    export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
fi

# Check if SOPS key file exists
if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
    echo "Error: SOPS Age key not found at: $SOPS_AGE_KEY_FILE" >&2
    return 1 2>/dev/null || exit 1
fi

# Load token from SOPS
SHARED_SECRETS="$PROJECT_ROOT/secrets/shared.sops.yaml"

if [ ! -f "$SHARED_SECRETS" ]; then
    echo "Error: Shared secrets file not found: $SHARED_SECRETS" >&2
    return 1 2>/dev/null || exit 1
fi

# Extract hcloud_token
HCLOUD_TOKEN=$(sops -d "$SHARED_SECRETS" | grep "^hcloud_token:" | awk '{print $2}')

if [ -z "$HCLOUD_TOKEN" ]; then
    echo "Error: Could not extract hcloud_token from secrets" >&2
    return 1 2>/dev/null || exit 1
fi

# Export for Ansible (dynamic inventory)
export HCLOUD_TOKEN

# Export for OpenTofu
export TF_VAR_hcloud_token="$HCLOUD_TOKEN"
export TF_VAR_hetznerdns_token="$HCLOUD_TOKEN"

echo "✓ Loaded Hetzner API token from SOPS"
echo "  • HCLOUD_TOKEN (for Ansible)"
echo "  • TF_VAR_hcloud_token (for OpenTofu)"
echo "  • TF_VAR_hetznerdns_token (for OpenTofu DNS)"
