#!/usr/bin/env bash
# Source this file to configure outbound SOCKS5 for Git, curl, and CLI tools.
set -a
source "$(dirname "${BASH_SOURCE[0]}")/../.env"
set +a
if [[ "${PROXY_ENABLED:-false}" == true ]]; then
  : "${SOCKS5_PROXY_PORT:?Set SOCKS5_PROXY_PORT in .env}"
  export ALL_PROXY="socks5h://${SOCKS5_PROXY_HOST:-192.168.108.204}:${SOCKS5_PROXY_PORT}"
  export all_proxy="$ALL_PROXY"
  export NO_PROXY="localhost,127.0.0.1,::1,postgres,backend,web,dns-control,nginx,${NO_PROXY:-}"
  export no_proxy="$NO_PROXY"
fi
