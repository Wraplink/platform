#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
umask 077
if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "Usage: bash scripts/restore.sh /var/backups/wraplink/BACKUP_ID" >&2
  exit 2
fi
backup="$(realpath "$1")"
(cd "$backup" && sha256sum -c SHA256SUMS)
set -a
source ./.env
set +a
COMPOSE=(docker compose -f compose.yml -f compose.prod.yml)
echo "WARNING: Restore overwrites production PostgreSQL and selected persistent volumes."
echo "Stop application writers before restoring. PostgreSQL must remain running."
read -r -p "Type RESTORE to continue: " answer
[[ "$answer" == RESTORE ]] || exit 1
"${COMPOSE[@]}" stop backend dns-control web migrate
"${COMPOSE[@]}" up -d postgres
# Terminate other sessions, then replace database objects from the custom-format dump.
"${COMPOSE[@]}" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();"
"${COMPOSE[@]}" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
  pg_restore -e --clean --if-exists --no-owner --no-acl \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$backup/postgres.dump"
for volume in mailqueue mailkeys dnsqueryspool; do
  [[ -f "$backup/$volume.tar.gz" ]] || continue
  docker run --rm --network none \
    -v "wraplink_${volume}:/target" -v "$backup:/backup:ro" alpine:3.21 \
    sh -ec 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -xzf "/backup/$1.tar.gz" -C /target' sh "$volume"
done
echo "Database and selected volumes restored. Configuration and TLS archives were NOT automatically applied."
echo "Review archived configuration, then restart services with your normal deployment procedure."
