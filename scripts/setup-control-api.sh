#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
umask 077

# Run on the central production host after deploying the updated compose.prod.yml.
: "${LE_EMAIL:?Set LE_EMAIL to your Let's Encrypt contact email}"
: "${EDGE_AGENT_ALLOWED_IP:?Set EDGE_AGENT_ALLOWED_IP to the agent's observed public egress IPv4}"
[[ "$EDGE_AGENT_ALLOWED_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "Invalid EDGE_AGENT_ALLOWED_IP" >&2; exit 2; }
for octet in ${EDGE_AGENT_ALLOWED_IP//./ }; do
  (( 10#$octet <= 255 )) || { echo "Invalid IPv4 octet" >&2; exit 2; }
done

mkdir -p nginx/generated/api-vhosts www/certbot/.well-known/acme-challenge letsencrypt
test -s nginx/generated/default.conf || { echo "Missing nginx/generated/default.conf" >&2; exit 1; }
docker compose --env-file .env -f compose.yml -f compose.prod.yml ps nginx

# Verify the local Nginx webroot directly. A central server may have an outbound
# HTTP proxy or hairpin-NAT interception when accessing its own public IP.
# This local probe does not replace a separate external ACME reachability test.
probe="wraplink-acme-$$"
printf '%s\n' "$probe" > "www/certbot/.well-known/acme-challenge/$probe"
# umask 077 protects private files, but HTTP-01 tokens must be readable by Nginx.
chmod 644 "www/certbot/.well-known/acme-challenge/$probe"
trap 'rm -f "www/certbot/.well-known/acme-challenge/$probe"' EXIT
for domain in api.wraplink.ir dns-api.wraplink.ir; do
  actual="$(curl --noproxy '*' --resolve "$domain:80:127.0.0.1" --fail --silent --show-error --max-time 15 "http://$domain/.well-known/acme-challenge/$probe")" || {
    echo "ACME HTTP probe failed for $domain; do not request a certificate yet" >&2; exit 1;
  }
  [[ "$actual" == "$probe" ]] || { echo "Unexpected LOCAL ACME response from $domain: $actual" >&2; exit 1; }
done

echo "Local ACME probe passed. Ensure both hostnames were tested from an external network before issuing."
docker run --rm \
  -v "$PWD/letsencrypt:/etc/letsencrypt" \
  -v "$PWD/www/certbot:/var/www/certbot" \
  certbot/certbot:v3.3.0 certonly --webroot \
  -w /var/www/certbot --non-interactive --agree-tos \
  --email "$LE_EMAIL" --cert-name wraplink-control-api \
  -d api.wraplink.ir -d dns-api.wraplink.ir

# Restrict both API vhosts to the agent IP; upstream authentication still applies.
# Never trust an unverified X-Forwarded-For header for access control.
tmp="$(mktemp nginx/generated/api-vhosts/control-api.conf.XXXXXX)"
cat > "$tmp" <<CONF
server {
  listen 443 ssl;
  server_name api.wraplink.ir;
  ssl_certificate /etc/letsencrypt/live/wraplink-control-api/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/wraplink-control-api/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  allow $EDGE_AGENT_ALLOWED_IP;
  deny all;
  location / {
    proxy_pass http://backend:7080;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header X-Forwarded-Proto https;
    proxy_connect_timeout 10s;
    proxy_read_timeout 60s;
  }
}
server {
  listen 443 ssl;
  server_name dns-api.wraplink.ir;
  ssl_certificate /etc/letsencrypt/live/wraplink-control-api/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/wraplink-control-api/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  allow $EDGE_AGENT_ALLOWED_IP;
  deny all;
  location / {
    proxy_pass http://dns-control:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header X-Forwarded-Proto https;
    proxy_connect_timeout 10s;
    proxy_read_timeout 60s;
  }
}
CONF
chmod 644 "$tmp"
mv "$tmp" nginx/generated/api-vhosts/control-api.conf

# Remove API hostnames from the main website vhost. Older setup-ssl runs
# included these hostnames, which shadows the API vhosts and produces HTTP 404.
# Only edit the server_name directive that contains the primary website domain.
default_conf=nginx/generated/default.conf
backup="$(mktemp nginx/generated/default.conf.backup.XXXXXX)"
cp "$default_conf" "$backup"
normalized="$(mktemp nginx/generated/default.conf.normalized.XXXXXX)"
awk '
  /server_name[[:space:]]/ {
    directive=$0
    while (directive !~ /;/ && (getline line)>0) directive=directive " " line
    if (directive ~ /wraplink[.]ir/ && directive ~ /api[.]wraplink[.]ir/) {
      print "  server_name wraplink.ir www.wraplink.ir;"
    } else {
      print directive
    }
    next
  }
  {print}
' "$default_conf" > "$normalized"
cat "$normalized" > "$default_conf"
rm -f "$normalized"
if ! grep -Fq 'include /etc/nginx/api-vhosts/*.conf;' "$default_conf"; then
  printf '\ninclude /etc/nginx/api-vhosts/*.conf;\n' >> "$default_conf"
fi
# Reject duplicate server names or missing API vhosts; nginx -t alone may warn
# about duplicate names without failing.
test_output="$(docker exec wraplink-nginx-1 nginx -t 2>&1)" || {
  printf '%s\n' "$test_output" >&2
  cp "$backup" "$default_conf"
  exit 1
}
if grep -qi 'conflicting server name' <<< "$test_output"; then
  printf '%s\n' "$test_output" >&2
  cp "$backup" "$default_conf"
  exit 1
fi
if ! docker exec wraplink-nginx-1 nginx -s reload; then
  cp "$backup" "$default_conf"
  docker exec wraplink-nginx-1 nginx -s reload || true
  exit 1
fi
rm -f "$backup"
echo "API HTTPS vhosts enabled. Confirm access from the edge agent."
