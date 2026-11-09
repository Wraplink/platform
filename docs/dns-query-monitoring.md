# DNS query monitoring and observed-domain registration

## Goal
Every DNS Control instance records authorized DNS queries (including normal, hijack, route, specific IP, block, REFUSED and SERVFAIL), reports them to Backend without blocking DNS responses, and exposes a searchable admin history. Admins can promote an observed FQDN to an existing domain resolution policy.

## Event contract
`POST /api/v1/internal/network/dns-queries/batch` authenticated with `X-Network-Control-Key` (same shared control-plane credential as DNS registration). JSON: `{controller_id, events:[{event_id, observed_at, domain, qtype, rcode, resolution_mode, duration_ms}]}`. Events have stable UUIDs for idempotent retries. Validate DNS names, enums, timestamps, event count and body size. Never accept caller-supplied policy changes via ingest.

## DNS Control
- Capture response RCODE at the response writer boundary, including denied queries, with no extra synchronous network calls in the DNS request path.
- Bounded nonblocking queue; background batch sender with exponential backoff, retry limits, and counters for dropped events. DNS resolution must work if Backend is unavailable.
- Record only the query's normalized domain and metadata by default, **not raw client IP**. Any future per-client tracking requires explicit opt-in and privacy review.
- Config: `WRAPLINK_DNS_QUERY_REPORT_ENABLED` (default false during rollout), `WRAPLINK_DNS_QUERY_BATCH_SIZE`, `WRAPLINK_DNS_QUERY_QUEUE_SIZE`, `WRAPLINK_DNS_QUERY_FLUSH_INTERVAL`.

## Backend
- Migration for partitionable DNS query event table, unique (controller_id,event_id), indexes on observed_at, domain, controller_id, rcode; enforce seven-day default retention via scheduled cleanup.
- Authenticated ingest validates controller identity, payload and size, and handles duplicates safely.
- `GET /api/v1/admin/network/dns-queries` supports page/pageSize (bounded), search, controller, qtype, rcode, mode, from/to; descending chronological ordering. Add aggregate counts/rates endpoint after basic ingestion.
- Admin-only permissions match existing network admin endpoints.

## Web
- Admin Network: DNS Queries tab/table with timestamp, domain, controller, qtype, RCODE, resolution mode and latency; search, filters, pagination and refresh.
- 'Register domain' action prefills existing Domain Resolution Policies editor; require explicit policy selection and confirmation. No automatic policy creation from observed traffic.
- Show reporting freshness, ingestion failures and dropped event counts so a quiet dashboard is not mistaken for no traffic.

## Rollout and verification
1. Backend migration, authenticated ingest, admin list API and tests.
2. DNS Control response capture, bounded async reporting and tests (including denied queries and Backend outage).
3. Web query table, filters and register-domain flow.
4. Deploy Backend first, DNS Control second with reporting disabled, then Web. Enable reporting after end-to-end checks.
5. Test UDP/TCP A/AAAA, REFUSED, SERVFAIL, repeated events, 401/403, queue overflow, retries, retention and domain policy promotion.

Do not store response payloads, raw client IPs, or credentials in query events. This document is a design contract; implementation requires separate PRs in Backend, DNS Control and Web.
