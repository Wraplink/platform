# WrapLink Slack app setup

This guide configures the Slack app used by WrapLink's GitHub workflows and backend runtime notifications. It contains no live credentials.

## Phase 1 — Slack app

1. Sign in at https://api.slack.com/apps using the workspace `wraplink.slack.com`.
2. Select **Create New App** > **From scratch**.
3. App name: **WrapLink Notifications**. Select the WrapLink workspace and create the app.
4. Create a public or private channel named `#wraplink-alerts` (recommended).
5. In the app configuration, open **Features > Incoming Webhooks** and enable incoming webhooks.
6. Select **Add New Webhook to Workspace**, choose `#wraplink-alerts`, and authorize.
7. Copy the generated HTTPS incoming webhook URL into a trusted secrets manager. **Never commit, paste into chat, or log the URL.**
8. Test delivery from a trusted terminal without printing the secret:

```bash
read -rsp 'Slack webhook URL: ' SLACK_WEBHOOK_URL; echo
curl --fail-with-body --silent --show-error \
  -H 'Content-Type: application/json' \
  --data '{"text":"WrapLink Slack integration test"}' \
  "$SLACK_WEBHOOK_URL"
unset SLACK_WEBHOOK_URL
```

Slack typically returns `ok` on success. Confirm the message appears in the channel. A workspace administrator may need to approve app installation.

## Phase 2 — GitHub Actions

Create an Actions secret named `WRAPLINK_SLACK_WEBHOOK_URL` in each repository: `Wraplink/platform`, `Wraplink/backend`, `Wraplink/dns-control`, `Wraplink/edge-agent`, `Wraplink/web`. Alternatively create one organization Actions secret and grant access to all five repositories.

For repository secrets: **Settings > Secrets and variables > Actions > New repository secret**. Set the exact name and paste the URL into GitHub's secret value field, not into a code file.

For organization secrets: organization **Settings > Secrets and variables > Actions > New organization secret**; choose repository access carefully. Availability of organization-level secrets depends on the GitHub plan and repository visibility.

Test in **Actions**: `platform` has **Slack project notifications**; the other four repositories have **Slack project reporting**. Select **Run workflow**, then check the Slack channel. The workflow may succeed while silently skipping if the secret is missing; inspect logs for the skipped notice.

## Phase 3 — backend and service alerts

In the server's untracked `.env`, set `WRAPLINK_SLACK_WEBHOOK_URL` to the same Slack webhook URL and `WRAPLINK_ALERT_INGEST_KEY` to a strong random shared key. The backend sends queued contact, support, and runtime alert notifications.

Generate a shared key locally, for example:

```bash
openssl rand -hex 32
```

Do not paste generated credentials into source control. Configure DNS Control and Edge Agent with the same alert ingest key. DNS Control uses the backend's private Compose address. Dedicated Edge Agent hosts require `WRAPLINK_ALERT_API_URL` pointing to a reachable, preferably private HTTPS, backend base URL; never use the Docker-internal hostname on a remote host.

Apply backend migrations and recreate the services after setting environment values. Protect the internal alert endpoint with network controls as well as the shared key. Test in staging before relying on production alerts.

## Verification checklist

- [ ] Slack app exists in the correct workspace.
- [ ] Incoming Webhooks enabled.
- [ ] Webhook bound to the intended channel.
- [ ] Manual test message received.
- [ ] GitHub Actions secrets configured for all five repositories.
- [ ] GitHub manual workflow tests received in Slack.
- [ ] Backend runtime environment and database migration applied.
- [ ] Test support ticket and contact message delivered.
- [ ] DNS Control and Edge Agent controlled failure alerts delivered.
- [ ] No secrets appear in logs, commits, issues, or chat.

## Troubleshooting

- No Slack message but green Actions run: inspect whether the webhook was absent and the notifier skipped.
- HTTP 403/404/410: verify webhook installation, channel authorization, and whether the webhook was revoked.
- HTTP 429: rate-limited; use retry/backoff and avoid bursts.
- Runtime delivery pending: inspect `slack_outbox` and backend logs, DNS connectivity, and HTTPS egress.
- Rotate a compromised webhook in Slack and update every GitHub secret and backend runtime configuration.

For architectural details, see [slack-reporting.md](slack-reporting.md).
