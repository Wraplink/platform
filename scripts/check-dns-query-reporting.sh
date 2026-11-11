#!/usr/bin/env bash
# Read-only preflight for DNS query audit reporting.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
compose=(docker compose --env-file .env -f compose.yml -f compose.prod.yml)
fail=0
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name" >&2
    fail=1
  fi
}
if [[ ! -f .env ]]; then
  echo 'FAIL .env missing' >&2
  exit 1
fi
check 'Compose configuration validates' "${compose[@]}" config --quiet
check 'Backend container running' "${compose[@]}" ps --status running --services backend
check 'DNS-Control container running' "${compose[@]}" ps --status running --services dns-control
check 'Web container running' "${compose[@]}" ps --status running --services web
# A running service check must also verify that the service appears in the output.
for service in backend dns-control web; do
  if ! "${compose[@]}" ps --status running --services "$service" 2>/dev/null | grep -qx "$service"; then
    printf 'FAIL %s is not running\n' "$service" >&2
    fail=1
  fi
done
cid=$("${compose[@]}" ps -q dns-control 2>/dev/null || true)
if [[ -z "$cid" ]]; then
  echo 'FAIL DNS-Control container not found' >&2
  fail=1
else
  # Inspect only mount destination and type; never print environment or credentials.
  if docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/wraplink/dns-query-spool"}}{{.Type}}{{end}}{{end}}' "$cid" | grep -qx volume; then
    echo 'PASS DNS query spool is a named volume'
  else
    echo 'FAIL DNS query spool named volume not mounted' >&2
    fail=1
  fi
fi
if grep -Eq '^WRAPLINK_DNS_QUERY_REPORT_ENABLED=true([[:space:]]*)$' .env; then
  echo 'INFO DNS query reporting is enabled in .env'
else
  echo 'INFO DNS query reporting is disabled in .env (safe default)'
fi
echo 'NOTE Backend migration, controller registration, and live query ingestion require separate verification.'
exit "$fail"
