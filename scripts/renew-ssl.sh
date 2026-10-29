#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
docker run --rm -p 80:80 -v "$PWD/letsencrypt:/etc/letsencrypt" -v "$PWD/www/certbot:/var/www/certbot" certbot/certbot:v3.3.0 renew --standalone --non-interactive
docker compose -f compose.yml -f compose.prod.yml exec -T nginx nginx -s reload
