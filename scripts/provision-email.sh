#!/usr/bin/env bash
#
# Provision a new email address for a client
#
# Usage: ./scripts/provision-email.sh <client_name>
#
# This script helps provision email addresses for clients using the configured
# email provider. Supports Mailgun and manual DNS setup.
#
# Prerequisites:
# - SMTP configuration in secrets/shared.sops.yaml
# - DNS access to vrije.cloud domain
# - For Mailgun: MAILGUN_API_KEY environment variable
#

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
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Client name required${NC}"
    echo "Usage: $0 <client_name>"
    echo ""
    echo "Example: $0 mycompany"
    exit 1
fi

CLIENT_NAME="$1"
EMAIL_DOMAIN="vrije.cloud"
CLIENT_EMAIL="${CLIENT_NAME}@${EMAIL_DOMAIN}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Provisioning email for: ${CLIENT_NAME}${NC}"
echo -e "${BLUE}Email address: ${CLIENT_EMAIL}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check for SOPS key
if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
    export SOPS_AGE_KEY_FILE="$PROJECT_ROOT/keys/age-key.txt"
fi

# Check if shared secrets exist
SHARED_SECRETS="$PROJECT_ROOT/secrets/shared.sops.yaml"
if [ ! -f "$SHARED_SECRETS" ]; then
    echo -e "${RED}Error: Shared secrets file not found: $SHARED_SECRETS${NC}"
    exit 1
fi

# Try to read email provider from secrets
EMAIL_PROVIDER=""
if command -v sops &> /dev/null; then
    EMAIL_PROVIDER=$(sops -d "$SHARED_SECRETS" 2>/dev/null | grep "^email_provider:" | awk '{print $2}' || echo "")
fi

echo -e "${YELLOW}Email Provider Options:${NC}"
echo ""
echo "1. Mailgun (recommended for transactional email)"
echo "2. SendGrid"
echo "3. Postmark"
echo "4. Custom SMTP (manual setup)"
echo "5. Self-hosted (Mailcow, etc.)"
echo ""

if [ -n "$EMAIL_PROVIDER" ]; then
    echo -e "${GREEN}Detected email provider in secrets: ${EMAIL_PROVIDER}${NC}"
else
    echo -e "${YELLOW}No email provider configured in secrets/shared.sops.yaml${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setup Instructions${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

case "${EMAIL_PROVIDER,,}" in
    mailgun)
        provision_mailgun
        ;;
    sendgrid)
        provision_sendgrid
        ;;
    *)
        echo -e "${YELLOW}For automatic email provisioning, choose an email provider.${NC}"
        echo ""
        ;;
esac

echo -e "${BLUE}== Option 1: Mailgun (Recommended) ==${NC}"
echo ""
echo "Mailgun provides reliable transactional email with easy DNS setup."
echo ""
echo "1. Sign up at https://www.mailgun.com/"
echo "2. Add domain: ${EMAIL_DOMAIN}"
echo "3. Configure DNS records (Mailgun provides these)"
echo "4. Create SMTP credentials"
echo "5. Update secrets/shared.sops.yaml:"
echo ""
echo "   sops secrets/shared.sops.yaml"
echo ""
echo "   Add the following:"
echo "   smtp_enabled: true"
echo "   smtp_host: smtp.mailgun.org"
echo "   smtp_port: 587"
echo "   smtp_username: postmaster@${EMAIL_DOMAIN}"
echo "   smtp_password: <your-mailgun-smtp-password>"
echo "   smtp_use_tls: true"
echo "   email_provider: mailgun"
echo ""

echo -e "${BLUE}== Option 2: SendGrid ==${NC}"
echo ""
echo "SendGrid is another popular transactional email service."
echo ""
echo "1. Sign up at https://sendgrid.com/"
echo "2. Create API key with Mail Send permissions"
echo "3. Configure sender authentication for ${EMAIL_DOMAIN}"
echo "4. Update secrets/shared.sops.yaml:"
echo ""
echo "   smtp_enabled: true"
echo "   smtp_host: smtp.sendgrid.net"
echo "   smtp_port: 587"
echo "   smtp_username: apikey"
echo "   smtp_password: <your-sendgrid-api-key>"
echo "   smtp_use_tls: true"
echo "   email_provider: sendgrid"
echo ""

