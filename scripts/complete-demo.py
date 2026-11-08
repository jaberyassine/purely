"""Repair the legacy identity-reader mapping and verify the temporary demo end to end.

Credentials/JWTs are never printed or written to the public reports. Only
reserved example.invalid fixture accounts and their own carts/orders are used.
"""
import base64
import csv
import json
import re
import secrets
import ssl
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

workspace, kubectl, roots, report = map(Path, sys.argv[1:5])
project = workspace / 'purely-ready'
private = project / '.validation/private-runtime'
kubeconfig = project / '.validation/aks/purely-demo.kubeconfig'
endpoint = json.loads((project / '.validation/frontend-tls/endpoint.json').read_text(encoding='utf-8-sig'))
if not re.fullmatch(r'purely-demo-71154f86(?:\.[a-z0-9-]+)?\.eastus\.cloudapp\.azure\.com', endpoint['Domain']):
    raise RuntimeError('Unexpected public demo endpoint')
origin = 'https://' + endpoint['Domain']
context = ssl.create_default_context(cafile=str(roots))
mail_context = ssl.create_default_context(cafile=str(private / 'ca.crt'))
report.mkdir(parents=True, exist_ok=True)
rows = []
current = 'initialization'

def record(name, detail=''):
    rows.append({'Check': name, 'Status': 'PASS', 'Detail': detail})
    save_report()
    print('[PASS] ' + name, flush=True)

def save_report():
    with (report / 'business-results.csv').open('w', newline='', encoding='utf-8') as output:
        writer = csv.DictWriter(output, fieldnames=['Check', 'Status', 'Detail'])
        writer.writeheader()
        writer.writerows(rows)

def kubernetes(arguments, payload=None):
    result = subprocess.run([str(kubectl), '--kubeconfig=' + str(kubeconfig), '--context=purely-demo', '--request-timeout=60s'] + arguments,
                            input=payload, text=True, encoding='utf-8', capture_output=True)
    if result.returncode:
        raise RuntimeError('Kubernetes operation failed during ' + current + '; cluster credentials and private payloads were not logged')
    return result.stdout

def mongo_script(text):
    result = kubernetes(['exec', '-i', 'mongodb-0', '-n', 'purely-data', '--', 'mongosh', '--quiet', '--tls', '--tlsCAFile', '/etc/mongodb/tls/ca.crt', '--host', 'localhost', '--file', '/dev/stdin'], text)
    if 'PASS:' not in result:
        raise RuntimeError('Database verification did not report success')

def apply_secret(namespace, name, values):
    owner = kubernetes(['get', 'secret', name, '-n', namespace, '--ignore-not-found', '-o', r'jsonpath={.metadata.name}:{.metadata.labels.purely\.io/bootstrap}']).strip()
    if owner not in ('', ':', name + ':runtime-v1'):
        raise RuntimeError('Refusing to overwrite an independently managed runtime Secret')
    encoded = {key: base64.b64encode(value if isinstance(value, bytes) else value.encode()).decode() for key, value in values.items()}
    payload = {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'Opaque', 'metadata': {'name': name, 'namespace': namespace, 'labels': {'purely.io/bootstrap': 'runtime-v1'}}, 'data': encoded}
    kubernetes(['apply', '--server-side', '--field-manager=purely-runtime', '-f', '-'], json.dumps(payload))

