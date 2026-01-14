#!/usr/bin/env python3
"""
Configure Authentik invitation flow.
Creates an invitation stage and binds it to the default enrollment flow.
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
        print(json.dumps({'error': 'Usage: configure_invitation_flow.py <base_url> <api_token>'}), file=sys.stderr)
        sys.exit(1)

    base_url = sys.argv[1]
    token = sys.argv[2]

    # Step 1: Get the default enrollment flow
    status, flows_response = api_request(base_url, token, '/api/v3/flows/instances/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list flows', 'details': flows_response}), file=sys.stderr)
        sys.exit(1)

    enrollment_flow = next((f for f in flows_response.get('results', [])
                           if f.get('designation') == 'enrollment'), None)

    if not enrollment_flow:
        print(json.dumps({'error': 'No enrollment flow found'}), file=sys.stderr)
        sys.exit(1)

    flow_slug = enrollment_flow['slug']
    flow_pk = enrollment_flow['pk']

    # Step 2: Check if invitation stage already exists
    status, stages_response = api_request(base_url, token, '/api/v3/stages/invitation/')
    if status != 200:
        print(json.dumps({'error': 'Failed to list invitation stages', 'details': stages_response}), file=sys.stderr)
        sys.exit(1)

    invitation_stage = next((s for s in stages_response.get('results', [])
                            if s.get('name') == 'default-enrollment-invitation'), None)

    # Step 3: Create invitation stage if it doesn't exist
    if not invitation_stage:
        stage_data = {
            'name': 'default-enrollment-invitation',
            'continue_flow_without_invitation': True
        }
        status, invitation_stage = api_request(base_url, token, '/api/v3/stages/invitation/', 'POST', stage_data)
        if status not in [200, 201]:
            print(json.dumps({'error': 'Failed to create invitation stage', 'details': invitation_stage}), file=sys.stderr)
            sys.exit(1)

    stage_pk = invitation_stage['pk']

    # Step 4: Check if the stage is already bound to the enrollment flow
    status, bindings_response = api_request(base_url, token, f'/api/v3/flows/bindings/?target={flow_pk}')
    if status != 200:
        print(json.dumps({'error': 'Failed to list flow bindings', 'details': bindings_response}), file=sys.stderr)
        sys.exit(1)

    # Check if invitation stage is already bound
    invitation_binding = next((b for b in bindings_response.get('results', [])
                              if b.get('stage') == stage_pk), None)

    # Step 5: Bind the invitation stage to the enrollment flow if not already bound
    if not invitation_binding:
        # Find the highest order number to insert at the beginning
        max_order = max([b.get('order', 0) for b in bindings_response.get('results', [])], default=0)

        binding_data = {
            'target': flow_pk,
            'stage': stage_pk,
            'order': 0,  # Put invitation stage first
            'evaluate_on_plan': True,
            're_evaluate_policies': False
        }
        status, binding = api_request(base_url, token, '/api/v3/flows/bindings/', 'POST', binding_data)
        if status not in [200, 201]:
            print(json.dumps({'error': 'Failed to bind invitation stage to flow', 'details': binding}), file=sys.stderr)
            sys.exit(1)

    print(json.dumps({
        'success': True,
        'message': 'Invitation flow configured',
        'flow_slug': flow_slug,
        'stage_pk': stage_pk,
        'note': 'Invitation stage bound to enrollment flow'
    }))

if __name__ == '__main__':
    main()