echo -e "${BLUE}== Option 3: Postmark ==${NC}"
echo ""
echo "Postmark specializes in transactional email with excellent deliverability."
echo ""
echo "1. Sign up at https://postmarkapp.com/"
echo "2. Create server and get API token"
echo "3. Verify sender domain ${EMAIL_DOMAIN}"
echo "4. Update secrets/shared.sops.yaml:"
echo ""
echo "   smtp_enabled: true"
echo "   smtp_host: smtp.postmarkapp.com"
echo "   smtp_port: 587"
echo "   smtp_username: <your-server-api-token>"
echo "   smtp_password: <your-server-api-token>"
echo "   smtp_use_tls: true"
echo "   email_provider: postmark"
echo ""

echo -e "${BLUE}== Option 4: Self-Hosted (Mailcow) ==${NC}"
echo ""
echo "For full control, you can self-host email with Mailcow or similar."
echo ""
echo "1. Deploy Mailcow on a separate server"
echo "2. Configure DNS (MX, SPF, DKIM, DMARC)"
echo "3. Create mailbox for ${CLIENT_EMAIL}"
echo "4. Update secrets/shared.sops.yaml:"
echo ""
echo "   smtp_enabled: true"
echo "   smtp_host: mail.${EMAIL_DOMAIN}"
echo "   smtp_port: 587"
echo "   smtp_username: ${CLIENT_EMAIL}"
echo "   smtp_password: <mailbox-password>"
echo "   smtp_use_tls: true"
echo "   email_provider: mailcow"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Client Secrets Update${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "After configuring SMTP, update the client secrets file:"
echo ""
echo "  sops secrets/clients/${CLIENT_NAME}.sops.yaml"
echo ""
echo "Add/update these fields:"
echo ""
echo "  # Client-specific email address for sending"
echo "  client_email_address: ${CLIENT_EMAIL}"
echo ""
echo "  # Admin email (also used for Authentik bootstrap)"
echo "  authentik_bootstrap_email: admin@${CLIENT_NAME}.vrije.cloud"
echo ""
echo "  # Nextcloud mail 'from' address prefix"
echo "  nextcloud_mail_from: nextcloud"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DNS Records Required${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "For any email provider, ensure these DNS records are set for ${EMAIL_DOMAIN}:"
echo ""
echo "1. SPF Record (TXT):"
echo "   Name: @"
echo "   Value: v=spf1 include:<provider-spf> ~all"
echo ""
echo "2. DKIM Record (TXT):"
echo "   Name: <selector>._domainkey"
echo "   Value: <provided-by-email-service>"
echo ""
echo "3. DMARC Record (TXT):"
echo "   Name: _dmarc"
echo "   Value: v=DMARC1; p=quarantine; rua=mailto:dmarc@${EMAIL_DOMAIN}"
echo ""
echo "4. MX Record (if receiving email):"
echo "   Name: @"
echo "   Priority: 10"
echo "   Value: <mail-server>"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Next Steps${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "1. Choose an email provider from the options above"
echo "2. Set up the provider and obtain SMTP credentials"
echo "3. Configure DNS records for ${EMAIL_DOMAIN}"
echo "4. Update secrets/shared.sops.yaml with SMTP settings"
echo "5. Update secrets/clients/${CLIENT_NAME}.sops.yaml with client email"
echo "6. Re-deploy the client:"
echo ""
echo "   ./scripts/deploy-client.sh ${CLIENT_NAME}"
echo ""
echo "The deployment will automatically configure:"
echo "- Authentik with SMTP for password resets"
echo "- Nextcloud with SMTP for notifications"
echo "- Admin user email addresses"
echo ""
