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

### Restricted-network outbound proxy (Debian 13)

For a persistent SSH SOCKS5 tunnel and separate configuration of **APT**, **Git**, **Docker image builds**, **Docker daemon pulls**, and runtime containers, see the [outbound proxy runbook](docs/proxy.md). The runbook includes the unprivileged `wraplink` systemd service, SSH host-key verification, restart diagnostics, proxy security, and rollback steps. Docker daemon pulls require a compatible HTTP CONNECT proxy/bridge; do not assume the mail image's SOCKS5 build arguments configure the daemon.

### Edge host

Do not start Edge Agent unless its public IPs, routes, nftables privileges and network boundaries are configured. A different host requires its own checkout of this repository, environment file, and `bash scripts/deploy.sh edge`. Edit `config/edge-agent.yml` for actual addresses and routing capacities; `WRAPLINK_BACKEND_URL` and `DNS_CONTROL_API_URL` must be externally reachable private or TLS endpoints.

### Configuration and secrets

Only `.env.example` is committed. Run `bash scripts/init-env.sh` once to generate random local credentials; it refuses to overwrite existing `.env`. Do not commit `.env`, change credentials on shared installations, and enforce access controls and backups. `PAYMENTS_DEV_SETTLEMENT_KEY` is intentionally empty by default. Backend requires `SECURE_COOKIES=true` for production; configure TLS ingress accordingly.

Database migrations run through a one-shot `migrate/migrate` container before backend startup. Migration errors block startup. Avoid concurrent deploy migrations. Persistent PostgreSQL data uses the `pgdata` named volume.

Web uses same-origin browser requests and `BACKEND_INTERNAL_URL=http://backend:7080` for server-side proxying. It is **not** a browser-accessible address.

### Bootstrap the initial administrator

The backend already implements administrator bootstrap in `internal/bootstrap/admin.go`, invoked from `cmd/api/main.go` after database initialization. Compose's backend service loads `.env` using `env_file: .env`. Configure **both** values in your local `.env` (never commit it):

```dotenv
WRAPLINK_BOOTSTRAP_ADMIN_EMAIL=admin@example.com
WRAPLINK_BOOTSTRAP_ADMIN_PASSWORD=REPLACE_WITH_A_UNIQUE_16_PLUS_CHARACTER_SECRET
```

The email must be valid; the password must contain **16–1024 characters**. The example is a placeholder, not a usable password. `scripts/init-env.sh` leaves both fields empty and does **not** create an administrator by default. Set them explicitly, then recreate the backend so it receives the updated environment:

```bash
docker compose -f compose.yml -f compose.prod.yml up -d --no-deps --force-recreate backend
docker compose -f compose.yml -f compose.prod.yml logs --tail=100 backend | grep -E 'initial administrator created|bootstrap administrator reconciliation completed|failed to bootstrap administrator|failed to load configuration'
```

On first creation, look for `initial administrator created`. For an already-existing admin account, look for `bootstrap administrator reconciliation completed`. An empty grep result does **not** prove success; inspect full backend logs and container status. Verify the account in PostgreSQL **without exposing credentials**:

```bash
docker compose -f compose.yml -f compose.prod.yml exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT u.email, u.account_status, u.email_verified, (a.user_id IS NOT NULL) AS is_access_admin FROM users u LEFT JOIN access_admins a ON a.user_id=u.id WHERE u.email=\x27admin@example.com\x27;"'
```

Replace `admin@example.com` in the SQL with your configured email. This checks the database role, not whether browser login succeeds; test login separately. The bootstrap creates grants in `access_admins`, `payment_review_admins`, and `discount_admins` for a new user. It **will not promote** an existing ordinary user. For an existing bootstrap administrator, the configured password is checked at each backend startup; if changed, the password is reset and active sessions are revoked. **After verifying first-time provisioning, clear both variables from `.env` and recreate the backend again** to prevent an environment-stored bootstrap password from continually controlling that account. Keep a secure recovery procedure for administrator access.

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

### Registration and transactional email

