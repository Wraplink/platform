#!/bin/sh
set -eu
: "${MAIL_DOMAIN:?MAIL_DOMAIN is required}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME is required}"
: "${MAIL_ALLOWED_NETWORK:?MAIL_ALLOWED_NETWORK is required}"
case "$MAIL_DOMAIN:$MAIL_HOSTNAME" in *[!a-zA-Z0-9.:-]*|'') echo "invalid mail domain or hostname" >&2; exit 1;; esac
mkdir -p /etc/opendkim/keys /run/opendkim /var/spool/postfix
if [ ! -s /etc/opendkim/keys/mail.private ]; then
  opendkim-genkey -b 2048 -s mail -d "$MAIL_DOMAIN" -D /etc/opendkim/keys
  mv /etc/opendkim/keys/mail.private /etc/opendkim/keys/mail.private.tmp
  chmod 600 /etc/opendkim/keys/mail.private.tmp
  mv /etc/opendkim/keys/mail.private.tmp /etc/opendkim/keys/mail.private
fi
chown -R opendkim:opendkim /etc/opendkim/keys /run/opendkim
cat > /etc/opendkim.conf <<EOF
Syslog yes
UMask 007
Mode s
Canonicalization relaxed/simple
Socket inet:8891@127.0.0.1
Domain $MAIL_DOMAIN
Selector mail
KeyFile /etc/opendkim/keys/mail.private
OversignHeaders From
EOF
postconf -e "myhostname = $MAIL_HOSTNAME"
postconf -e "mydomain = $MAIL_DOMAIN"
postconf -e "myorigin = $MAIL_DOMAIN"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = localhost"
postconf -e "relay_domains ="
postconf -e "mynetworks = 127.0.0.0/8, $MAIL_ALLOWED_NETWORK"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtp_helo_name = $MAIL_HOSTNAME"
postconf -e "smtp_header_checks ="
postconf -e "milter_default_action = tempfail"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:127.0.0.1:8891"
postconf -e "non_smtpd_milters = inet:127.0.0.1:8891"
postconf -e "maillog_file = /dev/stdout"
# Only start SMTP after the DKIM signer is running.
opendkim -x /etc/opendkim.conf -f &
dkim_pid=$!
trap 'kill "$dkim_pid" 2>/dev/null || true; postfix stop || true' TERM INT
postfix check
postfix start
echo "Mail relay ready. Publish the DKIM TXT key from /etc/opendkim/keys/mail.txt"
while kill -0 "$dkim_pid" 2>/dev/null; do sleep 5; done
echo "DKIM signer stopped" >&2
exit 1
