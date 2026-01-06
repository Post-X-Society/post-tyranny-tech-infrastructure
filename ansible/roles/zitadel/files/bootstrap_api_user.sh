#!/bin/bash
# Bootstrap Zitadel API service user and generate PAT
# This script must be run once per client after initial Zitadel deployment
# It creates a machine user with a Personal Access Token for API automation

set -e

ZITADEL_DOMAIN="$1"
ADMIN_USERNAME="$2"
ADMIN_PASSWORD="$3"

if [ -z "$ZITADEL_DOMAIN" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "Usage: $0 <zitadel_domain> <admin_username> <admin_password>" >&2
    echo "Example: $0 zitadel.test.vrije.cloud 'admin@test.zitadel.test.vrije.cloud' 'password123'" >&2
    exit 1
fi

echo "🔧 Bootstrapping Zitadel API automation..."
echo "Domain: $ZITADEL_DOMAIN"
echo "Admin: $ADMIN_USERNAME"
echo ""

# This is a placeholder script that provides instructions for the manual one-time setup
# In a production environment, this would use Puppeteer/Selenium to automate the browser

echo "⚠️  MANUAL SETUP REQUIRED (one time per client)"
echo ""
echo "Please follow these steps in your browser:"
echo ""
echo "1. Open: https://$ZITADEL_DOMAIN/ui/console"
echo "2. Login with:"
echo "   Username: $ADMIN_USERNAME"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "3. Navigate to: Users → Service Users"
echo "4. Click 'New'"
echo "5. Enter:"
echo "   Username: api-automation"
echo "   Name: API Automation Service"
echo "6. Click 'Create'"
echo ""
echo "7. Click on the new user 'api-automation'"
echo "8. Go to 'Personal Access Tokens' tab"
echo "9. Click 'New'"
echo "10. Set expiration date: 2099-12-31 (or far future)"
echo "11. Click 'Add'"
echo "12. COPY THE TOKEN (it will only be shown once!)"
echo ""
echo "13. Add the token to your secrets file:"
echo "    zitadel_api_token: <paste-token-here>"
echo ""
echo "14. Re-run the deployment: ansible-playbook -i hcloud.yml playbooks/deploy.yml"
echo ""
echo "After this one-time setup, all OIDC apps will be created automatically!"
echo ""

# TODO: Implement browser automation using Puppeteer or Selenium
# For now, this provides clear instructions for the manual process
