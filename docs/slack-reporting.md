# WrapLink Slack event reporting

## Scope

The platform repository sends **GitHub issue, pull request and selected failed workflow** notifications to a Slack channel through an incoming webhook. This is an initial GitHub reporting integration, **not** runtime error monitoring or a bidirectional ticket sync.

## Setup

1. In the `wraplink.slack.com` workspace, create or choose a channel (suggested: `#wraplink-alerts`).
2. Configure a Slack app with **Incoming Webhooks** enabled, add a webhook for the channel, and copy the generated HTTPS URL.
3. In **Wraplink/platform → Settings → Secrets and variables → Actions**, create repository secret `WRAPLINK_SLACK_WEBHOOK_URL`. Never commit or print the URL.
4. Merge the workflow PR and run **Actions → Slack project notifications → Run workflow** to test delivery.
5. For other repositories (backend, web, dns-control, edge-agent), replicate the workflow and notifier with a webhook secret in each repository, or adopt an organization-level reusable workflow and approved secrets. This PR covers only the platform repository.

## Events

- Issues: opened, reopened, closed.
- Pull requests: opened, reopened, ready for review, closed, merged.
- Failed workflow runs named CI, Build, Deploy, or Deployment (adjust names to match actual workflows).
- Manual test via workflow_dispatch.

Messages include links and short titles. They intentionally exclude issue bodies, logs, credentials and payload contents.

## Runtime alerts (next phase)

Backend, DNS Control, Edge Agent and Web should emit structured error events to a central alerting component. Include `service`, `environment`, `severity`, `fingerprint`, `timestamp`, `correlation_id`, `count`, and a safe dashboard URL. Group identical fingerprints over a configurable window, rate-limit messages, send recovery notifications, and redact tokens, IPs or personal data as appropriate. Use a queue/outbox with retries and a dead-letter path. Keep the Slack webhook server-side only. Runtime alerting is **not implemented** by this workflow.

## Security and troubleshooting

- `pull_request_target` runs trusted default-branch workflow code and does **not** check out or execute pull-request code. Do not add untrusted PR scripts to this job.
- Use the narrowest channel/app permissions available and rotate compromised webhooks.
- Missing secret: workflow skips notifications and logs a notice.
- HTTP/network error: job fails without logging the secret URL; inspect Actions logs.
- No CI alerts: confirm the workflow names in the `workflow_run.workflows` list match the actual workflow display names.
- Slack messages are best-effort; GitHub Actions may retry via rerunning a failed job. Delivery is not exactly-once.

## Current integration status and runtime setup (November 2026)

All five repositories now include GitHub Slack reporting workflows. Backend also includes a PostgreSQL-backed Slack outbox for support tickets and contact submissions, and an authenticated runtime alert ingestion endpoint. DNS Control and Edge Agent send selected runtime errors to that backend endpoint.

A successful Actions run can mean that the webhook was not configured: inspect logs for `Slack webhook is not configured; notification skipped.` Add the Actions secret `WRAPLINK_SLACK_WEBHOOK_URL` to each of the five repositories or use an organization secret accessible to all five. Trigger the workflows manually and confirm messages appear in the intended Slack channel.

For runtime reporting, set `WRAPLINK_SLACK_WEBHOOK_URL` and a long random `WRAPLINK_ALERT_INGEST_KEY` in the production untracked `.env`. Apply backend migrations before deploying. The DNS Control container uses the private Compose address `http://backend:7080`. Dedicated Edge Agent hosts additionally require `WRAPLINK_ALERT_API_URL` set to a backend base URL reachable from host networking, preferably through private HTTPS, and the same `WRAPLINK_ALERT_INGEST_KEY`. Never use the Docker-only backend hostname on a remote edge host. Restrict access to `/api/v1/internal/alerts` to trusted services.

Validate by creating a test contact message and support ticket, testing a controlled DNS sync error and Edge Agent error in staging, and verifying actual Slack delivery. Inspect `slack_outbox` attempts and delivery timestamps for failures. The outbox is at-least-once; duplicates are possible. The integration does not provide bidirectional Slack ticket sync.
