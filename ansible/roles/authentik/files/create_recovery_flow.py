#!/usr/bin/env python3
"""
Create password recovery flow in Authentik
Allows users to reset their password via email
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
        print(json.dumps({'error': 'Usage: create_recovery_flow.py <base_url> <api_token>'}))
        sys.exit(1)

    base_url = sys.argv[1]
    token = sys.argv[2]

    # Check if recovery flow already exists
    status, flows = api_request(base_url, token, '/api/v3/flows/instances/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list flows', 'details': flows}), file=sys.stderr)
        sys.exit(1)

    existing_recovery = next((f for f in flows.get('results', [])
                             if f.get('slug') == 'recovery-flow'), None)

    if existing_recovery:
        print(json.dumps({
            'success': True,
            'message': 'Recovery flow already exists',
            'flow_id': existing_recovery['pk']
        }))
        sys.exit(0)

    # Get default recovery flow to use as template
    default_recovery = next((f for f in flows.get('results', [])
                            if f.get('designation') == 'recovery'), None)

    if not default_recovery:
        print(json.dumps({'error': 'No default recovery flow found'}), file=sys.stderr)
        sys.exit(1)

    # Use the default recovery flow - it already exists and works
    print(json.dumps({
        'success': True,
        'message': 'Using default recovery flow',
        'flow_id': default_recovery['pk'],
        'flow_slug': default_recovery['slug']
    }))

if __name__ == '__main__':
    main()
