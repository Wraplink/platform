#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
mode="${1:-dev}"
case "$mode" in
  dev) override=compose.dev.yml ;;
  prod) override=compose.prod.yml ;;
  edge) override=compose.edge.yml ;;
  *) echo "Usage: bash scripts/deploy.sh [dev|prod|edge]" >&2; exit 2 ;;
esac
if [[ ! -f .env ]]; then echo "First run: bash scripts/init-env.sh" >&2; exit 1; fi
if [[ "$mode" == prod ]]; then
  bash scripts/detect-public-ip.sh
fi
if [[ "$mode" == prod && ! -s nginx/generated/default.conf ]]; then
  bash scripts/setup-ssl.sh
fi
if [[ "$mode" == edge ]]; then
  docker compose --env-file .env -f "$override" up -d --build
else
  docker compose --env-file .env -f compose.yml -f "$override" up -d --build
fi
