#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
if [[ -e .env ]]; then echo ".env already exists; refusing to overwrite" >&2; exit 1; fi
umask 077
cp .env.example .env
python3 - <<'PY'
from pathlib import Path
import secrets
p=Path(".env")
s=p.read_text()
for key in ("POSTGRES_PASSWORD","JWT_SECRET","NETWORK_USAGE_INGEST_KEY","NETWORK_CONTROL_SYNC_KEY","DNS_CONTROL_API_TOKEN","DNS_CONTROL_AGENT_TOKEN"):
    s=s.replace(key+"=CHANGE_ME",key+"="+secrets.token_hex(48))
p.write_text(s)
PY
chmod 600 .env
echo "Created .env with random secrets. Review host/IP and production settings."
