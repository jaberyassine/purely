"""Add the bundled ten-item demonstration catalog through authenticated APIs.

Existing names are preserved. Passwords and tokens stay in memory and are never
logged. Catalog images use verified source photos with bundled category fallback.
"""
import csv
import json
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def main():
    project, report = map(Path, sys.argv[1:3])
    endpoint = json.loads((project / '.validation/frontend-tls/endpoint.json').read_text(encoding='utf-8-sig'))
    if endpoint['Domain'] != 'purely-demo-71154f86.eastus.cloudapp.azure.com':
        raise RuntimeError('Unexpected demo endpoint')
    origin = 'https://' + endpoint['Domain']
    context = ssl.create_default_context(cafile=r'C:\Program Files\Git\mingw64\etc\ssl\cert.pem')
    accounts = json.loads((project / '.validation/private-runtime/demo-accounts.json').read_text(encoding='utf-8-sig'))
    admin = accounts['admin']
    if admin['email'] != 'admin-' + accounts['suffix'] + '@example.invalid':
        raise RuntimeError('Expected the reserved demo administrator')
    token = None

    def api(path, body=None, expected=200):
        headers = {'Accept': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        if body is not None:
            headers['Content-Type'] = 'application/json'
        request = Request(origin + path, data=None if body is None else json.dumps(body).encode(), headers=headers)
        try:
            with urlopen(request, context=context, timeout=30) as response:
                if response.status != expected:
                    raise RuntimeError('Unexpected API status')
                data = json.load(response)
        except HTTPError as error:
            raise RuntimeError('Catalog API HTTP ' + str(error.code)) from None
        if data.get('success') is not True:
            raise RuntimeError('Catalog API did not report success')
        return data.get('response')

    def image_available(url):
        if urlparse(url).scheme != 'https':
            return False
        try:
            with urlopen(Request(url, headers={'User-Agent': 'Purely-Demo-Catalog/1.0'}), context=context, timeout=6) as response:
                return response.status == 200 and response.headers.get('Content-Type', '').startswith('image/') and bool(response.read(32))
        except (HTTPError, URLError, TimeoutError, OSError):
            return False

    identity = api('/auth-service/auth/signin', {'email': admin['email'], 'password': admin['password']})
    if identity['roles'] != ['ROLE_ADMIN']:
        raise RuntimeError('The reserved account is not an administrator')
    token = identity['token']
    categories = json.loads((project / 'sample data/purely_category_service.categories.json').read_text(encoding='utf-8-sig'))
    products = json.loads((project / 'sample data/purely_product_service.products.json').read_text(encoding='utf-8-sig'))
    if len(categories) != 5 or len(products) != 10:
        raise RuntimeError('Unexpected bundled demo catalog')
    existing_categories = {item['categoryName']: item for item in api('/category-service/category/get/all')}
    mappings = {}
    for category in categories:
        fallback = '/categories/' + category['imageUrl']
        if not image_available(origin + fallback):
            raise RuntimeError('Bundled category image is unavailable')
        name = category['categoryName']
        if name not in existing_categories:
            api('/category-service/admin/category/create', {'name': name, 'description': 'Purely demonstration collection. Items and prices are for demo use.', 'imageUrl': category['imageUrl']})
            existing_categories = {item['categoryName']: item for item in api('/category-service/category/get/all')}
        mappings[category['_id']['$oid']] = (existing_categories[name]['id'], fallback)
        print('[PASS] Category: ' + name, flush=True)
    existing_products = {item['productName']: item for item in api('/product-service/product/get/all')}
    rows = []
    report.mkdir(parents=True, exist_ok=True)

    def save():
        with (report / 'catalog-results.csv').open('w', newline='', encoding='utf-8') as output:
            writer = csv.DictWriter(output, fieldnames=['Product', 'Price', 'Id', 'Status', 'Image'])
            writer.writeheader()
            writer.writerows(rows)

    for product in products:
        name = product['productName']
        category_id, fallback = mappings[product['categoryId']]
        status = 'Existing'
        if name not in existing_products:
            image = product['imageUrl'] if image_available(product['imageUrl']) else fallback
            api('/product-service/admin/product/add', {'productName': name, 'price': product['price'],
                'description': name + ' — demonstration catalog item. Illustrative image and price; not a live sales listing.',
                'imageUrl': image, 'categoryId': category_id})
            existing_products = {item['productName']: item for item in api('/product-service/product/get/all')}
            status = 'Created'
        item = existing_products.get(name)
        if not item:
            raise RuntimeError('Created product is missing from the public catalog')
        rows.append({'Product': name, 'Price': item['price'], 'Id': item['id'], 'Status': status, 'Image': item['imageUrl']})
        save()
        print('[PASS] ' + status + ': ' + name, flush=True)
    public = {item['id'] for item in api('/product-service/product/get/all')}
    if not all(row['Id'] in public for row in rows):
        raise RuntimeError('Public catalog verification failed')
    print('[PASS] Ten demo products visible in five categories. Existing products were preserved; no passwords or tokens were logged.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Avoid arbitrary HTTP response bodies or tracebacks containing private data.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('[FAIL] ' + message, flush=True)
        sys.exit(1)
