#!/usr/bin/env python3
"""
Create OIDC application in Zitadel using the Management API.

This script automates the creation of OIDC applications for services like Nextcloud.
It uses Zitadel's REST API with service account authentication.
"""

import json
import sys
import requests
import time
from typing import Dict, Optional


class ZitadelOIDCManager:
    """Manage OIDC applications in Zitadel."""

    def __init__(self, domain: str, pat_token: str):
        """Initialize the OIDC manager.

        Args:
            domain: Zitadel domain (e.g., zitadel.example.com)
            pat_token: Personal Access Token for authentication
        """
        self.domain = domain
        self.base_url = f"https://{domain}"
        self.headers = {
            "Authorization": f"Bearer {pat_token}",
            "Content-Type": "application/json",
        }

    def get_default_project(self) -> Optional[str]:
        """Get the default project ID."""
        url = f"{self.base_url}/management/v1/projects/_search"
        response = requests.post(url, headers=self.headers, json={})

        if response.status_code == 200:
            projects = response.json().get("result", [])
            if projects:
                return projects[0]["id"]
        return None

    def check_app_exists(self, project_id: str, app_name: str) -> Optional[Dict]:
        """Check if an OIDC app already exists.

        Args:
            project_id: Project ID
            app_name: Application name

        Returns:
            App data if exists, None otherwise
        """
        url = f"{self.base_url}/management/v1/projects/{project_id}/apps/_search"
        response = requests.post(url, headers=self.headers, json={})

        if response.status_code == 200:
            apps = response.json().get("result", [])
            for app in apps:
                if app.get("name") == app_name:
                    return app
        return None

    def create_oidc_app(
        self,
        project_id: str,
        app_name: str,
        redirect_uris: list,
        post_logout_redirect_uris: list = None,
    ) -> Dict:
        """Create an OIDC application.

        Args:
            project_id: Project ID
            app_name: Application name
            redirect_uris: List of redirect URIs
            post_logout_redirect_uris: List of post-logout redirect URIs

        Returns:
            Created app data including client ID and secret
        """
        url = f"{self.base_url}/management/v1/projects/{project_id}/apps/oidc"

        payload = {
            "name": app_name,
            "redirectUris": redirect_uris,
            "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
            "grantTypes": [
                "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
                "OIDC_GRANT_TYPE_REFRESH_TOKEN",
            ],
            "appType": "OIDC_APP_TYPE_WEB",
            "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
            "postLogoutRedirectUris": post_logout_redirect_uris or redirect_uris,
            "version": "OIDC_VERSION_1_0",
            "devMode": False,
            "accessTokenType": "OIDC_TOKEN_TYPE_JWT",
            "accessTokenRoleAssertion": True,
            "idTokenRoleAssertion": True,
            "idTokenUserinfoAssertion": True,
            "clockSkew": "0s",
            "skipNativeAppSuccessPage": False,
        }

        response = requests.post(url, headers=self.headers, json=payload)

        if response.status_code in [200, 201]:
            return response.json()
        else:
            raise Exception(
                f"Failed to create OIDC app: {response.status_code} - {response.text}"
            )


def main():
    """Main entry point."""
    if len(sys.argv) < 5:
        print("Usage: create_oidc_app.py <domain> <pat_token> <app_name> <redirect_uri>")
        sys.exit(1)

    domain = sys.argv[1]
    pat_token = sys.argv[2]
    app_name = sys.argv[3]
    redirect_uri = sys.argv[4]

    try:
        manager = ZitadelOIDCManager(domain, pat_token)

        # Get default project
        project_id = manager.get_default_project()
        if not project_id:
            print("Error: No project found", file=sys.stderr)
            sys.exit(1)

        # Check if app already exists
        existing_app = manager.check_app_exists(project_id, app_name)
        if existing_app:
            print(
                json.dumps(
                    {
                        "status": "exists",
                        "app_id": existing_app.get("id"),
                        "message": f"App '{app_name}' already exists",
                    }
                )
            )
            sys.exit(0)

        # Create new app
        result = manager.create_oidc_app(
            project_id=project_id,
            app_name=app_name,
            redirect_uris=[redirect_uri],
            post_logout_redirect_uris=[redirect_uri.rsplit("/", 1)[0] + "/"],
        )

        # Extract client credentials
        output = {
            "status": "created",
            "app_id": result.get("appId"),
            "client_id": result.get("clientId"),
            "client_secret": result.get("clientSecret"),
            "redirect_uri": redirect_uri,
        }

        print(json.dumps(output))

    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
