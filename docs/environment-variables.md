# WrapLink environment variables and cross-service relationships

This is the operator reference for the **central platform**, **standalone Backend**, **DNS Control**, and **Edge Agent**. Based on the tracked `compose.yml`, `compose.prod.yml`, `.env.example`, and service YAML templates. A variable in `.env` is **not** automatically available inside a container: it must be passed by `env_file` or `environment`. Compose substitutes its own YAML; Go applications expand `${NAME}` placeholders in their mounted configuration files.

## 1. Critical cross-project mappings

| Central Backend / platform | DNS Control | Edge Agent | Relationship and purpose |
| --- | --- | --- | --- |
| `NETWORK_CONTROL_SYNC_KEY` | `NETWORK_CONTROL_SYNC_KEY` | `NETWORK_CONTROL_KEY` | **Same secret**. Authenticates DNS Control / Edge Agent to Backend control-plane endpoints. The edge key is only required by current validation when Full Route is enabled, but configure it for integration. |
| `DNS_CONTROL_API_TOKEN` | **Not** the same as `DNS_CONTROL_AGENT_TOKEN` | `DNS_CONTROL_API_TOKEN` | Backend and agent clients authenticate to DNS Control's HTTP API using the same API token where the API expects it. Verify server-side token wiring before deployment; do not confuse this with the agent registration token. |
| `DNS_CONTROL_AGENT_TOKEN` | `DNS_CONTROL_AGENT_TOKEN` (agent.token) | Not currently referenced in edge `config.yml` | DNS Control agent-registration credential. **Do not assume it equals** `DNS_CONTROL_API_TOKEN`. Confirm the actual endpoint authentication and provision accordingly. |
| `DNS_CONTROL_API_URL` | DNS Control `API_LISTEN` plus reverse proxy | `DNS_CONTROL_API_URL` | URL points **to** DNS Control, not to Backend. Central Compose uses `http://dns-control:8080`; remote Edge uses `https://dns-api.wraplink.ir`. |
| Backend's own HTTP address | `WRAPLINK_BACKEND_URL` | `WRAPLINK_BACKEND_URL` | Both services point to Backend. Central Compose uses `http://backend:7080`; standalone hosts use a reachable HTTPS URL such as `https://api.wraplink.ir`. |
| `NETWORK_USAGE_INGEST_KEY` | Not referenced in tracked YAML | Not referenced in tracked YAML | Backend traffic-report ingestion secret. Do not substitute the control key; verify traffic-report sender integration separately. |
| `WRAPLINK_ALERT_INGEST_KEY` | `WRAPLINK_ALERT_INGEST_KEY` (Compose runtime) | Optional sender integration | Shared alert-ingest authentication. Distinct from control and usage keys. |
| `NODE_ID` / `NODE_REGION` / `NODE_PUBLIC_IP` | Same variable names | `EDGE_AGENT_ID` / `EDGE_AGENT_REGION` / `EDGE_PUBLIC_IP` | Independent identities and advertised addresses; **not shared values**. Each node ID must be unique and each advertised IP reachable. |
| `APP_ENV` | `WRAPLINK_ENVIRONMENT` via Compose | N/A | Central Compose maps `APP_ENV` into DNS Control environment for alert/runtime behavior. |
| `FRONTEND_URL` | N/A | N/A | Browser-facing origin; Backend uses it for frontend URL and its tracked CORS allowlist. |

**Security:** generate high-entropy secrets, store in restricted `.env` / `.env.local`, and never put values in commits, logs, PR descriptions, or chat. Use a secret manager when available. Rotating a shared key requires coordinated rollout to every consumer.

## 2. Central platform variables (`Wraplink/platform/.env`)