Production includes a **send-only Postfix + OpenDKIM** mail relay in the `mail` Compose service. The backend submits registration and password-reset email to `mail:25` over a dedicated private Docker network; no public SMTP ports are published. Delivery to recipient MX servers requires **outbound TCP 25**, correct forward/PTR DNS, SPF, DKIM, DMARC and monitoring.

For restricted networks, configure optional build-time proxy arguments in `.env` (the verified SOCKS5 URL can be used):

```dotenv
BUILD_HTTP_PROXY=socks5h://192.168.10.114:10810
BUILD_HTTPS_PROXY=socks5h://192.168.10.114:10810
```

Then build the mail image with `docker compose -f compose.yml -f compose.prod.yml build mail`. These arguments are supplied only to the mail image build and are independent of `MAIL_PROXY_ENABLED`, `MAIL_PROXY_HOST`, and `MAIL_PROXY_PORT`, which control outbound SMTP at runtime. Leave the build values blank when direct package downloads work. Build-time proxy settings do not configure Docker daemon image pulls.

See **[Self-hosted mail deployment, firewall ports and troubleshooting](docs/self-hosted-mail.md)** for the full runbook, Cloudflare records, DKIM verification, security requirements and diagnostic commands. Do not use the former Mailerever SMTP example for this deployment.

### Cloudflare Turnstile CAPTCHA

Create a **Managed** Turnstile widget in the [Cloudflare dashboard](https://dash.cloudflare.com/) for `wraplink.ir` (and `www.wraplink.ir` if used). Add the two values to your private platform `.env`:

```dotenv
NEXT_PUBLIC_TURNSTILE_SITE_KEY=your_public_site_key
TURNSTILE_SECRET_KEY=your_private_secret_key
```

The site key is public and is passed through `compose.yml` as a **web Docker build argument**; changing it requires rebuilding the web image. The secret is private and reaches the Go backend through `env_file: .env`; changing it requires recreating the backend container. Never add actual secret values to `.env.example`, frontend variables, or Git.

**Enable both together:** setting only the backend secret rejects public form submissions when the frontend has no widget. The backend currently bypasses CAPTCHA validation if its secret is unset, so a missing secret is **not** secure production enforcement. Turnstile protects registration, verification resend, password-reset requests, and contact submissions.

```bash
# After editing .env:
docker compose -f compose.yml -f compose.prod.yml build web
docker compose -f compose.yml -f compose.prod.yml up -d --no-deps --force-recreate web backend
```

The backend must reach `https://challenges.cloudflare.com/turnstile/v0/siteverify` over outbound HTTPS (TCP/443); restricted networks must configure working egress before enabling enforcement. Test all four protected forms after deployment. For local development, Cloudflare provides [test keys](https://developers.cloudflare.com/turnstile/troubleshooting/testing/).

## Authoritative agent registry rollout

For the new Backend / DNS Control / Edge Agent release, apply Backend migration `000046_agent_health`, deploy compatible Edge Agents, and verify fresh `network_agent_health` heartbeats **before** enabling DNS Control snapshots. Set `WRAPLINK_BACKEND_AGENT_SNAPSHOT_ENABLED=true` in `.env` and recreate DNS Control only after registration is healthy. The flag defaults to `false`. **Backend Full Route eligibility already requires Backend heartbeats regardless of this flag**, so coordinate deployment on any live Full Route fleet. Follow [the rollout guide](https://github.com/Wraplink/backend/blob/master/docs/agent-registry-rollout.md).

## DNS query reporting (optional)

DNS-Control can asynchronously report DNS query metadata to Backend for the admin Network / DNS Queries view. Deploy compatible Backend and DNS-Control versions first, then set `WRAPLINK_DNS_QUERY_REPORT_ENABLED=true` in `.env` and recreate DNS-Control. The Compose stack mounts a persistent `dnsqueryspool` volume and defaults to a 64 MiB disk budget. Events not yet persisted can still be lost during abrupt shutdown; monitor reporting counters and disk usage.

See [environment variables](docs/environment-variables.md#dns-query-reporting-and-persistent-spool) and the [DNS-Control reporting runbook](https://github.com/Wraplink/dns-control/blob/main/docs/dns-query-reporting-operations.md).
