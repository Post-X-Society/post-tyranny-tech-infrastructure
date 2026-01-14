#!/usr/bin/env python3
"""
Configure Authentik recovery flow.
Verifies that the default recovery flow exists (Authentik creates it by default).
The recovery flow is used when clicking "Create recovery link" in the UI.
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
        print(json.dumps({'error': 'Usage: configure_recovery_flow.py <base_url> <api_token>'}), file=sys.stderr)
        sys.exit(1)

    base_url = sys.argv[1]
    token = sys.argv[2]

    # Get the default recovery flow (created by Authentik by default)
    status, flows_response = api_request(base_url, token, '/api/v3/flows/instances/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list flows', 'details': flows_response}), file=sys.stderr)
        sys.exit(1)

    recovery_flow = next((f for f in flows_response.get('results', [])
                         if f.get('designation') == 'recovery'), None)

    if not recovery_flow:
        print(json.dumps({'error': 'No recovery flow found - Authentik should create one by default'}), file=sys.stderr)
        sys.exit(1)

    flow_slug = recovery_flow['slug']
    flow_pk = recovery_flow['pk']

    print(json.dumps({
        'success': True,
        'message': 'Recovery flow configured',
        'flow_slug': flow_slug,
        'flow_pk': flow_pk,
        'note': 'Using Authentik default recovery flow'
    }))

if __name__ == '__main__':
    main()
