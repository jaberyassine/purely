#!/bin/sh
set -eu
python /opt/purely/warmup.py &
warmup=$!
trap 'kill "$warmup" 2>/dev/null || true' EXIT
# Give Azure's load balancer probes time to observe a listening backend.
sleep 60
kill "$warmup"
wait "$warmup" 2>/dev/null || true
trap - EXIT
certbot certonly --dry-run --standalone --preferred-challenges http --http-01-port 8080 \
    --config-dir /certs --work-dir /work --logs-dir /logs \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --key-type rsa --rsa-key-size 3072 --domain "$DOMAIN"
certbot certonly --standalone --preferred-challenges http --http-01-port 8080 \
    --config-dir /certs --work-dir /work --logs-dir /logs \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --key-type rsa --rsa-key-size 3072 --domain "$DOMAIN"
echo PURELY_CERTIFICATE_READY
# Hold the files for the authenticated operator to copy, then exit.
sleep 1800
