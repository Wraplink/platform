# SOCKS5 outbound proxy

The deployment host has an optional SOCKS5 server at `192.168.108.204`. Its **port is not yet known**. Set `SOCKS5_PROXY_PORT` in `.env` before enabling.

```dotenv
PROXY_ENABLED=true
SOCKS5_PROXY_HOST=192.168.108.204
SOCKS5_PROXY_PORT=YOUR_PORT
```

For shell tools: `source scripts/proxy-env.sh` then run Git/curl commands. `socks5h` resolves names through the proxy. Note: Go and npm clients may not honor `ALL_PROXY`; use a compatible local HTTP CONNECT bridge or configured HTTP(S) proxy for Docker daemon and BuildKit. Do **not** assume Docker daemon supports SOCKS5 directly. Docker image pulls happen in the daemon, not in your shell.

The proxy is for outbound downloads only. Let's Encrypt HTTP-01 still needs inbound TCP 80 and public DNS pointing to `80.210.62.115`. Port 443 should be reachable for HTTPS. Certbot inside Docker may need explicit egress routing if direct internet access is restricted. Never expose a proxy endpoint publicly.

Check connectivity before certificate issuance:

```bash
source scripts/proxy-env.sh
curl -I https://acme-v02.api.letsencrypt.org/directory
dig +short A wraplink.ir
```

`PROXY_ENABLED=false` leaves normal outbound networking unchanged.
