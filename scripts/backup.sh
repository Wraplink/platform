#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
umask 077
set -a
source ./.env
set +a
BACKUP_DIR="${WRAPLINK_BACKUP_DIR:-/var/backups/wraplink}"
RETENTION_DAYS="${WRAPLINK_BACKUP_RETENTION_DAYS:-7}"
COMPOSE=(docker compose -f compose.yml -f compose.prod.yml)
mkdir -p "$BACKUP_DIR"
exec 9>"$BACKUP_DIR/.backup.lock"
flock -n 9 || { echo "Backup already running" >&2; exit 1; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp -d "$BACKUP_DIR/.incomplete-$stamp-XXXX")"
trap 'rm -rf "$tmp"' EXIT
echo "Creating backup $stamp"
"${COMPOSE[@]}" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$tmp/postgres.dump"
test -s "$tmp/postgres.dump"
# Copy named-volume contents read-only, without assuming the Compose project name.
for volume in mailqueue mailkeys dnsqueryspool; do
  docker run --rm --network none --read-only \
    -v "wraplink_${volume}:/source:ro" \
    -v "$tmp:/backup" alpine:3.21 \
    tar -czf "/backup/${volume}.tar.gz" -C /source .
done
tar -czf "$tmp/platform-config.tar.gz" \
  --exclude='.env' --exclude='services' --exclude='.git' \
  config nginx/generated
if [[ -d letsencrypt ]]; then
  tar -czf "$tmp/letsencrypt.tar.gz" letsencrypt
fi
if [[ -d www/certbot ]]; then
  tar -czf "$tmp/certbot.tar.gz" www/certbot
fi
(cd "$tmp" && sha256sum postgres.dump *.tar.gz > SHA256SUMS && sha256sum -c SHA256SUMS)
printf '%s\n' "$stamp" > "$tmp/BACKUP_ID"
mv "$tmp" "$BACKUP_DIR/$stamp"
trap - EXIT
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d \
  -name '20????????T??????Z' -mtime +"$RETENTION_DAYS" -exec rm -rf -- {} +
echo "Backup complete: $BACKUP_DIR/$stamp"
