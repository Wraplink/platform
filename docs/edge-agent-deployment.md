# Dedicated Edge Agent deployment (Debian 13)

This runbook provisions **one new edge host** without changing existing agents. It uses the platform repository's `compose.edge.yml` and `scripts/deploy.sh edge`.

> Do not use the central production `.env` on an edge server. Store only the credentials required by this agent. Never commit secrets or publicly expose the Backend/DNS Control management APIs.

## 1. Record the deployment details

Fill in these values before continuing:

| Setting | Example (replace) |
| --- | --- |
| Agent ID | `edge-eu-02` (unique across WrapLink) |
| Region | `eu-1` |
| Edge host public SNI IPv4 | `SNI_PUBLIC_IPV4` |
| Dedicated full-route IPv4 | `ROUTE_PUBLIC_IPV4` (optional, assigned to this host) |
| DNS Control API URL | `https://dns-control.example.net` (private/protected endpoint) |
| Backend URL | `https://backend.example.net` (private/protected endpoint) |
| DNS Control API token | Secret matching central DNS Control |
| Network control key | Secret matching central Backend |

The SNI and full-route public IPs should be separate. For NAT deployments, verify that the public addresses actually forward to this host. Do not advertise an outbound proxy/egress IP as an inbound address.

## 2. Prepare the edge server

Install Docker Engine and the Compose plugin following Docker's Debian instructions, then verify:

```bash
docker --version
docker compose version
ip -br addr
ip route
sudo ss -lntup | grep -E ':(443|8443|9091)\b' || true
sudo nft list ruleset > "$HOME/nft-before-wraplink.txt"
```

Check that the intended SNI listener port is free. Save the nftables snapshot for troubleshooting. Allow outbound HTTPS to the Backend and DNS Control APIs, and outbound UDP/TCP 53 to the independent upstream resolvers. Allow inbound TCP/443 to the SNI IP only when SNI is enabled. Full Route additionally needs the protocol/port reachability and forwarding/NAT configuration appropriate to the assigned destination leases; do not broadly expose the Backend control API.

## 3. Check out the platform and agent

```bash
git clone https://github.com/Wraplink/platform.git
cd platform
bash scripts/checkout.sh
test -f services/edge-agent/Dockerfile
cp .env.example .env
chmod 600 .env
```

**Do not run the central production deployment on the edge host.** Replace example secrets and configure edge-specific settings. `scripts/init-env.sh` is optional for local bootstrap but its generated shared tokens are NOT the credentials of your existing central platform.

## 4. Configure the edge environment

Add/update the following values in the edge host's private `.env`:

```dotenv
APP_ENV=production
EDGE_ID=edge-eu-02
EDGE_REGION=eu-1
DNS_CONTROL_API_URL=https://dns-control.example.net
DNS_CONTROL_API_TOKEN=REPLACE_WITH_EXISTING_DNS_CONTROL_TOKEN
WRAPLINK_BACKEND_URL=https://backend.example.net
NETWORK_CONTROL_SYNC_KEY=REPLACE_WITH_EXISTING_BACKEND_CONTROL_KEY
WRAPLINK_ALERT_API_URL=
WRAPLINK_ALERT_INGEST_KEY=
```

The example URLs are placeholders. Use a private network or authenticated TLS ingress; Docker-only names such as `http://backend:7080` are not reachable from a separate edge host. Do not use the public website URL unless its API paths are explicitly routed and protected.

## 5. Configure `config/edge-agent.yml`

