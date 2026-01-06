#!/usr/bin/env python3
"""
Automate creation of Zitadel API service user and Personal Access Token.
This script logs in as admin and creates a machine user with a PAT for API automation.
"""

import requests
import sys
import time
import re
from urllib.parse import urlparse, parse_qs

def login_and_get_session(domain, username, password):
    """Login to Zitadel and get authenticated session cookies."""
    session = requests.Session()
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    })

    # Start login flow
    login_url = f"https://{domain}/ui/login/loginname"
    print(f"📡 Initiating login to {domain}...")

    # Get login page to establish session
    resp = session.get(login_url, allow_redirects=True)

    # Submit username
    login_data = {
        'loginName': username
    }
    resp = session.post(login_url, data=login_data, allow_redirects=True)

    # Submit password
    password_url = f"https://{domain}/ui/login/password"
    password_data = {
        'password': password
    }
    resp = session.post(password_url, data=password_data, allow_redirects=True)

    if 'set-cookie' in resp.headers or len(session.cookies) > 0:
        print("✅ Login successful!")
        return session
    else:
        print(f"❌ Login failed. Status: {resp.status_code}")
        print(f"Response: {resp.text[:500]}")
        return None

def create_machine_user(session, domain):
    """Create a machine user via Management API."""
    api_url = f"https://{domain}/management/v1/users/machine"

    print("🤖 Creating API automation service user...")

    payload = {
        "userName": "api-automation",
        "name": "API Automation Service",
        "description": "Service account for automated OIDC app provisioning",
        "accessTokenType": "ACCESS_TOKEN_TYPE_BEARER"
    }

    resp = session.post(api_url, json=payload)

    if resp.status_code in [200, 201]:
        data = resp.json()
        user_id = data.get('userId')
        print(f"✅ Machine user created: {user_id}")
        return user_id
    elif resp.status_code == 409:
        print("ℹ️  Machine user already exists")
        # Try to get existing user
        list_url = f"https://{domain}/management/v1/users/_search"
        search_payload = {
            "query": {
                "userName": "api-automation"
            }
        }
        resp = session.post(list_url, json=search_payload)
        if resp.status_code == 200:
            users = resp.json().get('result', [])
            if users:
                user_id = users[0].get('id')
                print(f"✅ Found existing user: {user_id}")
                return user_id
        return None
    else:
        print(f"❌ Failed to create machine user. Status: {resp.status_code}")
        print(f"Response: {resp.text}")
        return None

def create_pat(session, domain, user_id):
    """Create a Personal Access Token for the machine user."""
    pat_url = f"https://{domain}/management/v1/users/{user_id}/pats"

    print("🔑 Creating Personal Access Token...")

    payload = {
        "expirationDate": "2099-12-31T23:59:59Z"
    }

    resp = session.post(pat_url, json=payload)

    if resp.status_code in [200, 201]:
        data = resp.json()
        token = data.get('token')
        if token:
            print("✅ Personal Access Token created successfully!")
            return token
        else:
            print("⚠️  PAT created but token not in response")
            print(f"Response: {resp.text}")
            return None
    else:
        print(f"❌ Failed to create PAT. Status: {resp.status_code}")
        print(f"Response: {resp.text}")
        return None

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 bootstrap_api_token.py <domain> <admin_username> <admin_password>")
        print("Example: python3 bootstrap_api_token.py zitadel.test.vrije.cloud 'admin@test.zitadel.test.vrije.cloud' 'password123'")
        sys.exit(1)

    domain = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    print(f"""
🚀 Zitadel API Token Bootstrap
================================
Domain: {domain}
Admin: {username}
""")

    # Step 1: Login
    session = login_and_get_session(domain, username, password)
    if not session:
        print("\n❌ Failed to establish session")
        sys.exit(1)

    # Small delay to ensure session is established
    time.sleep(2)

    # Step 2: Create machine user
    user_id = create_machine_user(session, domain)
    if not user_id:
        print("\n❌ Failed to create or find machine user")
        sys.exit(1)

    # Small delay
    time.sleep(1)

    # Step 3: Create PAT
    token = create_pat(session, domain, user_id)
    if not token:
        print("\n❌ Failed to create Personal Access Token")
        sys.exit(1)

    print(f"""
✅ SUCCESS! API automation is ready.

📋 Personal Access Token:
{token}

🔐 Add this to your secrets file:
zitadel_api_token: {token}

Then re-run: ansible-playbook -i hcloud.yml playbooks/deploy.yml
""")

if __name__ == '__main__':
    main()
