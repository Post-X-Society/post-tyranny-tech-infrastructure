#!/bin/bash
# Get admin access token from Zitadel using username/password authentication
# This is used for initial OIDC app provisioning automation

set -e

DOMAIN="$1"
USERNAME="$2"
PASSWORD="$3"

if [ -z "$DOMAIN" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <domain> <username> <password>" >&2
    exit 1
fi

# Get OAuth token using Resource Owner Password Credentials flow
# Note: This is only for admin automation, not recommended for production apps
RESPONSE=$(curl -s -X POST "https://${DOMAIN}/oauth/v2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "scope=openid profile email urn:zitadel:iam:org:project:id:zitadel:aud" \
    -d "username=${USERNAME}" \
    -d "password=${PASSWORD}")

# Extract access token
ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))")

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to get access token" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

echo "$ACCESS_TOKEN"
