"""Verify the internal mailbox over loopback-only port forwards, without printing credentials."""
import base64
import json
import smtplib
import ssl
import sys
import time
import uuid
from urllib.error import HTTPError
from email.message import EmailMessage
from pathlib import Path
from urllib.request import Request, urlopen

private = Path(sys.argv[1])
settings = json.loads((private / 'mailbox-users.json').read_text(encoding='utf-8-sig'))
context = ssl.create_default_context(cafile=str(private / 'ca.crt'))
subject = 'Purely deployment verification ' + uuid.uuid4().hex[:10]
with smtplib.SMTP('localhost', 11025, timeout=10) as denied_client:
    denied_client.ehlo()
    denied_client.starttls(context=context)
    denied_client.ehlo()
    try:
        denied_client.login(settings['smtpUser'], 'deliberately-incorrect-fixture-password')
        raise RuntimeError('Invalid SMTP credentials were accepted')
    except smtplib.SMTPAuthenticationError:
        pass
with smtplib.SMTP('localhost', 11025, timeout=10) as client:
    client.ehlo()
    # No real credentials are sent before STARTTLS.
    status, _ = client.docmd('AUTH', 'PLAIN ' + base64.b64encode(b'\0invalid\0invalid').decode())
    if status < 400:
        raise RuntimeError('SMTP authentication was not blocked before STARTTLS')
    client.starttls(context=context)
    client.ehlo()
    client.login(settings['smtpUser'], settings['smtpPassword'])
    message = EmailMessage()
    message['From'] = settings['smtpUser']
    message['To'] = 'fixture@example.invalid'
    message['Subject'] = subject
    message.set_content('Internal demonstration only. This message must remain in Mailpit.')
    client.send_message(message)

url = 'https://localhost:18025/api/v1/messages'
try:
    urlopen(url, context=context, timeout=5)
    raise RuntimeError('The mailbox API did not require authentication')
except HTTPError as error:
    if error.code not in (401, 403):
        raise
authorization = base64.b64encode((settings['uiUser'] + ':' + settings['uiPassword']).encode()).decode()
for attempt in range(10):
    request = Request(url, headers={'Authorization': 'Basic ' + authorization})
    with urlopen(request, context=context, timeout=5) as response:
        payload = json.load(response)
    if any(message.get('Subject') == subject for message in payload.get('messages', [])):
        print('PASS: verified SMTP STARTTLS and server certificate, authentication, rejected invalid credentials, protected HTTPS mailbox and captured delivery.')
        break
    time.sleep(1)
else:
    raise RuntimeError('The authenticated test message was not found in the mailbox')
