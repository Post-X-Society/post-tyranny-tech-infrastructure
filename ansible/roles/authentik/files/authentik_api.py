#!/usr/bin/env python3
"""
Authentik API client for automated OIDC provider configuration.

This script handles the complete automation of Authentik SSO setup:
1. Bootstrap initial admin user (if needed)
2. Create OAuth2/OIDC provider for Nextcloud
3. Return client credentials for Nextcloud configuration

Usage:
    python3 authentik_api.py --domain https://auth.example.com \
                             --app-name Nextcloud \
                             --redirect-uri https://nextcloud.example.com/apps/user_oidc/code \
                             --bootstrap-password <admin_password>
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, Optional, Tuple


class AuthentikAPI:
    """Client for Authentik API with bootstrapping support."""

    def __init__(self, base_url: str, token: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.token = token
        self.session_cookie = None

    def _request(self, method: str, path: str, data: Optional[Dict] = None,
                 headers: Optional[Dict] = None) -> Tuple[int, Dict]:
        """Make HTTP request to Authentik API."""
        import ssl
        url = f"{self.base_url}{path}"
        req_headers = headers or {}

        # Add authentication
        if self.token:
            req_headers['Authorization'] = f'Bearer {self.token}'
        elif self.session_cookie:
            req_headers['Cookie'] = self.session_cookie

        req_headers['Content-Type'] = 'application/json'

        body = json.dumps(data).encode('utf-8') if data else None
        request = urllib.request.Request(url, data=body, headers=req_headers, method=method)

        # Create SSL context (don't verify for internal services)
        ctx = ssl.create_default_context()
        # For production, you'd want to verify certificates properly
        # But for automated deployments, we trust the internal network
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            with urllib.request.urlopen(request, timeout=30, context=ctx) as response:
                response_data = json.loads(response.read().decode('utf-8'))
                # Capture session cookie if present
                cookie = response.headers.get('Set-Cookie')
                if cookie and not self.session_cookie:
                    self.session_cookie = cookie.split(';')[0]
                return response.status, response_data
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            try:
                error_data = json.loads(error_body)
            except json.JSONDecodeError:
                error_data = {'error': error_body}
            return e.code, error_data
        except urllib.error.URLError as e:
            return 0, {'error': str(e)}

    def wait_for_ready(self, timeout: int = 300) -> bool:
        """Wait for Authentik to be ready and responding."""
        print(f"Waiting for Authentik at {self.base_url} to be ready...", file=sys.stderr)
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                status, _ = self._request('GET', '/')
                if status in [200, 302]:
                    print("Authentik is ready!", file=sys.stderr)
                    return True
            except Exception:
                pass

            time.sleep(5)

        print(f"Timeout waiting for Authentik after {timeout}s", file=sys.stderr)
        return False

    def check_bootstrap_needed(self) -> bool:
        """Check if initial setup is needed."""
        status, data = self._request('GET', '/if/flow/initial-setup/')
        # 200 = setup needed, 302/404 = already configured
        return status == 200

    def bootstrap_admin(self, username: str, password: str, email: str) -> bool:
        """Bootstrap initial admin account via initial setup flow."""
        print(f"Bootstrapping admin user: {username}", file=sys.stderr)

        # This is a simplified approach - real implementation would need to:
        # 1. Get CSRF token from initial setup page
        # 2. Submit form with proper flow context
        # 3. Handle multi-step flow if needed

        # For now, we'll document that manual setup is required
        print("WARNING: Automatic bootstrap not yet implemented", file=sys.stderr)
        print(f"Please complete initial setup at: {self.base_url}/if/flow/initial-setup/",
              file=sys.stderr)
        return False

    def create_service_account_token(self, username: str, password: str) -> Optional[str]:
        """Login and create service account token."""
        print("Creating service account token...", file=sys.stderr)

        # Try to authenticate
        status, data = self._request('POST', '/api/v3/core/tokens/', {
            'identifier': username,
            'password': password,
            'intent': 'app_password',
            'description': 'Ansible automation token'
        })

        if status == 201:
            token = data.get('key')
            print("Service account token created successfully", file=sys.stderr)
            return token
        else:
            print(f"Failed to create token: {data}", file=sys.stderr)
            return None

    def get_default_authorization_flow(self) -> Optional[str]:
        """Get the default authorization flow UUID."""
        status, data = self._request('GET', '/api/v3/flows/instances/')

        if status == 200:
            for flow in data.get('results', []):
                if flow.get('slug') == 'default-authorization-flow':
                    return flow['pk']

        # Fallback: get any authorization flow
        for flow in data.get('results', []):
            if flow.get('designation') == 'authorization':
                return flow['pk']

        print("ERROR: No authorization flow found", file=sys.stderr)
        return None

    def get_default_signing_key(self) -> Optional[str]:
        """Get the default signing key UUID."""
        status, data = self._request('GET', '/api/v3/crypto/certificatekeypairs/')

        if status == 200:
            results = data.get('results', [])
            if results:
                # Return first available key
                return results[0]['pk']

        print("ERROR: No signing key found", file=sys.stderr)
        return None

    def create_oidc_provider(self, name: str, redirect_uris: str,
                             flow_uuid: str, key_uuid: str) -> Optional[Dict]:
        """Create OAuth2/OIDC provider."""
        print(f"Creating OIDC provider for {name}...", file=sys.stderr)

        provider_data = {
            'name': name,
            'authorization_flow': flow_uuid,
            'client_type': 'confidential',
            'redirect_uris': redirect_uris,
            'signing_key': key_uuid,
            'sub_mode': 'hashed_user_id',
            'include_claims_in_id_token': True,
        }

        status, data = self._request('POST', '/api/v3/providers/oauth2/', provider_data)

        if status == 201:
            print(f"OIDC provider created: {data['pk']}", file=sys.stderr)
            return data
        else:
            print(f"ERROR: Failed to create OIDC provider: {data}", file=sys.stderr)
            return None

    def create_application(self, name: str, slug: str, provider_id: int,
                          launch_url: str) -> Optional[Dict]:
        """Create application linked to OIDC provider."""
        print(f"Creating application {name}...", file=sys.stderr)

        app_data = {
            'name': name,
            'slug': slug,
            'provider': provider_id,
            'meta_launch_url': launch_url,
        }

        status, data = self._request('POST', '/api/v3/core/applications/', app_data)

        if status == 201:
            print(f"Application created: {data['pk']}", file=sys.stderr)
            return data
        else:
            print(f"ERROR: Failed to create application: {data}", file=sys.stderr)
            return None


def main():
    parser = argparse.ArgumentParser(description='Automate Authentik OIDC provider setup')
    parser.add_argument('--domain', required=True, help='Authentik domain (https://auth.example.com)')
    parser.add_argument('--app-name', required=True, help='Application name (e.g., Nextcloud)')
    parser.add_argument('--app-slug', help='Application slug (defaults to lowercase app-name)')
    parser.add_argument('--redirect-uri', required=True, help='OAuth2 redirect URI')
    parser.add_argument('--launch-url', help='Application launch URL (defaults to redirect-uri base)')
    parser.add_argument('--token', help='Authentik API token (if already bootstrapped)')
    parser.add_argument('--bootstrap-user', default='akadmin', help='Bootstrap admin username')
    parser.add_argument('--bootstrap-password', help='Bootstrap admin password')
    parser.add_argument('--bootstrap-email', default='admin@localhost', help='Bootstrap admin email')
    parser.add_argument('--wait-timeout', type=int, default=300, help='Timeout for waiting (seconds)')

    args = parser.parse_args()

    # Derive defaults
    app_slug = args.app_slug or args.app_name.lower()
    launch_url = args.launch_url or args.redirect_uri.rsplit('/', 2)[0]

    # Initialize API client
    api = AuthentikAPI(args.domain, args.token)

    # Wait for Authentik to be ready
    if not api.wait_for_ready(args.wait_timeout):
        print(json.dumps({'error': 'Authentik not ready'}))
        sys.exit(1)

    # Check if bootstrap is needed
    if not args.token:
        if api.check_bootstrap_needed():
            if not args.bootstrap_password:
                print(json.dumps({
                    'error': 'Bootstrap needed but no password provided',
                    'action_required': f'Visit {args.domain}/if/flow/initial-setup/ to complete setup',
                    'next_step': 'Create service account and provide --token'
                }))
                sys.exit(1)

            # Try to bootstrap (not yet implemented)
            if not api.bootstrap_admin(args.bootstrap_user, args.bootstrap_password,
                                       args.bootstrap_email):
                print(json.dumps({
                    'error': 'Bootstrap not yet automated',
                    'action_required': f'Visit {args.domain}/if/flow/initial-setup/ manually',
                    'instructions': [
                        f'1. Create admin user: {args.bootstrap_user}',
                        '2. Create API token in admin UI',
                        '3. Re-run with --token <token>'
                    ]
                }))
                sys.exit(1)

        print("ERROR: No API token provided and bootstrap needed", file=sys.stderr)
        sys.exit(1)

    # Get required UUIDs
    flow_uuid = api.get_default_authorization_flow()
    key_uuid = api.get_default_signing_key()

    if not flow_uuid or not key_uuid:
        print(json.dumps({'error': 'Failed to get required Authentik configuration'}))
        sys.exit(1)

    # Create OIDC provider
    provider = api.create_oidc_provider(args.app_name, args.redirect_uri, flow_uuid, key_uuid)
    if not provider:
        print(json.dumps({'error': 'Failed to create OIDC provider'}))
        sys.exit(1)

    # Create application
    application = api.create_application(args.app_name, app_slug, provider['pk'], launch_url)
    if not application:
        print(json.dumps({'error': 'Failed to create application'}))
        sys.exit(1)

    # Output credentials
    result = {
        'success': True,
        'provider_id': provider['pk'],
        'application_id': application['pk'],
        'client_id': provider['client_id'],
        'client_secret': provider['client_secret'],
        'discovery_uri': f"{args.domain}/application/o/{app_slug}/.well-known/openid-configuration",
        'issuer': f"{args.domain}/application/o/{app_slug}/",
    }

    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