Start in **SNI-only** mode (replace the IPv4 placeholder with the edge host's real reachable IP):

```yaml
dns_control:
  url: ${DNS_CONTROL_API_URL}
  token: ${DNS_CONTROL_API_TOKEN}
backend:
  url: ${WRAPLINK_BACKEND_URL}
  control_key: ${NETWORK_CONTROL_KEY}
  route_public_ips: []
agent:
  id: "${EDGE_ID}"
  region: "${EDGE_REGION}"
  interval: 10s
  capacity:
    sni: 100
    route: 0
edge:
  local_output_dnat: false
  upstream_dns:
    - "1.1.1.1:53"
    - "8.8.8.8:53"
  addresses:
    - "SNI_PUBLIC_IPV4"
  sni:
    enabled: true
    listen_address: "0.0.0.0:443"
    max_connections: 1024
    client_hello_timeout: 5s
diagnostics:
  enabled: false
  listen_address: "127.0.0.1:9091"
  token: ""
```

The Compose file maps `NETWORK_CONTROL_KEY` from `NETWORK_CONTROL_SYNC_KEY`. Never put secrets directly in the YAML. Verify `0.0.0.0:443` is not occupied by another service and that the inbound public IP reaches this host.

**Full Route (only after SNI registration works):** provision and route a separate public IPv4 to the edge host, add it to `edge.addresses` and `backend.route_public_ips`, then set `agent.capacity.route` to a positive value. Ensure the IPv4 is genuinely assigned/routed to this host and not already owned by another agent. Coordinate nftables and firewall policy before assigning production leases.

## 6. Validate Compose and start the agent

```bash
docker compose --env-file .env -f compose.edge.yml config --quiet
bash scripts/deploy.sh edge
docker compose --env-file .env -f compose.edge.yml ps
docker compose --env-file .env -f compose.edge.yml logs --tail=150 edge-agent
```

The `edge-agent` container uses `network_mode: host` and capabilities `NET_ADMIN`/`NET_RAW`. Treat this host as privileged network infrastructure. Avoid using `compose.yml` on this dedicated host.

## 7. Confirm registration and network readiness

From a trusted administrative machine, check DNS Control's agent diagnostics API (`GET /api/v1/agents`) with the configured API authentication; confirm the **new unique agent ID**, advertised IPs, region, heartbeat/last-seen, SNI enabled, and listener address. Also check the WrapLink Admin Network page for agent inventory and available capacity.

On the edge host:

```bash
sudo ss -lntp | grep ':443 '
sudo nft list ruleset
docker compose --env-file .env -f compose.edge.yml logs --since=10m edge-agent
```

Do not assign live domains until registration, reachable inbound IP, authorized-client behavior, and SNI TLS pass end-to-end testing. For Full Route, additionally verify lease acknowledgment, DNAT rules, both TCP/UDP where configured, traffic accounting, and recovery after an agent restart.

## 8. Common failures

| Symptom | Check |
| --- | --- |
| `missing environment variables` | `.env` keys and `NETWORK_CONTROL_KEY` mapping in Compose |
| Agent cannot register | DNS Control URL, token, TLS, network reachability and logs |
| Agent appears offline | Unique ID, heartbeats, time sync, Backend reachability |
| SNI port bind fails | Existing listener on TCP/443 or incorrect host networking |
| Full Route capacity rejected | Route public IP must also be listed in `edge.addresses` |
| Domains not allocated | Agent capacity, active registration, backend inventory, DNS lease status |
| SNI TLS fails | Public-IP forwarding, firewall, independent upstream DNS, and SNI listener |
| nftables conflicts | Compare saved pre-deployment rules; inspect existing tables before changes |

## 9. Rollback

Stop only the dedicated agent, preserving central services:

```bash
docker compose --env-file .env -f compose.edge.yml stop edge-agent
```

Drain or reassign any active leases first; stopping an agent with live traffic can interrupt clients. Inspect nftables and the saved snapshot before manually removing rules. Do **not** flush the entire host firewall.

## 10. Production acceptance checklist

- [ ] Unique ID and correct region
- [ ] Inbound IP verified (not outbound NAT address)
- [ ] API credentials protected and matching central services
- [ ] Agent registered and healthy
- [ ] SNI listener reachable on intended public IP
- [ ] Authorized client succeeds; unauthorized client is denied
- [ ] Full Route IP independently provisioned, if enabled
- [ ] DNS answer and lease match the assigned agent
- [ ] Routing works for configured protocols
- [ ] Usage/accounting reports correctly
- [ ] Agent restart and rollback tested
