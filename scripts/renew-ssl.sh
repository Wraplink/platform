#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
# Webroot validation uses the running Nginx port 80 listener; no port conflict.
docker run --rm -v "$PWD/letsencrypt:/etc/letsencrypt" -v "$PWD/www/certbot:/var/www/certbot" certbot/certbot:v3.3.0 renew --webroot --webroot-path /var/www/certbot --non-interactive
docker compose -f compose.yml -f compose.prod.yml exec -T nginx nginx -s reload
