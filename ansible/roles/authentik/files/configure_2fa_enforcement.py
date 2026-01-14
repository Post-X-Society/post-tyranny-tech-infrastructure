#!/usr/bin/env python3
"""
Configure 2FA enforcement in Authentik.
Modifies the default-authentication-mfa-validation stage to force users to configure MFA.
"""
import sys
import json
import urllib.request
import urllib.error

def api_request(base_url, token, path, method='GET', data=None):
    """Make API request to Authentik"""
    url = f"{base_url}{path}"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }

    request_data = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=request_data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        try:
            error_data = json.loads(error_body)
        except:
            error_data = {'error': error_body}
        return e.code, error_data

def main():
    if len(sys.argv) != 3:
        print(json.dumps({'error': 'Usage: configure_2fa_enforcement.py <base_url> <api_token>'}), file=sys.stderr)
        sys.exit(1)

    base_url = sys.argv[1]
    token = sys.argv[2]

    # Step 1: Find the default MFA validation stage
    status, stages_response = api_request(base_url, token, '/api/v3/stages/authenticator/validate/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list authenticator validate stages', 'details': stages_response}), file=sys.stderr)
        sys.exit(1)

    mfa_stage = next((s for s in stages_response.get('results', [])
                     if 'default-authentication-mfa-validation' in s.get('name', '').lower()), None)

    if not mfa_stage:
        print(json.dumps({'error': 'default-authentication-mfa-validation stage not found'}), file=sys.stderr)
        sys.exit(1)

    stage_pk = mfa_stage['pk']

    # Step 2: Find the default TOTP setup stage to use as configuration stage
    status, totp_stages_response = api_request(base_url, token, '/api/v3/stages/authenticator/totp/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list TOTP setup stages', 'details': totp_stages_response}), file=sys.stderr)
        sys.exit(1)

    totp_setup_stage = next((s for s in totp_stages_response.get('results', [])
                            if 'setup' in s.get('name', '').lower()), None)

    if not totp_setup_stage:
        print(json.dumps({'error': 'TOTP setup stage not found'}), file=sys.stderr)
        sys.exit(1)

    totp_setup_pk = totp_setup_stage['pk']

    # Step 3: Update the MFA validation stage to force configuration
    update_data = {
        'name': mfa_stage['name'],
        'not_configured_action': 'configure',  # Force user to configure
        'configuration_stages': [totp_setup_pk]  # Use TOTP setup stage
    }

    status, updated_stage = api_request(base_url, token, f'/api/v3/stages/authenticator/validate/{stage_pk}/', 'PATCH', update_data)
    if status not in [200, 201]:
        print(json.dumps({'error': 'Failed to update MFA validation stage', 'details': updated_stage}), file=sys.stderr)
        sys.exit(1)

    print(json.dumps({
        'success': True,
        'message': '2FA enforcement configured',
        'stage_name': mfa_stage['name'],
        'stage_pk': stage_pk,
        'note': 'Users will be forced to configure TOTP on login'
    }))

if __name__ == '__main__':
    main()
