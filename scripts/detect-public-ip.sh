#!/usr/bin/env bash
# Resolve the externally visible IPv4 address for production node advertising.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f .env ]]; then echo "Missing .env" >&2; exit 1; fi
python3 - <<'PY'
from pathlib import Path
import ipaddress
import os
import subprocess
import sys
import tempfile

env_path = Path(".env")
lines = env_path.read_text().splitlines(keepends=True)
values = {}
for line in lines:
    if line.strip() and not line.lstrip().startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip().strip('"').strip("'")

mode = values.get("NODE_PUBLIC_IP_MODE", "auto").lower()
if mode not in ("auto", "manual"):
    sys.exit("NODE_PUBLIC_IP_MODE must be auto or manual")

def valid_public(value):
    try:
        ip = ipaddress.IPv4Address(value)
        return ip.is_global
    except ValueError:
        return False

current = values.get("NODE_PUBLIC_IP", "")
if mode == "manual":
    if not valid_public(current):
        sys.exit("Manual NODE_PUBLIC_IP must be a globally routable IPv4 address")
    print("Using manually configured NODE_PUBLIC_IP=" + current)
    sys.exit(0)

if current and current not in ("127.0.0.1", "0.0.0.0", "auto") and valid_public(current):
    print("Keeping explicitly configured NODE_PUBLIC_IP=" + current + " (set NODE_PUBLIC_IP=auto to refresh)")
    sys.exit(0)

endpoints = ("https://api.ipify.org", "https://ipv4.icanhazip.com", "https://checkip.amazonaws.com")
detected = None
for endpoint in endpoints:
    try:
        result = subprocess.run(
            ["curl", "-4", "-fsS", "--noproxy", "*", "--connect-timeout", "4", "--max-time", "8", endpoint],
            capture_output=True, text=True, timeout=10, check=True)
        candidate = result.stdout.strip()
        if valid_public(candidate):
            detected = candidate
            break
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
        pass

if not detected:
    sys.exit("Public IPv4 detection failed. Set NODE_PUBLIC_IP_MODE=manual and NODE_PUBLIC_IP=<inbound-public-IP> in .env")

print("Detected outbound public IPv4: " + detected)
print("WARNING: This is the outbound egress IP; behind NAT it may differ from the inbound public IP.")
updated = []
found = False
for line in lines:
    if line.startswith("NODE_PUBLIC_IP="):
        updated.append("NODE_PUBLIC_IP=" + detected + "\n")
        found = True
    else:
        updated.append(line)
if not found:
    updated.append("\nNODE_PUBLIC_IP=" + detected + "\n")
fd, tmp = tempfile.mkstemp(prefix=".env.", dir=".")
try:
    with os.fdopen(fd, "w") as f:
        f.writelines(updated)
    os.chmod(tmp, 0o600)
    os.replace(tmp, env_path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