def api(name, path, method='GET', body=None, token=None, status=200):
    headers = {'Accept': 'application/json'}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = Request(origin + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        with urlopen(request, context=context, timeout=30) as response:
            actual, raw = response.status, response.read()
    except HTTPError as error:
        actual, raw = error.code, error.read()
    if actual != status:
        raise RuntimeError(name + ': HTTP ' + str(actual) + ', expected ' + str(status))
    try:
        payload = json.loads(raw)
    except (ValueError, UnicodeError):
        raise RuntimeError(name + ': invalid JSON response') from None
    if 200 <= status < 300 and payload.get('success') is not True:
        raise RuntimeError(name + ': response did not report success=true')
    return payload

def wait_read(name, path, token=None):
    for attempt in range(30):
        try:
            return api(name, path, token=token)
        except RuntimeError:
            if attempt == 29:
                raise
            time.sleep(2)

def mail_json(path, settings):
    authorization = base64.b64encode((settings['uiUser'] + ':' + settings['uiPassword']).encode()).decode()
    request = Request('https://localhost:18025' + path, headers={'Authorization': 'Basic ' + authorization})
    with urlopen(request, context=mail_context, timeout=10) as response:
        return json.load(response)

def verify_email(account, mailbox):
    previous = {message['ID'] for message in mail_json('/api/v1/messages?limit=50', mailbox).get('messages', [])}
    api('request verification email', '/auth-service/auth/signup/resend?' + urlencode({'email': account['email']}))
    for attempt in range(30):
        messages = mail_json('/api/v1/messages?limit=50', mailbox).get('messages', [])
        for message in messages:
            if message['ID'] in previous:
                continue
            if any(recipient.get('Address', '').lower() == account['email'].lower() for recipient in message.get('To', [])):
                detail = mail_json('/api/v1/message/' + message['ID'], mailbox)
                match = re.search(r'verification code:\s*<strong>(\d{1,6})</strong>', detail.get('HTML', ''), re.IGNORECASE)
                if match:
                    api('verify captured email code', '/auth-service/auth/signup/verify?' + urlencode({'code': match.group(1)}), status=202)
                    return
        time.sleep(1)
    raise RuntimeError('No verification email/code was captured for the reserved fixture account')

def main():
    global current
    current = 'collection-scoped identity reader migration'
    settings_path = private / 'database-users.json'
    settings = json.loads(settings_path.read_text(encoding='utf-8-sig'))
    auth = next(account for account in settings['services'] if account['service'] == 'auth-service')
    reader = next(account for account in settings['services'] if account['service'] == 'user-service')
    if auth['database'] != 'purely_auth' or reader['database'] != 'purely_user':
        raise RuntimeError('Unexpected demo identity mapping')
    mongo_script((project / 'deploy-support/mongodb/repair-user-directory.js').read_text())
    backup = private / 'database-users.before-directory-fix.json'
    if not backup.exists():
        backup.write_bytes(settings_path.read_bytes())
    reader.update(dataDatabase=auth['database'], accessMode='identity-readonly')
    settings_path.write_text(json.dumps(settings, indent=2), encoding='utf-8')
    uri = 'mongodb://' + reader['user'] + ':' + reader['password'] + '@mongodb.purely-data.svc.cluster.local:27017/' + auth['database'] + '?authSource=' + reader['database'] + '&tls=true'
    apply_secret('user-service', 'mongodb-secret', {'uri': uri})
    bootstrap = {'users.json': json.dumps({key: settings[key] for key in ['admin', 'services', 'persistenceToken']})}
    for name in ['bootstrap.js', 'verify.js', 'persistence.js']:
        bootstrap[name] = (project / 'deploy-support/mongodb' / name).read_bytes()
    apply_secret('purely-data', 'mongodb-bootstrap', bootstrap)
    kubernetes(['rollout', 'restart', 'deployment/user-service', '-n', 'user-service'])
    kubernetes(['rollout', 'status', 'deployment/user-service', '-n', 'user-service', '--timeout=300s'])
    record('identity-directory-scope', 'User service reads only auth Users; writes and Roles reads denied. Other database accounts unchanged.')

    current = 'reserved demonstration accounts'
    accounts_path = private / 'demo-accounts.json'
    if not accounts_path.exists():
        suffix = secrets.token_hex(3)
        accounts = {'suffix': suffix}
        for kind, username in [('admin', 'demoAdmin'), ('customer', 'demoBuyer'), ('other', 'demoOther')]:
            accounts[kind] = {'email': kind + '-' + suffix + '@example.invalid', 'username': username + suffix, 'password': 'T!' + secrets.token_hex(8)}
        accounts_path.write_text(json.dumps(accounts, indent=2), encoding='utf-8')
    accounts = json.loads(accounts_path.read_text(encoding='utf-8-sig'))
    if not re.fullmatch(r'[a-f0-9]{6}', accounts['suffix']):
        raise RuntimeError('Unexpected fixture account namespace')
    for kind in ['admin', 'customer', 'other']:
        account = accounts[kind]
        if account['email'] != kind + '-' + accounts['suffix'] + '@example.invalid':
            raise RuntimeError('Refusing to operate on a non-fixture account')
        try:
            api('public signup', '/auth-service/auth/signup', 'POST', {'userName': account['username'], 'email': account['email'], 'password': account['password'], 'roles': ['admin']}, status=201)
        except RuntimeError as error:
            if 'HTTP 409, expected 201' not in str(error):
                raise
    mailbox = json.loads((private / 'mailbox-users.json').read_text(encoding='utf-8-sig'))
    verify_email(accounts['customer'], mailbox)
    record('verification-email', 'Captured email delivered through notification-service; verification endpoint accepted the code.')
    identities = {}
    for kind in ['admin', 'customer', 'other']:
        account = accounts[kind]
        identities[kind] = api('sign in fixture', '/auth-service/auth/signin', 'POST', {'email': account['email'], 'password': account['password']})['response']
    customer, other = identities['customer'], identities['other']
    if customer['roles'] != ['ROLE_USER'] or other['roles'] != ['ROLE_USER']:
        raise RuntimeError('Public registration accepted a caller-selected administrator role')
    api('wrong password rejected', '/auth-service/auth/signin', 'POST', {'email': accounts['customer']['email'], 'password': 'incorrect-password'}, status=401)
    record('authentication', 'Public signup cannot elevate privileges; correct password works and incorrect password is rejected.')

    current = 'cross-service user lookup'
    profile = wait_read('new identity visible through user service', '/user-service/user/get/byId?' + urlencode({'id': customer['id']}))
    if profile['response']['userId'] != customer['id'] or profile['response']['email'] != accounts['customer']['email']:
        raise RuntimeError('User service did not return the newly registered identity')
    record('identity-api', 'Auth-created identity is readable through user-service with the collection-scoped account.')

    current = 'operator-owned fixture administrator'
    fixture = {'email': accounts['admin']['email'], 'id': identities['admin']['id']}
    if identities['admin']['roles'] not in (['ROLE_USER'], ['ROLE_ADMIN']):
        raise RuntimeError('Unexpected fixture administrator roles')
    promotion = '''
const config=JSON.parse(require('fs').readFileSync('/bootstrap/users.json','utf8'));
if(!db.getSiblingDB('admin').auth(config.admin.user,config.admin.password))throw Error('Admin authentication failed');
const account=config.services.find(a=>a.service==='auth-service');
const identity=db.getSiblingDB(account.database);
const user=identity.Users.findOne({email:fixture.email});
if(!user||String(user._id)!==fixture.id||!/^admin-[a-f0-9]{6}@example\\.invalid$/.test(user.email))throw Error('Refusing non-fixture promotion');
const role=identity.Roles.findOne({name:'ROLE_ADMIN'});
if(!role)throw Error('Admin application role was not seeded');
identity.Users.updateOne({_id:user._id,email:fixture.email},{$set:{roles:[role]}});
print('PASS: only the reserved fixture administrator was provisioned.');
'''
    mongo_script('const fixture=' + json.dumps(fixture) + ';\n' + promotion)
    admin = api('operator-provisioned admin sign in', '/auth-service/auth/signin', 'POST', {'email': accounts['admin']['email'], 'password': accounts['admin']['password']})['response']
    if admin['roles'] != ['ROLE_ADMIN']:
        raise RuntimeError('The reserved fixture administrator was not provisioned')
    record('fixture-administration', 'Admin role assigned only through the operator to the reserved fixture, never public signup.')

    current = 'catalog and admin authorization'
    image_path = '/categories/6773f28a0f5832bdbc95ebbd.jpg'
    with urlopen(origin + image_path, context=context, timeout=10) as image:
        if image.status != 200 or not image.headers.get('Content-Type', '').startswith('image/'):
            raise RuntimeError('The bundled catalog image was not served')
    category_name = 'Demo Wellness ' + accounts['suffix']
    catalog = api('read categories', '/category-service/category/get/all')['response']
    category = next((item for item in catalog if item['categoryName'] == category_name), None)
    if not category:
        api('admin create category', '/category-service/admin/category/create', 'POST', {'name': category_name, 'description': 'Temporary demonstration catalog', 'imageUrl': image_path}, admin['token'])
        category = next(item for item in api('read created category', '/category-service/category/get/all')['response'] if item['categoryName'] == category_name)
    product_name = 'Demo Wellness Kit ' + accounts['suffix']
    products = api('read catalog', '/product-service/product/get/all')['response']
    product = next((item for item in products if item['productName'] == product_name), None)
    if not product:
        api('admin create product', '/product-service/admin/product/add', 'POST', {'productName': product_name, 'description': 'Demonstration item for checkout validation. Not for sale.', 'price': 25, 'imageUrl': image_path, 'categoryId': category['id']}, admin['token'])
        product = next(item for item in api('read created product', '/product-service/product/get/all')['response'] if item['productName'] == product_name)
    if product['price'] != 25:
        raise RuntimeError('Fixture price differs from the expected amount')
    api('user denied admin write', '/category-service/admin/category/create', 'POST', {'name': 'must-not-create-' + accounts['suffix'], 'description': 'Forbidden fixture', 'imageUrl': image_path}, customer['token'], status=403)
    api('anonymous cart rejected', '/cart-service/cart/get/byUser', status=401)
    record('catalog-authorization', 'Category/product created through admin APIs, bundled image served, normal user and anonymous access controls verified.')

    current = 'cart ownership and totals'
    cart = wait_read('read own cart', '/cart-service/cart/get/byUser', customer['token'])['response']
    if cart['noOfCartItems']:
        api('clear own reserved fixture cart', '/cart-service/cart/clear/byId?' + urlencode({'id': cart['cartId']}), 'DELETE', token=customer['token'])
    api('add fixture product', '/cart-service/cart/add', 'POST', {'productId': product['id'], 'quantity': 1}, customer['token'])
    cart = api('read populated cart', '/cart-service/cart/get/byUser', token=customer['token'])['response']
    if cart['noOfCartItems'] != 1 or cart['subtotal'] != 25 or len(cart['cartItems']) != 1:
        raise RuntimeError('Cart contents or subtotal are incorrect')
    api('foreign cart read rejected', '/cart-service/cart/get/byId?' + urlencode({'id': cart['cartId']}), token=other['token'], status=404)
    api('foreign cart clear rejected', '/cart-service/cart/clear/byId?' + urlencode({'id': cart['cartId']}), 'DELETE', token=other['token'], status=404)
    record('cart', 'One item, subtotal 25; another user cannot read or clear the cart.')

    current = 'order checkout and ownership'
    before = api('read own orders', '/order-service/order/get/byUser', token=customer['token'])['response']
    old_ids = {item['id'] for item in before}
    api('create order', '/order-service/order/create', 'POST', {'cartId': cart['cartId'], 'firstName': 'Demo', 'lastName': 'Buyer', 'addressLine1': 'Demonstration address', 'addressLine2': '', 'city': 'Demo', 'phoneNo': '0000000000'}, customer['token'])
    orders = api('read created order', '/order-service/order/get/byUser', token=customer['token'])['response']
    created = [item for item in orders if item['id'] not in old_ids]
    if len(created) != 1 or created[0]['orderAmt'] != 25 or created[0]['orderStatus'] != 'PENDING' or created[0]['userId'] != customer['id']:
        raise RuntimeError('The new order does not match the customer/cart')
    order = created[0]
    cart = api('cart cleared after checkout', '/cart-service/cart/get/byUser', token=customer['token'])['response']
    if cart['noOfCartItems'] != 0 or cart['subtotal'] != 0:
        raise RuntimeError('Cart was not cleared after checkout')
    api('foreign cancellation rejected', '/order-service/order/cancel?' + urlencode({'orderId': order['id']}), 'PATCH', token=other['token'], status=404)
    api('owner cancels own fixture order', '/order-service/order/cancel?' + urlencode({'orderId': order['id']}), 'PATCH', token=customer['token'])
    cancelled = next(item for item in api('read cancelled order', '/order-service/order/get/byUser', token=customer['token'])['response'] if item['id'] == order['id'])
    if cancelled['orderStatus'] != 'CANCELLED':
        raise RuntimeError('Owner cancellation was not persisted')
    record('order', 'Amount 25/PENDING persisted, cart cleared, foreign cancellation rejected, owner cancellation persisted.')
    (report / 'demo-summary.json').write_text(json.dumps({'PublicUrl': origin, 'CategoryId': category['id'], 'ProductId': product['id'], 'VerifiedOrderId': order['id'], 'ChecksPassed': len(rows)}, indent=2))
    print('[PASS] Deployed business flow verified. Reserved demo credentials remain in the private runtime directory; no JWTs were saved.', flush=True)

try:
    main()
except Exception as error:
    rows.append({'Check': current, 'Status': 'FAIL', 'Detail': type(error).__name__ + ': ' + str(error)[:240]})
    save_report()
    print('[FAIL] ' + current + ': ' + str(error)[:240], flush=True)
    sys.exit(1)
