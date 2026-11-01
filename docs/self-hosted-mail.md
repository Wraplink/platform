# Self-hosted transactional mail for WrapLink

The `mail` service is a **send-only** Postfix relay with OpenDKIM. It does not receive inbound mail or provide IMAP/webmail. The service is attached only to the dedicated `mailnet` Docker network, with no published SMTP port. Backend uses `mail:25` inside this network.

## Preconditions (mandatory before enabling production email)

1. Confirm outbound TCP port **25** is allowed by the hosting provider: `nc -vz -w 8 gmail-smtp-in.l.google.com 25`.
2. Set the public IPv4's PTR/rDNS to `mail.wraplink.ir` at your VPS provider; add Cloudflare **DNS-only** A record `mail.wraplink.ir` pointing to the same IPv4. Forward and reverse records must match.
3. Use a static public IPv4 with acceptable sending reputation. Major recipients may reject or spam-folder messages from new or residential IPs regardless of authentication.
4. Check Docker's `172.30.91.0/24` subnet is unused on the host. Change both `mailnet.ipam` and `MAIL_ALLOWED_NETWORK` if it conflicts. Treat this private subnet as trusted: only backend and mail should join it.
5. Configure `MAIL_DOMAIN`, `MAIL_HOSTNAME` and `SMTP_FROM` in `.env`. Do not configure the old provider's SMTP credentials.

## Start and publish DNS

```bash
docker compose -f compose.yml -f compose.prod.yml up -d --build mail backend
docker compose -f compose.yml -f compose.prod.yml logs --tail=100 mail
docker compose -f compose.yml -f compose.prod.yml exec mail cat /etc/opendkim/keys/mail.txt
```

The first startup generates a persistent 2048-bit DKIM key. Copy the **public** TXT value from `mail.txt` to `mail._domainkey.wraplink.ir` in Cloudflare. **Never publish or share `mail.private`.** The keys and mail queue survive container recreation in Docker volumes `mailkeys` and `mailqueue`. Do not remove these volumes during upgrades.

Suggested records (adjust IP and existing authorized senders):

| Type | Name | Content |
| --- | --- | --- |
| A (DNS only) | mail | Your sending server's public IPv4 |
| TXT | @ | `v=spf1 ip4:YOUR_PUBLIC_IPV4 ~all` if this is the only sender |
| TXT | mail._domainkey | Public DKIM key from `mail.txt` |
| TXT | _dmarc | `v=DMARC1; p=none` for initial monitoring |

If Mailerever still sends mail for the domain, retain its SPF include until you stop using it. Remove obsolete DKIM and return-path records only after confirming no provider still needs them. Do not create multiple SPF or DMARC TXT records for the same name. MX is not needed for outbound-only mail.

## Verify

```bash
dig A mail.wraplink.ir +short
dig -x YOUR_PUBLIC_IPV4 +short
dig TXT mail._domainkey.wraplink.ir +short
dig TXT wraplink.ir +short
dig TXT _dmarc.wraplink.ir +short
docker compose -f compose.yml -f compose.prod.yml exec mail postqueue -p
```

Register a test user and inspect the delivered message's Authentication-Results for SPF, DKIM and DMARC passes. Postfix queues transient failures for retry, but the backend currently considers successful local SMTP acceptance as successful sending, **not confirmed remote delivery**. Configure queue monitoring and bounce handling before scale.

**Security:** Never publish mail port 25/587 from Docker; do not attach untrusted containers to `mailnet`. This relay deliberately allows unauthenticated submissions from the dedicated private network. The backend's plaintext SMTP exception applies only to `mail:25`.
