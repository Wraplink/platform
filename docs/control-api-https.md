# Control API HTTPS setup (central production host)

The website certificate covers only `wraplink.ir` and `www.wraplink.ir`. The edge agent needs HTTPS endpoints at `api.wraplink.ir` and `dns-api.wraplink.ir`.

1. Point both API hostnames to the central public IPv4 (DNS-only if using Cloudflare). Ensure public TCP/80 reaches the production Nginx container.
2. Deploy the updated platform files: `bash scripts/deploy.sh prod`. This mounts `nginx/generated/api-vhosts` read-only into Nginx.
3. On the **edge host**, check its real outbound public IPv4 (NAT may differ from its inbound address), then set `EDGE_AGENT_ALLOWED_IP` to that observed source IP on the central host.
4. Run `LE_EMAIL=you@example.com EDGE_AGENT_ALLOWED_IP=185.194.190.84 bash scripts/setup-control-api.sh` on the central host. Replace both values with the actual email and observed source IPv4.
5. The script probes public HTTP-01 URLs **before** asking Let's Encrypt for a certificate. If it fails, investigate DNS, external proxies, Nginx, or the challenge volume rather than repeatedly invoking Certbot.
6. Once the probe passes, Certbot issues a **separate** certificate for the two API hostnames, writes dedicated Nginx vhosts, checks syntax and reloads Nginx without stopping the website.
7. Configure the edge agent's Backend and DNS Control URLs to these HTTPS hostnames. Keep their existing API tokens/keys; IP allowlisting is additional protection, not a replacement for authentication.

The script currently proxies all paths on each API hostname, subject to IP allowlisting and upstream authentication. Before opening access more broadly, audit the exact agent-required endpoints and restrict location paths. Do not place a Cloudflare-proxied hostname in front of this source-IP allowlist without a trusted-real-IP design.

## Required setup variables

The `scripts/setup-control-api.sh` command requires two **shell environment variables** on the **central production host**. They are not automatically read from `.env` by the script, and they are not required by the running Nginx container.

| Variable | Meaning | Example |
| --- | --- | --- |
| `LE_EMAIL` | Contact email registered with Let's Encrypt for expiry and account notices; use a valid mailbox you control. | `ops@example.com` |
| `EDGE_AGENT_ALLOWED_IP` | The public **source IPv4** that Nginx observes when the remote Edge Agent connects. This IP is added to the HTTPS API allowlist. | `185.194.190.84` |

Determine the egress address **on the Edge Agent host**, not on the central server:

```bash
curl --noproxy '*' -4 -fsS https://api.ipify.org; echo
```

An assigned inbound IPv4 is not necessarily the outbound source IP if the host uses NAT or an outbound proxy. Verify that the source IP remains stable. If it changes, the API returns HTTP 403 until the allowlist is updated. Only IPv4 is accepted by the setup script.

Set the values for a single invocation (replace both examples):

```bash
cd /home/wraplink/platform
LE_EMAIL="ops@example.com" \
EDGE_AGENT_ALLOWED_IP="185.194.190.84" \
bash scripts/setup-control-api.sh
```

Alternatively, export them in the current shell:

```bash
export LE_EMAIL="ops@example.com"
export EDGE_AGENT_ALLOWED_IP="185.194.190.84"
bash scripts/setup-control-api.sh
```

Neither variable is an API credential. Keep `DNS_CONTROL_API_TOKEN` and `NETWORK_CONTROL_SYNC_KEY` secret and configured separately. This setup issues certificates and writes the IP allowlist; it does **not** install automated renewal or validate application API authentication.

## Troubleshooting

- **404 on HTTP-01**: Verify `docker exec wraplink-nginx-1 cat /var/www/certbot/.well-known/acme-challenge/<test-file>` and then request `http://api.wraplink.ir/.well-known/acme-challenge/<test-file>`. Both must show the same content.
- **403 from API**: The agent's observed egress IPv4 may differ from its assigned public IPv4.
- **401 from API**: The application rejected the supplied credentials.
- **Nginx config not visible**: Recreate the Nginx container with the updated Compose mounts; `nginx -s reload` alone cannot add a missing Docker bind mount.
- **Certificate renewals**: Certbot webroot renewal must be scheduled separately and Nginx reloaded after successful renewal; this setup script performs initial issuance/configuration only.
