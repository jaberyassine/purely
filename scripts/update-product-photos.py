"""Replace demo category placeholders with distinct, product-specific photos.

Only the imageUrl field changes logically; the legacy edit API also requires
the current name, category, description and price. Public before/after records
are saved for reversal. Credentials and JWTs are never logged or saved.
"""
import csv
import hashlib
import json
import ssl
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


def main():
    project, report = map(Path, sys.argv[1:3])
    domain = json.loads((project / '.validation/frontend-tls/endpoint.json').read_text(encoding='utf-8-sig'))['Domain']
    if domain != 'purely-demo-71154f86.eastus.cloudapp.azure.com':
        raise RuntimeError('Unexpected demo endpoint')
    origin = 'https://' + domain
    context = ssl.create_default_context(cafile=r'C:\Program Files\Git\mingw64\etc\ssl\cert.pem')
    accounts = json.loads((project / '.validation/private-runtime/demo-accounts.json').read_text(encoding='utf-8-sig'))
    admin = accounts['admin']
    if admin['email'] != 'admin-' + accounts['suffix'] + '@example.invalid':
        raise RuntimeError('Expected the reserved demo administrator')
    token = None

    def api(path, body=None, method=None):
        headers = {'Accept': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        if body is not None:
            headers['Content-Type'] = 'application/json'
        request = Request(origin + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
        try:
            with urlopen(request, context=context, timeout=30) as response:
                result = json.load(response)
        except HTTPError as error:
            raise RuntimeError('Product API HTTP ' + str(error.code)) from None
        if result.get('success') is not True:
            raise RuntimeError('Product API did not report success')
        return result.get('response')

    identity = api('/auth-service/auth/signin', {'email': admin['email'], 'password': admin['password']})
    if identity['roles'] != ['ROLE_ADMIN']:
        raise RuntimeError('Expected administrator role')
    token = identity['token']
    manifest = json.loads((project / 'sample data/demo-product-photos.json').read_text(encoding='utf-8-sig'))
    if len(manifest) != 26 or len({item['url'] for item in manifest}) != 26:
        raise RuntimeError('Expected 26 distinct photo mappings')
    original = json.loads((project / 'sample data/purely_product_service.products.json').read_text(encoding='utf-8-sig'))
    alternatives = {item['productName']: item['imageUrl'] for item in original}
    products = api('/product-service/product/get/all')
    plan = []
    for photo in manifest:
        matches = [item for item in products if item['productName'] == photo['product'] or
                   (photo['product'] == 'Demo Wellness Kit' and item['productName'] == 'Demo Wellness Kit ' + accounts['suffix'])]
        if len(matches) > 1:
            raise RuntimeError('Duplicate demo product names; stop before modification')
        if matches:
            plan.append((matches[0], photo))
    if not plan:
        raise RuntimeError('No seeded demo products found')
    report.mkdir(parents=True, exist_ok=True)
    (report / 'products-before.json').write_text(json.dumps([item for item, _ in plan], indent=2), encoding='utf-8')

    def check(entry):
        product, photo = entry
        candidates = list(dict.fromkeys([photo['url'], alternatives.get(photo['product'])]))
        for url in candidates:
            if not url or urlparse(url).scheme != 'https':
                continue
            try:
                request = Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'image/avif,image/webp,image/*;q=0.9,*/*;q=0.8'})
                with urlopen(request, context=context, timeout=15) as response:
                    if response.status != 200 or urlparse(response.url).scheme != 'https' or not response.headers.get('Content-Type', '').startswith('image/'):
                        continue
                    data = response.read(8 * 1024 * 1024 + 1)
                    if not data or len(data) > 8 * 1024 * 1024:
                        continue
                return product, url, hashlib.sha256(data).hexdigest()
            except (HTTPError, URLError, TimeoutError, OSError):
                continue
        return product, None, None

    print('[VERIFY] Checking individual product photos and detecting repeated image content.', flush=True)
    with ThreadPoolExecutor(max_workers=6) as pool:
        checked = list(pool.map(check, plan))
    rows, hashes, selected = [], set(), {}
    for product, url, digest in checked:
        name = product['productName']
        if not url or digest in hashes:
            rows.append({'Product': name, 'Status': 'NEEDS_PHOTO', 'Image': '', 'Id': product['id']})
            print('[NEEDS_PHOTO] ' + name, flush=True)
            continue
        hashes.add(digest)
        # Preserve every non-image field; do not create or delete products.
        payload = {key: product[key] for key in ['productName', 'price', 'description', 'categoryId']}
        payload['imageUrl'] = url
        if product['imageUrl'] != url:
            api('/product-service/admin/product/edit?' + urlencode({'productId': product['id']}), payload, 'PUT')
        selected[product['id']] = payload
        rows.append({'Product': name, 'Status': 'UPDATED', 'Image': url, 'Id': product['id']})
        print('[PASS] Individual photo: ' + name, flush=True)
    with (report / 'photo-results.csv').open('w', newline='', encoding='utf-8') as output:
        writer = csv.DictWriter(output, fieldnames=['Product', 'Status', 'Image', 'Id'])
        writer.writeheader()
        writer.writerows(rows)
    after = {item['id']: item for item in api('/product-service/product/get/all')}
    for product_id, expected in selected.items():
        if product_id not in after or any(after[product_id].get(key) != value for key, value in expected.items()):
            raise RuntimeError('Public product photo verification failed')
    if any(row['Status'] != 'UPDATED' for row in rows):
        raise RuntimeError('Some photo hosts were unavailable. Working photos were applied; see photo-results.csv for remaining products')
    print('[PASS] ' + str(len(rows)) + ' products have distinct verified photos. Names, prices, descriptions and categories were preserved.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('[FAIL] ' + (str(error) if isinstance(error, RuntimeError) else type(error).__name__), flush=True)
        sys.exit(1)
