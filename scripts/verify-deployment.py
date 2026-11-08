"""Check public TLS/SPA, actuator blocking and real Prometheus application targets."""
import json
import ssl
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

endpoint = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
context = ssl.create_default_context(cafile=sys.argv[2])
url = 'https://' + endpoint['Domain']
for attempt in range(30):
    try:
        with urlopen(url, context=context, timeout=10) as response:
            content = response.read().decode()
            if response.status != 200 or '<!doctype html>' not in content.lower():
                raise RuntimeError('Frontend did not return the built application')
            if not response.headers.get('Strict-Transport-Security'):
                raise RuntimeError('The HTTPS response did not include HSTS')
        break
    except (HTTPError, URLError, TimeoutError):
        if attempt == 29:
            raise
        time.sleep(3)
for service in ['product-service', 'auth-service', 'order-service']:
    try:
        urlopen(url + '/' + service + '/actuator/health', context=context, timeout=10)
        raise RuntimeError('A backend actuator path was not blocked at the frontend')
    except HTTPError as error:
        if error.code != 404:
            raise
expected = {'api-gateway', 'auth-service', 'cart-service', 'category-service', 'notification-service', 'order-service', 'product-service', 'service-registry', 'user-service'}
query = 'up{namespace=~"' + '|'.join(sorted(expected)) + '"}'
for attempt in range(30):
    with urlopen('http://127.0.0.1:19090/api/v1/query?' + urlencode({'query': query}), timeout=10) as response:
        payload = json.load(response)
    if payload.get('status') != 'success':
        raise RuntimeError('Prometheus query failed')
    metrics = payload['data']['result']
    seen = {item['metric'].get('namespace') for item in metrics}
    if expected.issubset(seen) and all(item['value'][1] == '1' for item in metrics):
        break
    if attempt == 29:
        raise RuntimeError('Not all nine backend namespaces have healthy Prometheus scrape targets: ' + ','.join(sorted(expected - seen)))
    time.sleep(3)
print(json.dumps({'PublicUrl': url, 'TrustedTls': True, 'FrontendHtml': True, 'Hsts': True, 'ActuatorBlocked': True, 'HealthyBackendNamespaces': len(expected), 'HealthyApplicationTargets': len(metrics)}, indent=2))
