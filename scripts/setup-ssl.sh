#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ -f .env ]] || { echo "Missing .env. Run bash scripts/init-env.sh first." >&2; exit 1; }
read -r -p "Primary public domain (e.g. wraplink.ir): " DOMAIN
[[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$DOMAIN" == *.* && "$DOMAIN" != *..* ]] || { echo "Invalid domain" >&2; exit 2; }
read -r -p "Additional domains, separated by spaces (optional): " EXTRA
DOMAINS=("$DOMAIN")
for d in $EXTRA; do
  [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$d" == *.* && "$d" != *..* ]] || { echo "Invalid domain: $d" >&2; exit 2; }
  DOMAINS+=("$d")
done
read -r -p "Let's Encrypt contact email: " EMAIL
[[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { echo "Invalid email" >&2; exit 2; }
printf 'Domains: %s\nEmail: %s\n' "${DOMAINS[*]}" "$EMAIL"
read -r -p "DNS A/AAAA records point here and port 80 is reachable? [y/N]: " YES
[[ "$YES" =~ ^[yY]$ ]] || exit 1
mkdir -p nginx/generated letsencrypt www/certbot

args=()
for d in "${DOMAINS[@]}"; do args+=(-d "$d"); done
echo "Issuing certificates using Let's Encrypt HTTP-01 standalone challenge."
echo "Port 80 must be free during initial issuance."
docker run --rm -p 80:80 -v "$PWD/letsencrypt:/etc/letsencrypt" -v "$PWD/www/certbot:/var/www/certbot" certbot/certbot:v3.3.0 certonly --standalone --preferred-challenges http --agree-tos --non-interactive --email "$EMAIL" --cert-name "$DOMAIN" "${args[@]}"
# Publish TLS configuration only after issuance succeeds. A failed challenge
# must not leave a 443 vhost referencing certificates that do not exist.
docker run --rm \
  -v "$PWD/letsencrypt:/etc/letsencrypt:ro" \
  --entrypoint /bin/sh certbot/certbot:v3.3.0 \
  -c 'test -s "/etc/letsencrypt/live/$1/fullchain.pem" && test -s "/etc/letsencrypt/live/$1/privkey.pem"' \
  sh "$DOMAIN" || {
  echo "Certificate files are missing or unreadable inside the certificate volume" >&2
  exit 1
}
{
  cat <<'CONF'
server {
  listen 80;
  server_name _;
  location /.well-known/acme-challenge/ { root /var/www/certbot; try_files $uri =404; }
  location / { return 308 https://$host$request_uri; }
}
server {
  listen 443 ssl;
  server_name
CONF
  printf '    %s' "${DOMAINS[@]}"
  printf ';\n'
  printf '  ssl_certificate /etc/letsencrypt/live/%s/fullchain.pem;\n' "$DOMAIN"
  printf '  ssl_certificate_key /etc/letsencrypt/live/%s/privkey.pem;\n' "$DOMAIN"
  cat <<'CONF'
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_session_tickets off;
  add_header X-Content-Type-Options nosniff always;
  client_max_body_size 10m;
  location / {
    proxy_pass http://web:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
CONF
} > nginx/generated/default.conf
echo "Certificate ready. Start production with: bash scripts/deploy.sh prod"
