#!/usr/bin/env python3
import sys, json, urllib.request

base_url = "https://auth.test.vrije.cloud"
token = "ak_0Xj3OmKT0rx5E_TDKjuvXAl2Ry8IfxlSDKPSRq7fH71uPX3M04d-Xg"
nextcloud_domain = "nextcloud.test.vrije.cloud"
authentik_domain = "auth.test.vrije.cloud"

def req(p, m='GET', d=None):
    url = f"{base_url}{p}"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    data = json.dumps(d).encode() if d else None
    request = urllib.request.Request(url, data, headers, method=m)

    try:
        with urllib.request.urlopen(request, timeout=30) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        content_type = e.headers.get('Content-Type', '')
        if content_type.startswith('application/json'):
            return e.code, json.loads(e.read())
        else:
            return e.code, {'error': e.read().decode()}

# Check if provider already exists
print("Checking for existing providers...")
status, providers = req('/api/v3/providers/oauth2/')
print(f"Found {len(providers.get('results', []))} providers")

for provider in providers.get('results', []):
    print(f"  - {provider.get('name')} (ID: {provider.get('pk')})")
    if provider.get('name') == 'Nextcloud':
        print(f"    Deleting existing Nextcloud provider...")
        status, _ = req(f"/api/v3/providers/oauth2/{provider.get('pk')}/", 'DELETE')
        print(f"    Delete status: {status}")

# Get flows
print("\nGetting flows...")
status, flows = req('/api/v3/flows/instances/')
auth_flow = next((f['pk'] for f in flows.get('results', []) if f.get('slug') == 'default-authorization-flow' or f.get('designation') == 'authorization'), None)
inval_flow = next((f['pk'] for f in flows.get('results', []) if f.get('slug') == 'default-invalidation-flow' or f.get('designation') == 'invalidation'), None)
print(f"Auth flow: {auth_flow}, Invalidation flow: {inval_flow}")

# Get signing key
print("\nGetting signing keys...")
status, keys = req('/api/v3/crypto/certificatekeypairs/')
key = keys.get('results', [{}])[0].get('pk') if keys.get('results') else None
print(f"Signing key: {key}")

if not auth_flow or not key:
    print("ERROR: Missing required configuration")
    sys.exit(1)

# Create provider
print("\nCreating new OIDC provider...")
provider_data = {
    'name': 'Nextcloud',
    'authorization_flow': auth_flow,
    'invalidation_flow': inval_flow,
    'client_type': 'confidential',
    'redirect_uris': [
        {
            'matching_mode': 'strict',
            'url': f'https://{nextcloud_domain}/apps/user_oidc/code'
        }
    ],
    'signing_key': key,
    'sub_mode': 'hashed_user_id',
    'include_claims_in_id_token': True
}

print(f"Provider data: {json.dumps(provider_data, indent=2)}")

status, prov = req('/api/v3/providers/oauth2/', 'POST', provider_data)
print(f"Create provider status: {status}")
print(f"Response: {json.dumps(prov, indent=2)}")

if status != 201:
    print("ERROR: Failed to create provider")
    sys.exit(1)

# Check if application already exists
print("\nChecking for existing applications...")
status, apps = req('/api/v3/core/applications/')
for app in apps.get('results', []):
    if app.get('slug') == 'nextcloud':
        print(f"  Deleting existing Nextcloud application...")
        status, _ = req(f"/api/v3/core/applications/{app.get('slug')}/", 'DELETE')
        print(f"  Delete status: {status}")

# Create application
print("\nCreating application...")
app_data = {
    'name': 'Nextcloud',
    'slug': 'nextcloud',
    'provider': prov['pk'],
    'meta_launch_url': f'https://{nextcloud_domain}'
}

status, app = req('/api/v3/core/applications/', 'POST', app_data)
print(f"Create application status: {status}")

if status != 201:
    print("ERROR: Failed to create application")
    print(f"Response: {json.dumps(app, indent=2)}")
    sys.exit(1)

# Success!
result = {
    'success': True,
    'provider_id': prov['pk'],
    'application_id': app['pk'],
    'client_id': prov['client_id'],
    'client_secret': prov['client_secret'],
    'discovery_uri': f"https://{authentik_domain}/application/o/nextcloud/.well-known/openid-configuration",
    'issuer': f"https://{authentik_domain}/application/o/nextcloud/"
}

print("\n" + "="*60)
print("SUCCESS!")
print("="*60)
print(json.dumps(result, indent=2))
