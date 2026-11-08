"""Connect a dedicated datasource, verify real metrics, and open a managed dashboard.

Uses existing local credentials only. No passwords, tokens or complete datasource
responses are written to public reports. Existing dashboards are preserved.
"""
import base64
import csv
import json
import math
import re
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, ProxyHandler, build_opener


def main():
    project, report = map(Path, sys.argv[1:3])
    prom_url = sys.argv[3]
    if not re.fullmatch(r'http://[a-z0-9-]+\.monitoring\.svc\.cluster\.local:9090', prom_url):
        raise RuntimeError('Unexpected internal Prometheus endpoint')
    credentials = json.loads((project / '.validation/private-runtime/monitoring-users.json').read_text(encoding='utf-8-sig'))
    if credentials['user'] != 'demo-admin':
        raise RuntimeError('Unexpected Grafana administrator')
    authorization = 'Basic ' + base64.b64encode((credentials['user'] + ':' + credentials['password']).encode()).decode()
    origin = 'http://127.0.0.1:3000'
    local_http = build_opener(ProxyHandler({}))
    report.mkdir(parents=True, exist_ok=True)
    checks = []

    def record(name, status, detail):
        checks.append({'Check': name, 'Status': status, 'Detail': detail})
        with (report / 'checks.csv').open('w', newline='', encoding='utf-8') as output:
            writer = csv.DictWriter(output, fieldnames=['Check', 'Status', 'Detail'])
            writer.writeheader()
            writer.writerows(checks)
        print('[' + status + '] ' + name + ': ' + detail, flush=True)

    def api(path, body=None, method=None, allow_missing=False):
        headers = {'Authorization': authorization, 'Accept': 'application/json'}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        request = Request(origin + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
        try:
            with local_http.open(request, timeout=25) as response:
                return json.load(response)
        except HTTPError as error:
            if error.code == 404 and allow_missing:
                return None
            raise RuntimeError('Grafana API HTTP ' + str(error.code) + ' at ' + path.split('?')[0]) from None

    try:
        user = api('/api/user')
        if user.get('login') != credentials['user']:
            raise RuntimeError('Unexpected Grafana login')
        record('Grafana login', 'PASS', 'Existing administrator authenticated; password not logged.')
        uid = 'purely-prometheus'
        datasource = api('/api/datasources/uid/' + uid, allow_missing=True)
        if datasource is None:
            api('/api/datasources', {'name': 'Purely Prometheus', 'uid': uid, 'type': 'prometheus', 'access': 'proxy',
                                    'url': prom_url, 'isDefault': False, 'basicAuth': False,
                                    'jsonData': {'httpMethod': 'POST', 'timeInterval': '15s'}})
        elif datasource.get('type') != 'prometheus' or datasource.get('url', '').rstrip('/') != prom_url:
            raise RuntimeError('Existing dedicated datasource differs; stop before overwriting it')
        health = api('/api/datasources/uid/' + uid + '/health')
        if str(health.get('status')).upper() != 'OK':
            raise RuntimeError('Grafana cannot reach Prometheus through the internal Service')
        record('Prometheus datasource', 'PASS', 'Grafana server can query ' + prom_url)

        def query(expression):
            payload = api('/api/datasources/proxy/uid/' + uid + '/api/v1/query?' + urlencode({'query': expression}))
            if payload.get('status') != 'success':
                raise RuntimeError('Prometheus rejected a dashboard query')
            return payload['data']['result']

        namespaces = {'api-gateway', 'auth-service', 'cart-service', 'category-service', 'notification-service', 'order-service', 'product-service', 'service-registry', 'user-service'}
        samples = query('up{namespace=~"' + '|'.join(sorted(namespaces)) + '"}')
        if not samples:
            raise RuntimeError('Prometheus returned no Purely scrape targets; dashboard data cannot yet be verified')
        seen = {sample['metric'].get('namespace') for sample in samples}
        failed = sum(sample['value'][1] != '1' for sample in samples)
        record('Live application metrics', 'PASS', str(len(samples)) + ' scrape targets in ' + str(len(seen)) + ' namespaces; failed scrapes=' + str(failed))
        if namespaces - seen:
            record('Missing monitored namespaces', 'WARN', ', '.join(sorted(namespaces - seen)))
        dashboard = json.loads((project / 'k8s/observability/dashboards/purely-live.json').read_text())
        if dashboard['uid'] != 'purely-live-overview' or 'purely-managed' not in dashboard.get('tags', []):
            raise RuntimeError('Unexpected managed dashboard source')
        existing = api('/api/dashboards/uid/' + dashboard['uid'], allow_missing=True)
        if existing and 'purely-managed' not in existing['dashboard'].get('tags', []):
            raise RuntimeError('An independently managed dashboard uses this UID; stop before replacement')
        if existing:
            (report / 'dashboard-before.json').write_text(json.dumps(existing['dashboard'], indent=2), encoding='utf-8')
        if not existing or not existing.get('meta', {}).get('provisioned'):
            if existing:
                dashboard['id'] = existing['dashboard']['id']
                dashboard['version'] = existing['dashboard'].get('version', 0)
            api('/api/dashboards/db', {'dashboard': dashboard, 'overwrite': True,
                                     'message': 'Purely live metrics dashboard setup'})
        actual = api('/api/dashboards/uid/' + dashboard['uid'])['dashboard']
        if len(actual.get('panels', [])) != 10:
            raise RuntimeError('The managed dashboard does not contain the expected ten panels')
        record('Purely live dashboard', 'PASS', 'Ten panels saved; other dashboards preserved.')
        for panel in actual['panels']:
            if panel.get('datasource', {}).get('uid') != uid:
                raise RuntimeError('Dashboard datasource UID is inconsistent')
            result = query(panel['targets'][0]['expr'])
            finite = 0
            for series in result:
                value = series.get('value', [None, 'NaN'])[1]
                try:
                    finite += math.isfinite(float(value))
                except (ValueError, TypeError):
                    pass
            record(panel['title'], 'PASS' if finite else 'NO_SAMPLES', str(finite) + ' live series; empty/NaN values are not replaced with invented data.')
        preferences = api('/api/user/preferences')
        (report / 'preferences-before.json').write_text(json.dumps(preferences, indent=2), encoding='utf-8')
        updated = {key: preferences[key] for key in ['theme', 'timezone', 'weekStart'] if key in preferences}
        updated['homeDashboardUID'] = dashboard['uid']
        api('/api/user/preferences', updated, 'PUT')
        if api('/api/user/preferences').get('homeDashboardUID') != dashboard['uid']:
            raise RuntimeError('Grafana home dashboard preference did not persist')
        record('Grafana home page', 'PASS', 'Purely live overview is now the current administrator home dashboard.')
        print('[OPEN] ' + origin + '/d/purely-live-overview', flush=True)
    except Exception as error:
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        record('Grafana setup', 'FAIL', message)
        raise RuntimeError(message) from None


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('[FAIL] ' + (str(error) if isinstance(error, RuntimeError) else type(error).__name__), flush=True)
        sys.exit(1)