| Variable | Used by / where | Description | Requirement |
| --- | --- | --- | --- |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Compose Postgres, migration, Backend `DATABASE_URL` | Database name, role and password | Required |
| `JWT_SECRET` | Backend security.jwt-secret | JWT signing secret, minimum 64 chars per Backend validation | Required |
| `NETWORK_USAGE_INGEST_KEY` | Backend network.usage-ingest-key | Authenticates usage ingestion | Optional feature; >=32 chars if set |
| `NETWORK_CONTROL_SYNC_KEY` | Backend and DNS Control | Shared control synchronization secret | Required by central Compose |
| `DNS_CONTROL_API_TOKEN` | Backend, DNS Control API clients, remote Edge | DNS Control HTTP API client token | Required by central Compose |
| `DNS_CONTROL_AGENT_TOKEN` | DNS Control agent.token | Agent registration credential | Required for registration |
| `WRAPLINK_BACKEND_AGENT_SNAPSHOT_ENABLED` | DNS Control runtime (Compose passes through) | Use paginated Backend-authoritative agent snapshots instead of local agent inventory | **false by default**; enable only after Backend and Edge Agent heartbeat rollout |
| `PAYMENTS_DEV_SETTLEMENT_KEY` | Backend payments.dev-settlement-key | Development-only settlement | Optional; never enable in production |
| `DNS_LISTEN` | DNS Control DNS listener (central Compose overrides to `:53`) | UDP/TCP DNS bind | Default `:53` |
| `DNS_UPSTREAM` | DNS Control upstream | Comma-separated upstream `IP:53` entries | Default two public resolvers |
| `API_LISTEN` | DNS Control HTTP API (central Compose overrides to `:8080`) | API bind address | Default `:8080` |
| `PLATFORM_HOST` | Deployment scripts / hostname setup | Public platform hostname | Deployment-dependent |
| `WEB_PORT`, `BACKEND_PORT`, `DNS_API_PORT`, `DNS_PORT` | Production Compose published ports | Host-side bindings | Optional defaults 3000/7080/8080/53 |
| `NODE_PUBLIC_IP_MODE` | Deployment scripts | Automatic versus manual advertised public IP selection | Use manual behind NAT |
| `NODE_ID`, `NODE_REGION`, `NODE_PUBLIC_IP` | DNS Control node registration | Unique identity, region, advertised DNS address | Required for registered DNS node |
| `FRONTEND_URL` | Backend, Compose | Public browser-facing origin and CORS entry | Required for Backend |
| `APP_ENV` | Backend, DNS Control runtime | development/production | Required for Backend |
| `SECURE_COOKIES` | Backend security.secure-cookies | HTTPS session-cookie security | **true in production** |
| `COOKIE_DOMAIN` | Backend security.refresh-cookie-domain | Cookie domain; blank for host-only | Optional |
| `BACKEND_TRUSTED_PROXIES` | Deployment config/scripts; not directly mapped in tracked Backend YAML | Trusted reverse proxies | Check generated config before relying on it |
| `WRAPLINK_BOOTSTRAP_ADMIN_EMAIL`, `WRAPLINK_BOOTSTRAP_ADMIN_PASSWORD` | Backend runtime (read directly from env) | Admin bootstrap; password 16–1024 chars | Optional; both together |
| `EDGE_ENABLED`, `EDGE_ID`, `EDGE_REGION`, `EDGE_ADDRESSES` | Platform edge deployment scripts/config | Optional platform-managed edge identity | Only if platform edge enabled |
| `EDGE_ROUTE_PUBLIC_IPS`, `EDGE_ROUTE_CAPACITY`, `EDGE_SNI_CAPACITY` | Platform edge deployment scripts/config | Advertised route IPs and capacities | Edge-specific |
| `EDGE_SNI_ENABLED`, `EDGE_SNI_LISTEN` | Platform edge deployment scripts/config | SNI listener settings | Edge-specific |
| `PROXY_ENABLED`, `SOCKS5_PROXY_HOST`, `SOCKS5_PROXY_PORT` | Deployment scripts | Optional outbound SOCKS5 proxy | Optional; not Docker daemon proxy |
| `BUILD_HTTP_PROXY`, `BUILD_HTTPS_PROXY` | Compose build args | Image-build proxy | Optional |
| `MAIL_DOMAIN`, `MAIL_HOSTNAME`, `SMTP_FROM` | Mail container, Backend SMTP sender | Sending domain, host and From address | Mail-specific |
| `MAIL_PROXY_ENABLED`, `MAIL_PROXY_HOST`, `MAIL_PROXY_PORT`, `MAIL_PROXY_USERNAME`, `MAIL_PROXY_PASSWORD` | Mail container | SOCKS5 SMTP egress | Optional |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | Web image build | Public CAPTCHA site key | Optional; build-time |
| `TURNSTILE_SECRET_KEY` | Backend runtime | Private CAPTCHA verification key | Optional; server-only |
| `WRAPLINK_SLACK_WEBHOOK_URL` | Backend runtime | Slack notifications | Optional |
| `WRAPLINK_ALERT_INGEST_KEY`, `WRAPLINK_ALERT_API_URL` | Backend / DNS Control alerts; edge senders | Shared alert auth and target API | Optional |
| `WRAPLINK_DIAGNOSTICS_TOKEN` | Standalone Edge Agent only (when explicitly enabled in `config.yml`) | Private diagnostics HTTP API authentication token; not needed for agent registration/heartbeats | Optional; diagnostics disabled by default |

Compose also sets fixed `SMTP_HOST=mail`, `SMTP_PORT=25`, `SMTP_ALLOW_PLAINTEXT_INTERNAL=true`, `BACKEND_INTERNAL_URL=http://backend:7080`, and `BACKEND_PROXY_TRUST_NEXT_FORWARDED_FOR=false`. They are **container environment settings**, not independent `.env.example` entries.

