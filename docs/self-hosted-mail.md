# WrapLink self-hosted mail: deployment, firewall and troubleshooting

This runbook describes the **send-only** mail relay in `compose.yml` and `compose.prod.yml` on Debian 13. The backend sends verification/reset messages to Postfix via the isolated Docker `mailnet`; Postfix signs through OpenDKIM and connects to recipient MX servers over outbound TCP 25. **There is no inbound SMTP service, IMAP, mailbox or webmail.** Receiving replies/bounces requires separate design.

## Architecture and environment

- `mail`: custom Debian 13 image at `docker/mail/Dockerfile`; startup script `docker/mail/entrypoint.sh`; Postfix listener on container port 25; OpenDKIM milter on loopback port 8891 **inside the mail container**.
- `backend`: shares `mailnet` with `mail`; Compose sets `SMTP_HOST=mail`, `SMTP_PORT=25`, `SMTP_USERNAME=`, `SMTP_PASSWORD=`, `SMTP_ALLOW_PLAINTEXT_INTERNAL=true` and `SMTP_FROM`. The backend permits plaintext unauthenticated SMTP **only** for `mail:25` inside this private network.
- `mailnet`: dedicated Docker bridge subnet `172.30.91.0/24`. **Check for collisions** with host, VPN, or existing Docker networks before deployment; if changed, update both Compose IPAM and `MAIL_ALLOWED_NETWORK`. Only trusted backend/mail containers may join. The SMTP relay trusts this subnet, so never attach untrusted workloads.
- `MAIL_DOMAIN=wraplink.ir`, `MAIL_HOSTNAME=mail.wraplink.ir`, `SMTP_FROM=no-reply@wraplink.ir` in `.env`. The backend's SMTP host/port are overridden by Compose; do not configure Mailerever credentials for this deployment.
- `mailqueue` Docker volume holds the Postfix queue; `mailkeys` holds DKIM keys. Back up securely. **Never run `docker compose down -v`** on a live installation.
- Production `FRONTEND_URL=https://wraplink.ir`, `APP_ENV=production`, `SECURE_COOKIES=true` must also be configured.

## Firewall / network port matrix

These are baseline requirements for the **central WrapLink platform**; edge-agent route/SNI ports depend on its separate host/IP and must be inventoried separately.

| Direction | Port / protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| Inbound | 22/TCP (or configured SSH port) | SSH administration | Restrict to trusted management addresses; preserve SSH access before enabling firewall |
| Inbound | 53/UDP + 53/TCP | Public DNS Control queries | Public only if this node serves public DNS |
| Inbound | 80/TCP | HTTP / ACME HTTP-01 / redirect | Public |
| Inbound | 443/TCP | Nginx HTTPS | Public |
| Outbound | **25/TCP** | Postfix direct delivery to recipients' MX | **Required**; also must be allowed by VPS provider |
| Outbound | 53/UDP + 53/TCP | DNS lookup (if using external DNS) | Required for resolving MX/A |
| Outbound | 80/TCP + 443/TCP | Package updates, ACME, HTTP(S) dependencies | Usually allow |
| Outbound | 123/UDP | Time sync, if using NTP | Allow if needed |
| Internal Docker only | 25/TCP | Backend -> Postfix | **Never publish** from `mail` to host |
| Internal mail container only | 8891/TCP | Postfix -> OpenDKIM milter | Loopback; never publish |
| Loopback host only (production Compose) | 3000/TCP | Next.js | 127.0.0.1 only |
| Loopback host only (production Compose) | 7080/TCP | Backend | 127.0.0.1 only |
| Loopback host only (production Compose) | 8080/TCP | DNS Control API | 127.0.0.1 only |
| Private Docker only | 5432/TCP | PostgreSQL | Never publish publicly |
| Not needed inbound | 25, 465, 587, 110, 143, 993, 995 | Mail reception/submission/mailboxes | **Keep closed** |

No additional inbound mail port is necessary for send-only operation. Docker-published ports can bypass UFW's normal INPUT filtering; audit Docker port mappings, host firewall and VPS firewall together. For nftables-based edge routing, inspect existing chains before changing firewall rules.

### UFW example (only if UFW is the selected firewall)

