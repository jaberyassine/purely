"""Wait for Eureka registrations and verify public routes before business tests."""
import json
import ssl
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

project, report = map(Path, sys.argv[1:3])
domain = json.loads((project / '.validation/frontend-tls/endpoint.json').read_text(encoding='utf-8-sig'))['Domain']
if domain != 'purely-demo-71154f86.eastus.cloudapp.azure.com':
    raise RuntimeError('Unexpected public endpoint')
context = ssl.create_default_context(cafile=r'C:\Program Files\Git\mingw64\etc\ssl\cert.pem')
expected = {'API-GATEWAY', 'AUTH-SERVICE', 'CART-SERVICE', 'CATEGORY-SERVICE', 'NOTIFICATION-SERVICE', 'ORDER-SERVICE', 'PRODUCT-SERVICE', 'USER-SERVICE'}
for attempt in range(60):
    try:
        request = Request('http://127.0.0.1:18761/eureka/apps', headers={'Accept': 'application/json'})
        with urlopen(request, timeout=10) as response:
            apps = json.load(response)['applications'].get('application', [])
        if isinstance(apps, dict):
            apps = [apps]
        seen = set()
        for app in apps:
            instances = app.get('instance', [])
            if isinstance(instances, dict):
                instances = [instances]
            if any(instance.get('status') == 'UP' for instance in instances):
                seen.add(app['name'].upper())
        if expected.issubset(seen):
            print('[PASS] All eight application clients registered UP in Eureka.', flush=True)
            break
    except (HTTPError, URLError, TimeoutError):
        pass
    if attempt == 59:
        raise RuntimeError('Eureka did not report all expected application clients UP')
    time.sleep(3)
checks = [('auth-validation', '/auth-service/auth/signin', b'{}', 400),
          ('products', '/product-service/product/get/all', None, 200),
          ('categories', '/category-service/category/get/all', None, 200)]
results = []
for name, path, body, expected_status in checks:
    for attempt in range(30):
        request = Request('https://' + domain + path, data=body, headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urlopen(request, context=context, timeout=15) as response:
                status = response.status
                payload = json.load(response)
        except HTTPError as error:
            status = error.code
            payload = {}
        if status == expected_status:
            if status == 200 and payload.get('success') is not True:
                raise RuntimeError(name + ' returned success=false')
            results.append({'Check': name, 'HTTP': status})
            print('[PASS] Public ' + name + ': HTTP ' + str(status), flush=True)
            break
        if status != 503 or attempt == 29:
            raise RuntimeError(name + ': HTTP ' + str(status) + ', expected ' + str(expected_status))
        time.sleep(3)
(report / 'routing-results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
