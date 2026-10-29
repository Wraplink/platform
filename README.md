# Wraplink Platform

Central Docker Compose orchestration for [Web](https://github.com/Wraplink/web), [Backend](https://github.com/Wraplink/backend), [DNS Control](https://github.com/Wraplink/dns-control), and the optional privileged [Edge Agent](https://github.com/Wraplink/edge-agent). PostgreSQL 17 is used for the backend.

## Quick start (development)

Requires Docker Engine with Docker Compose v2, Git, Python 3 and free ports 53/3000/5432/7080/8080. On Debian 13, port 53 may already be occupied by a local resolver; check with `sudo ss -lntup | grep ':53 '`.

```bash
git clone https://github.com/Wraplink/platform.git
cd platform
bash scripts/checkout.sh
bash scripts/init-env.sh
# Check .env values, especially NODE_PUBLIC_IP
bash scripts/deploy.sh dev
docker compose -f compose.yml -f compose.dev.yml ps
```

Web: http://localhost:3000; backend http://localhost:7080. Public DNS forwards UDP/TCP 53 to DNS Control (development only as configured).

Services are cloned into `services/` (ignored by Git). For a single-host production deployment run:

```bash
# Set APP_ENV=production, SECURE_COOKIES=true,
# FRONTEND_URL=https://wraplink.ir in .env
bash scripts/deploy.sh prod
```

Production publishes Web, Backend and the DNS API on loopback, but DNS port 53 publicly. Nginx is included in production Compose for TLS offload and forwards requests to Web over the private Docker network. Before the first production start, obtain a certificate using `bash scripts/issue-cert.sh wraplink.ir ops@example.com` (replace with your actual email), and ensure the domain points to the server and TCP port 80 is reachable. Nginx will fail to start without certificate files. The current configuration targets `wraplink.ir`; adjust the Nginx configuration and certificate issuance for additional hostnames. Automate certificate renewal and Nginx reload before production use. Do not publicly expose the backend control APIs or DNS API. Review ACLs, firewall, TLS, backups, and secrets before internet exposure. Production is a **starting configuration, not a hardened, fully tested production deployment**.

### Edge host

Do not start Edge Agent unless its public IPs, routes, nftables privileges and network boundaries are configured. A different host requires its own checkout of this repository, environment file, and `bash scripts/deploy.sh edge`. Edit `config/edge-agent.yml` for actual addresses and routing capacities; `WRAPLINK_BACKEND_URL` and `DNS_CONTROL_API_URL` must be externally reachable private or TLS endpoints.

### Configuration and secrets

Only `.env.example` is committed. Run `bash scripts/init-env.sh` once to generate random local credentials; it refuses to overwrite existing `.env`. Do not commit `.env`, change credentials on shared installations, and enforce access controls and backups. `PAYMENTS_DEV_SETTLEMENT_KEY` is intentionally empty by default. Backend requires `SECURE_COOKIES=true` for production; configure TLS ingress accordingly.

Database migrations run through a one-shot `migrate/migrate` container before backend startup. Migration errors block startup. Avoid concurrent deploy migrations. Persistent PostgreSQL data uses the `pgdata` named volume.

Web uses same-origin browser requests and `BACKEND_INTERNAL_URL=http://backend:7080` for server-side proxying. It is **not** a browser-accessible address.

### Limitations requiring site-specific configuration

- The DNS node advertises `NODE_PUBLIC_IP`; the default `127.0.0.1` is only appropriate for local testing.
- DNS Control needs a securely shared agent token; ensure Edge Agent uses the matching token in `DNS_CONTROL_API_TOKEN` on the edge host.
- Real Edge Agent full-route forwarding requires assigning IP addresses to the host and configuring capacities/routes correctly.
- Production app readiness, live external DNS behavior, TLS proxying, NAT/iptables/nftables interactions and end-to-end smoke tests must be verified on the actual servers.

### HTTPS / TLS offload

Nginx publishes TCP 80/443, redirects normal HTTP traffic to HTTPS, and proxies requests to the Web container. The Go backend remains internal behind Next.js. Certificate files are mounted from `./letsencrypt`; obtain the initial certificate *before* `bash scripts/deploy.sh prod`:

```bash
bash scripts/issue-cert.sh wraplink.ir admin@example.com
bash scripts/deploy.sh prod
```

The issuance script uses a standalone ACME HTTP-01 challenge and needs exclusive access to port 80. Stop other port-80 listeners first. Renew certificates with Certbot and reload Nginx (`docker compose -f compose.yml -f compose.prod.yml exec nginx nginx -s reload`); renewal automation is not included yet. Do not publish DNS Control's administrative API publicly. Set `FRONTEND_URL=https://wraplink.ir`, `APP_ENV=production`, and `SECURE_COOKIES=true` in `.env`.

### Interactive domain configuration

On the first production start, `bash scripts/deploy.sh prod` prompts for a primary domain, optional additional domains and a Let's Encrypt contact email. It issues certificates using standalone HTTP-01 (port 80 must be free) and generates the Nginx configuration. For subsequent changes use `bash scripts/setup-ssl.sh` (stop Nginx first if it holds port 80), then restart Nginx. Renew with `bash scripts/renew-ssl.sh` while Nginx is running. Schedule renewal separately using cron/systemd; no timer is installed automatically. 