Check current SSH port, access rules, Docker networking and nftables first. Applying `ufw enable` remotely without a working SSH allowance can lock you out.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from YOUR_TRUSTED_ADMIN_IPV4 to any port 22 proto tcp
sudo ufw allow 53/udp
sudo ufw allow 53/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw status verbose
# Enable only after reviewing rules and ensuring console/recovery access:
# sudo ufw enable
```

If outbound policy is deny, explicitly permit outbound TCP 25, DNS, HTTPS/HTTP and any required NTP. Cloud/VPS firewalls may separately block outbound TCP 25 regardless of local UFW settings. **Do not open inbound TCP 25 to solve an outbound block.**

### Verify listening ports and actual Compose exposure

```bash
docker compose -f compose.yml -f compose.prod.yml config
docker compose -f compose.yml -f compose.prod.yml ps
sudo ss -lntup
sudo ufw status verbose
sudo nft list ruleset
docker network ls
```

Check that `mail` shows `25/tcp` but **not** `0.0.0.0:25->25/tcp`. Review any additional edge-agent ports and dedicated IPs independently.

## DNS / Cloudflare

Example for the current WrapLink sending IPv4 `80.210.62.115`; update if the IP changes. Set Cloudflare's `mail` A record to **DNS only**, not proxied. PTR is managed by the VPS provider, not Cloudflare.

| DNS type | Name | Example value / source | Notes |
| --- | --- | --- | --- |
| A | `mail` | `80.210.62.115` | DNS only |
| PTR (reverse DNS) | `80.210.62.115` | `mail.wraplink.ir` | Configure at hosting provider; must forward-resolve to same IP |
| TXT | `@` | `v=spf1 ip4:80.210.62.115 ~all` | One SPF TXT; merge other authorized senders into it |
| TXT | `mail._domainkey` | Public key from `/etc/opendkim/keys/mail.txt` | Never publish private key |
| TXT | `_dmarc` | `v=DMARC1; p=none` | Monitoring phase; later evaluate stronger policy |

No MX record is needed **to send** mail. However, with no working inbound mailbox for the envelope sender, delivery-status notifications/bounces may be lost. Before production scale, arrange a monitored bounce/abuse mailbox or bounce processing strategy.

Previous provider-specific `everp-api._domainkey` and `mtaa` records may remain temporarily during migration; remove them only when the old provider is no longer used. Do not publish multiple SPF or DMARC TXT records for the same hostname.

### Generate and publish DKIM

```bash
docker compose -f compose.yml -f compose.prod.yml up -d --build mail backend
docker compose -f compose.yml -f compose.prod.yml logs --tail=100 mail
docker compose -f compose.yml -f compose.prod.yml exec mail cat /etc/opendkim/keys/mail.txt
```

Copy the **complete TXT value** (concatenate the quoted segments) to `mail._domainkey.wraplink.ir` in Cloudflare. Do not include `IN TXT`, parentheses, comments or quote delimiters.

```bash
dig TXT mail._domainkey.wraplink.ir @1.1.1.1 +short
docker compose -f compose.yml -f compose.prod.yml exec mail \
  opendkim-testkey -d wraplink.ir -s mail \
  -k /etc/opendkim/keys/mail.private -vvv
