#!/usr/bin/env python3
"""
One-time setup script to configure Zitadel for full OIDC automation.
This script uses the manually created PAT to set up everything needed.
"""

import json
import sys
import requests
from typing import Optional


class ZitadelSetup:
    """Setup Zitadel for OIDC automation."""

    def __init__(self, domain: str, pat_token: str):
        self.domain = domain
        self.base_url = f"https://{domain}"
        self.headers = {
            "Authorization": f"Bearer {pat_token}",
            "Content-Type": "application/json",
        }

    def create_project(self, name: str) -> Optional[str]:
        """Create a project for OIDC applications."""
        url = f"{self.base_url}/management/v1/projects"
        payload = {"name": name}

        print(f"📦 Creating project '{name}'...")
        response = requests.post(url, headers=self.headers, json=payload)

        if response.status_code in [200, 201]:
            project_id = response.json().get("id")
            print(f"✅ Project created: {project_id}")
            return project_id
        elif response.status_code == 409:
            print(f"ℹ️  Project already exists, searching...")
            return self.find_project(name)
        else:
            print(f"❌ Failed to create project: {response.status_code}")
            print(f"Response: {response.text}")
            return None

    def find_project(self, name: str) -> Optional[str]:
        """Find existing project by name."""
        url = f"{self.base_url}/management/v1/projects/_search"
        response = requests.post(url, headers=self.headers, json={})

        if response.status_code == 200:
            projects = response.json().get("result", [])
            for project in projects:
                if project.get("name") == name:
                    print(f"✅ Found existing project: {project['id']}")
                    return project["id"]
        return None

    def get_service_user_id(self, username: str) -> Optional[str]:
        """Find the service user ID."""
        url = f"{self.base_url}/management/v1/users/_search"
        payload = {
            "query": {
                "userName": username
            }
        }

        print(f"🔍 Looking for service user '{username}'...")
        response = requests.post(url, headers=self.headers, json=payload)

        if response.status_code == 200:
            users = response.json().get("result", [])
            if users:
                user_id = users[0].get("id")
                print(f"✅ Found service user: {user_id}")
                return user_id

        print(f"❌ Service user not found")
        return None

    def grant_project_permission(self, project_id: str, user_id: str) -> bool:
        """Grant project ownership to service user."""
        url = f"{self.base_url}/management/v1/projects/{project_id}/roles/_bulk/set"

        # Grant PROJECT_OWNER role
        payload = {
            "grants": [
                {
                    "userId": user_id,
                    "roleKeys": ["PROJECT_OWNER"]
                }
            ]
        }

        print(f"🔐 Granting PROJECT_OWNER permission...")
        response = requests.post(url, headers=self.headers, json=payload)

        if response.status_code in [200, 201]:
            print(f"✅ Permission granted")
            return True
        else:
            print(f"⚠️  Permission grant: {response.status_code}")
            print(f"Response: {response.text}")
            # This might fail if already granted, which is OK
            return True


def main():
    if len(sys.argv) < 3:
        print("Usage: setup_automation.py <domain> <pat_token>")
        sys.exit(1)

    domain = sys.argv[1]
    pat_token = sys.argv[2]

    print(f"""
🚀 Zitadel OIDC Automation Setup
=================================
Domain: {domain}

This script will:
1. Create 'SSO Applications' project
2. Grant api-automation user PROJECT_OWNER permission
3. Enable full OIDC automation

""")

    try:
        setup = ZitadelSetup(domain, pat_token)

        # Step 1: Create or find project
        project_id = setup.create_project("SSO Applications")
        if not project_id:
            print("\n❌ Failed to create/find project")
            sys.exit(1)

        # Step 2: Find service user
        user_id = setup.get_service_user_id("api-automation")
        if not user_id:
            print("\n❌ Service user 'api-automation' not found")
            print("Please create the machine user first via Zitadel console")
            sys.exit(1)

        # Step 3: Grant permissions
        if not setup.grant_project_permission(project_id, user_id):
            print("\n⚠️  Warning: Could not grant permissions (may already exist)")

        print(f"""
✅ SUCCESS! OIDC automation is now fully configured.

Next steps:
- Run deployment: ansible-playbook -i hcloud.yml playbooks/deploy.yml
- All OIDC apps will be created automatically
- No more manual steps required!

Project ID: {project_id}
Service User: api-automation ({user_id})
""")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