## Coordinated agent-registry upgrade

Deploy compatible Backend (including migration `000046_agent_health`) and Edge Agents first, verify `network_agent_health` has fresh online records, then enable `WRAPLINK_BACKEND_AGENT_SNAPSHOT_ENABLED=true` in the DNS Control environment and recreate DNS Control. Backend Full Route eligibility requires both route IP inventory and Backend agent-health heartbeats; do not deploy it ahead of compatible Edge Agents on a live Full Route fleet without a maintenance window. The flag controls DNS Control snapshots only, **not** Backend route eligibility. See [Backend rollout guide](https://github.com/Wraplink/backend/blob/master/docs/agent-registry-rollout.md).

## 3. Standalone Backend (`Wraplink/backend/config.yml`)

| Variable | YAML field | Meaning |
| --- | --- | --- |
| `APP_ENV` | app.environment | Runtime environment |
| `FRONTEND_URL` | app.frontend-url; cors.allowed-origins | Frontend URL and one allowed CORS origin |
| `DATABASE_URL` | database.url | PostgreSQL connection string |
| `JWT_SECRET` | security.jwt-secret | Signing key |
| `SECURE_COOKIES` | security.secure-cookies | Boolean, production true |
| `COOKIE_DOMAIN` | security.refresh-cookie-domain | Optional domain |
| `PAYMENTS_DEV_SETTLEMENT_KEY` | payments.dev-settlement-key | Development-only secret |
| `NETWORK_USAGE_INGEST_KEY` | network.usage-ingest-key | Usage reporting authentication |
| `NETWORK_CONTROL_SYNC_KEY` | network.control-sync-key | Control-plane shared key |
| `DNS_CONTROL_API_URL` | network.dns-control-url | DNS Control API base URL |
| `DNS_CONTROL_API_TOKEN` | network.dns-control-token | DNS Control client credential |
| `WRAPLINK_BOOTSTRAP_ADMIN_EMAIL`, `WRAPLINK_BOOTSTRAP_ADMIN_PASSWORD` | Read directly by Go loader | Optional admin bootstrap pair |

`BACKEND_TRUSTED_PROXIES` is not interpolated by the tracked standalone `config.yml`; `server.trusted-proxies` currently defaults to an empty list. Avoid assuming it takes effect without a separate configuration/rendering step.

## 4. Standalone DNS Control (`Wraplink/dns-control/config.yaml`)

| Variable | YAML field | Meaning |
| --- | --- | --- |
| `DNS_LISTEN` | dns.listen | DNS bind address |
| `DNS_UPSTREAM` | dns.upstream | Comma-separated upstream resolver list |
| `API_LISTEN` | api.listen | Management API listener |
| `DNS_CONTROL_AGENT_TOKEN` | agent.token | Agent authentication secret |
| `WRAPLINK_BACKEND_URL` | backend.url | Backend reachable base URL |
| `NETWORK_CONTROL_SYNC_KEY` | backend.control_key | Must equal Backend key |
| `NODE_ID` | node.id | Unique node identity |
| `NODE_REGION` | node.region | Node region |
| `NODE_PUBLIC_IP` | node.public_dns[0] | Externally reachable DNS IP |
| `PARENT_DNS_CONTROL_TOKEN` | dns.parent_token (commented) | Optional parent DNS Control credential; only used if parent configuration is enabled |

The DNS Control Go loader currently uses `os.ExpandEnv`; **unset variables silently become empty**. Ensure all referenced values are present before starting.

## 5. Standalone Edge Agent (`Wraplink/edge-agent/config.yml`)

| Variable | YAML field | Meaning |
| --- | --- | --- |
| `EDGE_AGENT_ID` | agent.id | Unique agent ID |
| `EDGE_AGENT_REGION` | agent.region | Deployment region |
| `EDGE_PUBLIC_IP` | edge.addresses[0] | Advertised IP assigned to this host |
| `EDGE_SNI_CAPACITY` | agent.capacity.sni | SNI capacity |
| `EDGE_ROUTE_CAPACITY` | agent.capacity.route | Full Route capacity; 0 disables |
| `EDGE_SNI_ENABLED` | edge.sni.enabled | Enable SNI listener |
| `EDGE_SNI_LISTEN_ADDRESS` | edge.sni.listen_address | SNI bind address, e.g. 0.0.0.0:443 |
| `DNS_CONTROL_API_URL` | dns_control.url | DNS Control reachable API |
| `DNS_CONTROL_API_TOKEN` | dns_control.token | DNS Control API credential |
| `WRAPLINK_BACKEND_URL` | backend.url | Backend reachable API |
| `NETWORK_CONTROL_KEY` | backend.control_key | **Same value as Backend `NETWORK_CONTROL_SYNC_KEY`** |

For SNI-only nodes, use `EDGE_ROUTE_CAPACITY=0` and `backend.route_public_ips: []`. For Full Route, explicitly add dedicated route IPs in the YAML and provision them in Backend. Edge Agent validates missing referenced environment variables rather than silently substituting empty values.

| `WRAPLINK_DIAGNOSTICS_TOKEN` | diagnostics.token (only if configured as `${WRAPLINK_DIAGNOSTICS_TOKEN}`) | Optional secret for private diagnostics API; set `diagnostics.enabled: true` and keep listener on loopback | 

**Important:** The shipped Edge Agent `config.yml` has `diagnostics.enabled: false` and a literal empty `diagnostics.token`. Setting the environment variable alone does not enable the API. Generate a strong token (`openssl rand -hex 32`) only when enabling diagnostics; never expose port 9091 publicly.

**Naming caution:** central platform optional edge variables (`EDGE_ID`, `EDGE_REGION`, `EDGE_ADDRESSES`, `EDGE_SNI_LISTEN`) are **not** the same names as standalone Edge Agent's `EDGE_AGENT_ID`, `EDGE_AGENT_REGION`, `EDGE_PUBLIC_IP`, `EDGE_SNI_LISTEN_ADDRESS`.

## DNS query reporting and persistent spool

DNS query reporting is **opt-in** and must be enabled only after the compatible Backend ingestion endpoint (Backend PR #86 and migration) and DNS-Control reporting worker (DNS-Control PR #43, stacked on #41) have been deployed.

| Variable | Default in platform Compose | Purpose |
| --- | --- | --- |
| `WRAPLINK_DNS_QUERY_REPORT_ENABLED` | `false` | Enable asynchronous DNS query reporting to Backend; only active when Backend and DNS node registration are configured |
| `WRAPLINK_DNS_QUERY_SPOOL_DIR` | `/var/lib/wraplink/dns-query-spool` | Disk directory used for batch persistence; central Compose sets this automatically |
| `WRAPLINK_DNS_QUERY_SPOOL_MAX_BYTES` | `67108864` (64 MiB) | Maximum retained batch payload bytes; must be a positive integer |

The central Compose file mounts the **`dnsqueryspool` named volume** at `/var/lib/wraplink/dns-query-spool`. This volume survives container recreation, but **not** `docker compose down -v` or explicit volume removal. Do not mount the spool on ephemeral container storage. Confirm that the DNS-Control process can write to the directory before enabling reporting.

To opt in after rollout, set `WRAPLINK_DNS_QUERY_REPORT_ENABLED=true` in the platform `.env` and recreate DNS-Control. To inspect the mount without printing secrets, run:

```bash
docker compose -f compose.yml -f compose.prod.yml config --quiet
docker compose -f compose.yml -f compose.prod.yml ps dns-control
docker compose -f compose.yml -f compose.prod.yml logs --tail=100 dns-control
docker volume ls --filter name=dnsqueryspool
```

A persisted batch is replayed after a restart with its original event IDs; Backend must deduplicate those IDs. This is **not** a guarantee that every DNS request survives a crash: events still in the bounded memory channel have not yet reached disk. Long outages may fill both the spool and memory queue. Monitor `delivered`, `failed_batches`, `dropped`, `pending` logs and disk capacity. See [DNS-Control query reporting operations](https://github.com/Wraplink/dns-control/blob/main/docs/dns-query-reporting-operations.md).

## 6. Operator checks

```bash
# Verify Compose structure without dumping resolved secret values
docker compose -f compose.yml -f compose.prod.yml config --quiet

# Check that variables are set without displaying their values
for key in NETWORK_CONTROL_SYNC_KEY DNS_CONTROL_API_TOKEN DNS_CONTROL_AGENT_TOKEN; do
  if grep -Eq "^$key=.+$" .env; then echo "$key: present"; else echo "$key: missing/empty"; fi
done
```

For standalone services, verify `.env.local` is passed with Compose `env_file`, use `chmod 600 .env.local`, and inspect startup logs for missing variables, auth failures, invalid node IPs, and TLS errors. For remote nodes, `http://backend:7080` and `http://dns-control:8080` are Docker-only names and **will not resolve** outside the central Compose network.

See [new Edge Agent setup](https://github.com/Wraplink/edge-agent/blob/main/docs/new-agent-setup.md) and [new DNS Control setup](https://github.com/Wraplink/dns-control/blob/main/docs/new-dns-control-setup.md).
