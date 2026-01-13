#!/usr/bin/env python3
"""
Create user invitation flow in Authentik
Allows admins to send invitation emails to new users
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
        print(json.dumps({'error': 'Usage: create_invitation_flow.py <base_url> <api_token>'}))
        sys.exit(1)

    base_url = sys.argv[1]
    token = sys.argv[2]

    # Check if invitation flow already exists
    status, flows = api_request(base_url, token, '/api/v3/flows/instances/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list flows', 'details': flows}), file=sys.stderr)
        sys.exit(1)

    existing_invitation = next((f for f in flows.get('results', [])
                               if 'invitation' in f.get('slug', '').lower()), None)

    if existing_invitation:
        print(json.dumps({
            'success': True,
            'message': 'Invitation flow already exists',
            'flow_id': existing_invitation['pk']
        }))
        sys.exit(0)

    # Get enrollment flow to use for invitations
    enrollment_flow = next((f for f in flows.get('results', [])
                           if f.get('designation') == 'enrollment'), None)

    if enrollment_flow:
        print(json.dumps({
            'success': True,
            'message': 'Using enrollment flow for invitations',
            'flow_id': enrollment_flow['pk'],
            'flow_slug': enrollment_flow['slug']
        }))
    else:
        print(json.dumps({'error': 'No enrollment flow found'}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