```

`key OK` means the private and published public keys match. `key not secure` typically means DNSSEC authentication was not established; it does **not** invalidate DKIM.

### Verify SPF, DMARC, PTR and outbound SMTP

```bash
dig TXT wraplink.ir @1.1.1.1 +short
dig TXT _dmarc.wraplink.ir @1.1.1.1 +short
dig A mail.wraplink.ir @1.1.1.1 +short
dig -x 80.210.62.115 @1.1.1.1 +short
nc -vz -w 8 gmail-smtp-in.l.google.com 25
```

SPF and DMARC DNS publication alone does not prove that an actual email passes authentication. Check the recipient's message headers (`Authentication-Results`) for `spf=pass`, `dkim=pass`, `dmarc=pass`, and correct domain alignment.

## Runtime health and delivery testing

```bash
docker compose -f compose.yml -f compose.prod.yml ps mail backend
docker compose -f compose.yml -f compose.prod.yml logs --tail=100 mail
docker compose -f compose.yml -f compose.prod.yml exec mail sh -c 'postfix status; pgrep -a opendkim; postqueue -p'
docker compose -f compose.yml -f compose.prod.yml exec mail postconf -n
```

To test end-to-end, register a disposable WrapLink user using an email address you control. Check backend logs for SMTP submission errors, Postfix logs for recipient response, and the received message's original headers. **Backend SMTP acceptance means queued/accepted locally, not delivered to the destination.** Avoid publishing verification tokens or message bodies in logs/support tickets. Check spam folders and recipient policies.

## Troubleshooting matrix

| Symptom | Likely cause | Check / corrective action |
| --- | --- | --- |
| Mail container repeatedly restarts; `/etc/opendkim/keys is writeable and owned by uid 100 which is not executing uid (0)` | OpenDKIM identity/ownership mismatch (fixed in platform PR #15) | Update platform and rebuild mail image; verify `UserID opendkim:opendkim`, key directory ownership and restrictive permissions; preserve `mailkeys` |
| `DKIM signer stopped` | OpenDKIM process exited; entrypoint restarts | Read preceding signer errors in `logs mail`; inspect `pgrep -a opendkim`, permissions and config |
| `key OK` plus `key not secure` | DKIM matches but DNSSEC not validated | Usually informational; confirm DKIM in received message |
| DKIM TXT not found | Missing/wrong Cloudflare name or propagation | `dig TXT mail._domainkey.wraplink.ir @1.1.1.1 +short`; use `mail._domainkey` name |
| SPF/DMARC TXT empty | Missing record or wrong name/zone | Add `@` SPF and `_dmarc` TXT; query authoritative/public resolver; avoid duplicate SPF |
| SMTP connection times out on outbound 25 | Provider/cloud firewall block, local firewall, or routing | `nc -vz -w 8 gmail-smtp-in.l.google.com 25`; check VPS support policy; opening inbound 25 will not help |
| PTR returns wrong hostname | Reverse DNS unset/incorrect | Configure PTR at VPS provider, and A record to match |
| Backend says SMTP STARTTLS unavailable | Backend not using internal relay settings / wrong image | Ensure merged backend PR #68 is deployed, `SMTP_HOST=mail`, `SMTP_PORT=25`, `SMTP_ALLOW_PLAINTEXT_INTERNAL=true` via Compose |
| `relay access denied` | Wrong Docker subnet/trust configuration | Compare mailnet subnet with `MAIL_ALLOWED_NETWORK`; do not widen trust to public networks |
| `milter-reject` or `Connection refused` to 8891 | OpenDKIM not running/listening | Inspect `pgrep -a opendkim`, mail logs, and loopback milter config |
| Mail queued/deferred | Remote temporary error, DNS, IP reputation, or outbound block | `postqueue -p`, logs; fix root cause, then allow normal retries; avoid deleting queue |
| Gmail rejects or spam-folders | PTR/SPF/DKIM/DMARC misalignment, IP reputation, message content, or policy | Check exact SMTP rejection and received headers; sending reputation cannot be guaranteed |
| Old Mailerever host fails DNS | `send.mailerever.net` did not resolve during prior testing | This self-hosted setup uses `mail:25`, not provider SMTP; remove stale overrides |
| Backend reports send success but recipient gets nothing | Local queue accepted, remote delivery failed or delayed | Inspect Postfix queue/logs and recipient spam folder; add bounce monitoring |

## Operations and security

- Monitor queue size, deferred deliveries, container restarts, disk space and DKIM signer availability. Define alerts and retry/bounce handling before high-volume sending.
- Restrict SSH to trusted addresses, avoid public SMTP exposure, keep OS/images updated, and do not attach arbitrary containers to the trusted mail network.
- Back up `mailkeys` securely and keep `mailqueue` persistent. A key rotation requires publishing the new DKIM TXT and coordinated deployment.
- For real-world sending, set rate limits, abuse prevention and signup throttling at the backend. A new VPS IP may have poor reputation even with all DNS records correct.
- If outbound port 25 is permanently blocked, direct-to-MX delivery is not viable; use a verified SMTP relay rather than opening inbound ports.


## Changing the outbound mail IP (direct or SOCKS5)

**Identify the actual egress IP, not just the VPS address.** Gmail reported `93.187.70.13` for a message sent via the configured SOCKS5 proxy; the WrapLink host's public IP was `80.210.62.115`. These are examples from November 2026, not permanent addresses.

1. Determine whether Postfix sends directly or via `MAIL_PROXY_ENABLED=true` and `MAIL_PROXY_HOST`/`MAIL_PROXY_PORT`. With a proxy, confirm the **actual SMTP TCP/25 egress IP** with the proxy provider or recipient headers/bounce diagnostics; a generic HTTPS IP-check can use a different exit. Ensure the proxy has stable egress and permits SMTP/25.
2. Edit the **existing single** SPF TXT record at `wraplink.ir` to authorize every current outbound egress IP. For example, during migration: `v=spf1 ip4:80.210.62.115 ip4:93.187.70.13 ~all`. Remove obsolete IPs after migration. Do **not** add a second `v=spf1` record.
3. If the **direct sending host** changes IP, update `mail.wraplink.ir` A (DNS-only if using Cloudflare), and request a matching PTR from the IP owner. For proxy egress, PTR belongs to the proxy exit IP and is controlled by its provider; changing the mail host A record alone does not change the proxy's reverse DNS. For robust delivery, coordinate a stable exit with suitable PTR/forward DNS and HELO identity.
4. DKIM `mail._domainkey.wraplink.ir` is tied to the signing **key**, not the sending IP. **Do not regenerate DKIM merely because the IP changes.** DMARC also does not need an IP-specific edit if the From domain stays the same.
5. Check public DNS and send a **fresh** test message. Inspect the Gmail "Show original" authentication results and any bounce's `Diagnostic-Code`. An empty queue does not prove delivery.

```bash
dig +short TXT wraplink.ir @1.1.1.1
dig +short TXT mail._domainkey.wraplink.ir @1.1.1.1
dig +short TXT _dmarc.wraplink.ir @1.1.1.1
dig +short A mail.wraplink.ir @1.1.1.1
dig +short -x 93.187.70.13 @1.1.1.1
docker compose -f compose.yml -f compose.prod.yml exec mail postqueue -p
```

If changing proxy settings, update `.env` (`MAIL_PROXY_ENABLED`, `MAIL_PROXY_HOST`, `MAIL_PROXY_PORT`, and optional credentials) and recreate only the mail service:

```bash
docker compose -f compose.yml -f compose.prod.yml up -d --force-recreate mail
docker compose -f compose.yml -f compose.prod.yml exec mail postconf -M smtp/unix
```

Keep credentials out of command output, tickets and git.

## DKIM mismatch and deliberate key regeneration

First diagnose, **without rotating keys**:

```bash
docker compose -f compose.yml -f compose.prod.yml exec mail \
  opendkim-testkey -d wraplink.ir -s mail -k /etc/opendkim/keys/mail.private -vvv
