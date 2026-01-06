#!/usr/bin/env python3
"""
Zitadel API client using JWT authentication.
Fully automated OIDC app provisioning.
"""

import json
import sys
import time
import requests
import jwt
from typing import Dict, Optional


class ZitadelAPI:
    """Zitadel API client with JWT authentication."""

    def __init__(self, domain: str, jwt_key_path: str):
        """Initialize with JWT key file."""
        self.domain = domain
        self.base_url = f"https://{domain}"

        # Load JWT key
        with open(jwt_key_path, 'r') as f:
            self.jwt_key = json.load(f)

        self.user_id = self.jwt_key.get("userId")
        self.key_id = self.jwt_key.get("keyId")
        self.private_key = self.jwt_key.get("key")

    def get_access_token(self) -> str:
        """Get access token using JWT assertion."""
        # Create JWT assertion
        now = int(time.time())
        payload = {
            "iss": self.user_id,
            "sub": self.user_id,
            "aud": self.domain,
            "iat": now,
            "exp": now + 3600,
        }

        assertion = jwt.encode(
            payload,
            self.private_key,
            algorithm="RS256",
            headers={"kid": self.key_id}
        )

        # Exchange JWT for access token
        token_url = f"{self.base_url}/oauth/v2/token"
        data = {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
            "scope": "openid profile email urn:zitadel:iam:org:project:id:zitadel:aud",
        }

        response = requests.post(token_url, data=data)
        if response.status_code == 200:
            return response.json().get("access_token")
        else:
            raise Exception(f"Failed to get access token: {response.status_code} - {response.text}")

    def create_project(self, access_token: str, name: str) -> Optional[str]:
        """Create a project."""
        url = f"{self.base_url}/management/v1/projects"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }
        payload = {"name": name}

        response = requests.post(url, headers=headers, json=payload)

        if response.status_code in [200, 201]:
            return response.json().get("id")
        elif response.status_code == 409:
            # Already exists, find it
            return self.find_project(access_token, name)
        else:
            raise Exception(f"Failed to create project: {response.status_code} - {response.text}")

    def find_project(self, access_token: str, name: str) -> Optional[str]:
        """Find existing project by name."""
        url = f"{self.base_url}/management/v1/projects/_search"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }

        response = requests.post(url, headers=headers, json={})

        if response.status_code == 200:
            projects = response.json().get("result", [])
            for project in projects:
                if project.get("name") == name:
                    return project["id"]
        return None

    def create_oidc_app(
        self,
        access_token: str,
        project_id: str,
        app_name: str,
        redirect_uri: str,
    ) -> Dict:
        """Create OIDC application."""
        url = f"{self.base_url}/management/v1/projects/{project_id}/apps/oidc"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }

        payload = {
            "name": app_name,
            "redirectUris": [redirect_uri],
            "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
            "grantTypes": [
                "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
                "OIDC_GRANT_TYPE_REFRESH_TOKEN",
            ],
            "appType": "OIDC_APP_TYPE_WEB",
            "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
            "postLogoutRedirectUris": [redirect_uri.rsplit("/", 1)[0] + "/"],
            "version": "OIDC_VERSION_1_0",
            "devMode": False,
            "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
            "accessTokenRoleAssertion": True,
            "idTokenRoleAssertion": True,
            "idTokenUserinfoAssertion": True,
            "clockSkew": "0s",
        }

        response = requests.post(url, headers=headers, json=payload)

        if response.status_code in [200, 201]:
            return response.json()
        else:
            raise Exception(f"Failed to create OIDC app: {response.status_code} - {response.text}")


def main():
    """Main entry point."""
    if len(sys.argv) < 5:
        print("Usage: zitadel_api.py <domain> <jwt_key_path> <app_name> <redirect_uri>")
        sys.exit(1)

    domain = sys.argv[1]
    jwt_key_path = sys.argv[2]
    app_name = sys.argv[3]
    redirect_uri = sys.argv[4]

    try:
        api = ZitadelAPI(domain, jwt_key_path)

        # Get access token
        access_token = api.get_access_token()

        # Get or create project
        project_id = api.create_project(access_token, "SSO Applications")

        # Create OIDC app
        result = api.create_oidc_app(access_token, project_id, app_name, redirect_uri)

        # Output credentials
        output = {
            "status": "created",
            "app_id": result.get("appId"),
            "client_id": result.get("clientId"),
            "client_secret": result.get("clientSecret"),
            "redirect_uri": redirect_uri,
        }

        print(json.dumps(output))

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
