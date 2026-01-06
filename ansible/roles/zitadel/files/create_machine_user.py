#!/usr/bin/env python3
"""
Create a machine user in Zitadel using admin credentials.
This script creates a service account with a JWT key for API automation.
"""

import json
import sys
import requests
from urllib.parse import urlencode

def get_admin_token(domain, username, password):
    """Get access token using admin username/password."""
    token_url = f"https://{domain}/oauth/v2/token"

    data = {
        "grant_type": "password",
        "username": username,
        "password": password,
        "scope": "openid profile email urn:zitadel:iam:org:project:id:zitadel:aud",
    }

    response = requests.post(token_url, data=data)
    if response.status_code == 200:
        return response.json().get("access_token")
    else:
        raise Exception(f"Failed to get admin token: {response.status_code} - {response.text}")

def create_machine_user(domain, access_token, username, name):
    """Create a machine user."""
    url = f"https://{domain}/management/v1/users/machine"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {
        "userName": username,
        "name": name,
        "description": "Service account for automated API operations",
        "accessTokenType": "ACCESS_TOKEN_TYPE_JWT",
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code in [200, 201]:
        return response.json().get("userId")
    elif response.status_code == 409:
        # User already exists, get the user ID
        return find_machine_user(domain, access_token, username)
    else:
        raise Exception(f"Failed to create machine user: {response.status_code} - {response.text}")

def find_machine_user(domain, access_token, username):
    """Find existing machine user by username."""
    url = f"https://{domain}/management/v1/users/_search"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {
        "queries": [
            {
                "userNameQuery": {
                    "userName": username,
                    "method": "TEXT_QUERY_METHOD_EQUALS"
                }
            }
        ]
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code == 200:
        result = response.json().get("result", [])
        if result:
            return result[0].get("id")
    return None

def create_machine_key(domain, access_token, user_id):
    """Create a JWT key for the machine user."""
    url = f"https://{domain}/management/v1/users/{user_id}/keys"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {
        "type": "KEY_TYPE_JSON",
        "expirationDate": "2030-01-01T00:00:00Z",
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code in [200, 201]:
        return response.json()
    else:
        raise Exception(f"Failed to create machine key: {response.status_code} - {response.text}")

def main():
    if len(sys.argv) != 4:
        print("Usage: create_machine_user.py <domain> <admin_username> <admin_password>")
        sys.exit(1)

    domain = sys.argv[1]
    admin_username = sys.argv[2]
    admin_password = sys.argv[3]

    try:
        # Get admin access token
        print(f"Authenticating as admin...", file=sys.stderr)
        access_token = get_admin_token(domain, admin_username, admin_password)

        # Create machine user
        print(f"Creating machine user 'api-automation'...", file=sys.stderr)
        user_id = create_machine_user(domain, access_token, "api-automation", "API Automation Service")
        print(f"Machine user ID: {user_id}", file=sys.stderr)

        # Create JWT key
        print(f"Creating JWT key...", file=sys.stderr)
        key_data = create_machine_key(domain, access_token, user_id)

        # Output the key as JSON
        print(json.dumps(key_data, indent=2))

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