docker compose -f compose.yml -f compose.prod.yml exec mail \
  cat /etc/opendkim/keys/mail.txt
dig +short TXT mail._domainkey.wraplink.ir @1.1.1.1
```

- `key OK`: published DNS key matches the local private key; this alone does not prove Gmail validated a delivered signature.
- `keys do not match`: publish the **matching public TXT** from the persistent key's `mail.txt` first, rather than generating a new key. Confirm the TXT value and selector, wait for DNS caches to expire, and rerun the test.
- `key not secure`: DNSSEC verification was not established; not itself a DKIM failure.
- Do not use `openssl pkey -pubout -outform DER` as a drop-in DKIM TXT `p=` value: its SubjectPublicKeyInfo encoding may not match the DKIM record's expected RSA key encoding.

**Rotate only if the private key is compromised, missing, or intentional rotation is required.** The following example stages a new 2048-bit RSA key with a **new selector** `mail2026b`, allowing DNS propagation without breaking mail signed by the old selector. Run during a maintenance window; do not expose private keys:

```bash
# Generate a new key pair in a temporary private directory inside the mail container.
docker compose -f compose.yml -f compose.prod.yml exec -u root mail sh -ec '
  install -d -m 700 /root/dkim-rotation
  opendkim-genkey -b 2048 -d wraplink.ir -s mail2026b -D /root/dkim-rotation
  cat /root/dkim-rotation/mail2026b.txt
'
```

1. Publish the new TXT record at `mail2026b._domainkey.wraplink.ir` using the **entire** generated TXT value (join quoted fragments). Keep the old `mail._domainkey` record published.
2. Wait for DNS propagation. Then, in the mail container, install the new private key in the **persistent** `/etc/opendkim/keys` directory, with the same owner and permissions as the existing key. Back up the original key securely first. The generated temporary key disappears on container recreation, so **copy it to persistent storage before restarting**.
3. Change the OpenDKIM signing selector and key path in the deployment configuration to `mail2026b` and `/etc/opendkim/keys/mail2026b.private`. **Do not edit only the runtime container**: `docker/mail/entrypoint.sh` currently configures the selector/key on startup, so the change must be made in the repository and redeployed. Verify the active OpenDKIM configuration after deployment.
4. Verify with `opendkim-testkey -d wraplink.ir -s mail2026b -k /etc/opendkim/keys/mail2026b.private -vvv`, then send a new message and confirm `dkim=pass` and `dmarc=pass` at the recipient.
5. Retain the old public selector record long enough for delayed messages to be verified. Remove it only after the transition window; securely retain or retire old private keys according to policy.

**Important:** The current entrypoint may generate/reuse the original `mail` selector on startup. The new-selector procedure requires the configuration change in step 3; do not run the generation command alone and assume the new key is in use.

## Bounce and delivery-status troubleshooting

A `MAILER-DAEMON` message queued to `no-reply@wraplink.ir` is a delivery failure report, **not proof of successful delivery**. Inspect it with `postcat -q QUEUE_ID` and find `Diagnostic-Code`. Gmail `550 5.7.26` with `SPF ... did not pass` and `DKIM = did not pass` means authentication failed. In particular, SPF must authorize the **proxy exit IP** if the SMTP connection exits via SOCKS5.

After capturing the failure details, remove **only that known obsolete bounce**, if appropriate, with `postsuper -d QUEUE_ID`; never clear the whole mail queue as routine troubleshooting. This send-only deployment does not currently provide a reliable inbound bounce mailbox; arrange monitored bounce processing and Postfix logging before production volume.
