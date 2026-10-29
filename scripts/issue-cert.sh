#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
domain="${1:-wraplink.ir}"
email="${2:-}"
[[ -n "$email" ]] || { echo "Usage: bash scripts/issue-cert.sh DOMAIN EMAIL" >&2; exit 2; }
[[ "$domain" == "wraplink.ir" ]] || { echo "This Nginx template expects wraplink.ir; customize it first." >&2; exit 2; }
mkdir -p letsencrypt www/certbot
# First issuance uses standalone HTTP challenge on port 80. Stop any service bound to 80.
docker run --rm -p 80:80 -v "$PWD/letsencrypt:/etc/letsencrypt" -v "$PWD/www/certbot:/var/www/certbot" certbot/certbot:latest certonly --standalone --preferred-challenges http --agree-tos --non-interactive -m "$email" -d "$domain"
echo "Certificate issued. Configure renewal and reload nginx after renewal."
