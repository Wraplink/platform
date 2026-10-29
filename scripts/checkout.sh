#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
mkdir -p services
for repo in backend dns-control edge-agent web; do
  if [[ -d "services/$repo/.git" ]]; then
    git -C "services/$repo" pull --ff-only
  elif [[ -e "services/$repo" ]]; then
    echo "Unexpected existing path services/$repo" >&2; exit 1
  else
    git clone "https://github.com/Wraplink/$repo.git" "services/$repo"
  fi
done
