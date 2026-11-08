"""Read-only routing diagnostics; no credentials, request bodies or tokens logged."""
import csv
import json
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

project, report = map(Path, sys.argv[1:3])
endpoint = json.loads((project / '.validation/frontend-tls/endpoint.json').read_text(encoding='utf-8-sig'))
if endpoint['Domain'] != 'purely-demo-71154f86.eastus.cloudapp.azure.com':
    raise RuntimeError('Unexpected demo endpoint')
context = ssl.create_default_context(cafile=r'C:\Program Files\Git\mingw64\etc\ssl\cert.pem')
registry_request = Request('http://127.0.0.1:18761/eureka/apps', headers={'Accept': 'application/json'})
with urlopen(registry_request, timeout=15) as response:
    payload = json.load(response)
apps = payload.get('applications', {}).get('application', [])
if isinstance(apps, dict):
    apps = [apps]
rows = []
for app in apps:
    instances = app.get('instance', [])
    if isinstance(instances, dict):
        instances = [instances]
    for instance in instances:
        port = instance.get('port', {})
        rows.append({'Application': app.get('name'), 'Status': instance.get('status'),
                     'IP': instance.get('ipAddr'), 'Port': port.get('$') if isinstance(port, dict) else port})
with (report / 'registry-instances.csv').open('w', newline='', encoding='utf-8') as output:
    writer = csv.DictWriter(output, fieldnames=['Application', 'Status', 'IP', 'Port'])
    writer.writeheader()
    writer.writerows(rows)
print('[REGISTRY] ' + json.dumps(rows), flush=True)
results = []
for name, path, body in [('auth-validation', '/auth-service/auth/signin', b'{}'),
                         ('catalog', '/product-service/product/get/all', None),
                         ('categories', '/category-service/category/get/all', None)]:
    request = Request('https://' + endpoint['Domain'] + path, data=body,
                      headers={'Accept': 'application/json', 'Content-Type': 'application/json'})
    try:
        response = urlopen(request, context=context, timeout=15)
    except HTTPError as error:
        response = error
    with response:
        status = response.status
        try:
            data = json.load(response)
        except (ValueError, UnicodeError):
            data = {}
        # Log the error class, never the arbitrary response message/body.
        result = {'Check': name, 'HTTP': status, 'Error': data.get('error'), 'Success': data.get('success')}
        results.append(result)
        print('[ROUTE] ' + json.dumps(result), flush=True)
(report / 'public-routes.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
