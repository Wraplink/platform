# WrapLink outbound proxy runbook (Debian 13)

This guide covers the SSH SOCKS5 service, APT, Git, Docker builds, and Docker Engine image pulls on a restricted-egress WrapLink host. Example values (replace `PROXY_SERVER_IP` and `PROXY_LAN_IP` with your own addresses; the latter must be a reachable address on the tunnel host):

- SSH endpoint: `root@PROXY_SERVER_IP`
- Private key: `/home/wraplink/vpn/id.rsa`
- SOCKS5 listener: `127.0.0.1:10810` on the tunnel host; LAN clients may use `PROXY_LAN_IP:10810` **only when intentionally allowed by firewall**.
- The local Linux account running the service is `wraplink`; it does **not** require sudo. Administrative installation commands below are run as root.

**Security:** A SOCKS5 listener on `0.0.0.0:10810` is unauthenticated. Prefer `127.0.0.1:10810` when all consumers are local, or restrict the LAN listener to trusted source IPs. Do not expose TCP 10810 to the internet. Confirm the remote SSH host-key fingerprint through a trusted channel before accepting it. Never disable SSH host-key verification to work around connection errors.

## 1. Persistent SSH SOCKS5 service

Install as root:

```bash
apt-get update
apt-get install -y autossh openssh-client curl util-linux
install -d -m 700 -o wraplink -g wraplink /home/wraplink/.ssh
chown wraplink:wraplink /home/wraplink/vpn/id.rsa
chmod 600 /home/wraplink/vpn/id.rsa
```

First verify the remote host's ED25519 fingerprint independently (for example, from the remote machine's trusted console using `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`). Then accept the matching host key as the **same local account** that runs autossh:

```bash
runuser -u wraplink -- ssh -i /home/wraplink/vpn/id.rsa \
  -o StrictHostKeyChecking=ask root@PROXY_SERVER_IP
# Confirm the fingerprint, type yes, then exit the remote shell.
runuser -u wraplink -- ssh -i /home/wraplink/vpn/id.rsa \
  -o BatchMode=yes -o StrictHostKeyChecking=yes \
  root@PROXY_SERVER_IP 'echo SSH_OK'
```

Create `/etc/systemd/system/wraplink-socks5.service` as root:

```ini
[Unit]
Description=WrapLink persistent outbound SOCKS5 tunnel
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=wraplink
Group=wraplink
WorkingDirectory=/home/wraplink
Environment=AUTOSSH_GATETIME=0
ExecStart=/usr/bin/autossh -M 0 -N -i /home/wraplink/vpn/id.rsa -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=10 -o TCPKeepAlive=yes -o ConnectionAttempts=1 -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none -D 127.0.0.1:10810 root@PROXY_SERVER_IP
Restart=always
RestartSec=5
TimeoutStopSec=10
KillMode=control-group

[Install]
WantedBy=multi-user.target
```

If Docker containers or other **LAN hosts** must access this tunnel, replace `-D 127.0.0.1:10810` with `-D PROXY_LAN_IP:10810` or `-D 0.0.0.0:10810` and explicitly firewall TCP 10810 to the required client IPs. The Docker container's `127.0.0.1` is **not** the host loopback. `-f` is intentionally omitted: systemd manages the foreground process.

```bash
systemctl daemon-reload
systemctl enable --now wraplink-socks5
systemctl status wraplink-socks5
journalctl -u wraplink-socks5 -n 50 --no-pager
ss -lntp | grep 10810
curl -fsS --proxy socks5h://127.0.0.1:10810 https://api.ipify.org
```

`systemctl active (running)` alone does not prove the SSH tunnel is established: autossh can remain active while SSH exits with status 255 (for example, due to missing `known_hosts`). Confirm the listening port and a successful proxied request. `ServerAliveInterval=15` and `ServerAliveCountMax=3` detect an unresponsive SSH transport in roughly 45 seconds; autossh/systemd restart it. With `-M 0`, autossh monitoring is disabled, so an application-level probe is required to detect a live SSH transport with broken forwarding.


### Automatic SOCKS5 recovery

Install the following watchdog as root. It checks remote DNS and HTTPS through the actual SOCKS5 listener, bypassing inherited proxy exclusions. If using a LAN-only listener, change the local probe address accordingly. If your existing tunnel unit has another name, adjust SERVICE below.

Create `/usr/local/bin/wraplink-socks5-health`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE=wraplink-socks5.service
PROXY=socks5h://127.0.0.1:10810
STATE=/run/wraplink-socks5-health
mkdir -p -m 700 "$STATE"
exec 9>"$STATE/lock"
flock -n 9 || exit 0

log() { logger -t wraplink-socks5-health -- "$*"; }

if ! systemctl is-active --quiet "$SERVICE"; then
    rm -f "$STATE/failures"
    exit 0
fi

for url in https://www.google.com/generate_204 https://www.cloudflare.com/cdn-cgi/trace https://github.com/; do
    if error=$(curl -q --proxy "$PROXY" --noproxy "" \
        --connect-timeout 5 --max-time 10 --silent --show-error \
        --fail --output /dev/null "$url" 2>&1); then
        if [[ -f "$STATE/failures" ]]; then log "SOCKS5 recovered"; fi
        rm -f "$STATE/failures"
        exit 0
    fi
    log "Probe failed: $url: $error"
done

failures=0
if [[ -f "$STATE/failures" ]]; then read -r failures < "$STATE/failures"; fi
failures=$((failures + 1))
echo "$failures" > "$STATE/failures"
log "All probes failed ($failures consecutive rounds)"
(( failures >= 3 )) || exit 0

# Monotonic uptime avoids wall-clock adjustments affecting cooldown.
read -r uptime _ < /proc/uptime
now=${uptime%%.*}
last=-120
if [[ -f "$STATE/last_restart" ]]; then read -r last < "$STATE/last_restart"; fi
(( now - last >= 120 )) || exit 0

# Recheck state; do not start a deliberately stopped tunnel.
systemctl is-active --quiet "$SERVICE" || exit 0
echo "$now" > "$STATE/last_restart"
log "Restarting $SERVICE"
systemctl try-restart "$SERVICE"
rm -f "$STATE/failures"
```

```bash
chown root:root /usr/local/bin/wraplink-socks5-health
chmod 755 /usr/local/bin/wraplink-socks5-health
bash -n /usr/local/bin/wraplink-socks5-health
```

Create `/etc/systemd/system/wraplink-socks5-health.service`:

```ini
[Unit]
Description=WrapLink SOCKS5 health check
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/wraplink-socks5-health
TimeoutStartSec=60
```

Create `/etc/systemd/system/wraplink-socks5-health.timer`:

```ini
[Unit]
Description=WrapLink SOCKS5 health monitoring

[Timer]
OnBootSec=30s
OnUnitInactiveSec=15s
AccuracySec=1s

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl restart wraplink-socks5.service
systemctl enable --now wraplink-socks5-health.timer
systemctl start wraplink-socks5-health.service
systemctl list-timers wraplink-socks5-health.timer
journalctl -t wraplink-socks5-health -f
```

Any successful endpoint clears the failure counter. Three consecutive rounds in which all endpoints fail trigger a restart, with at least 120 seconds between restart attempts. Each round can take up to 30 seconds, plus the 15-second interval between rounds. The timer does not start an intentionally stopped tunnel. A successful service restart is not proof of recovery; the next probe verifies it.

For diagnosis, compare remote and local DNS resolution:

```bash
curl -q -v --noproxy "" --max-time 15 --proxy socks5h://127.0.0.1:10810 https://www.google.com/generate_204
curl -q -v --noproxy "" --max-time 15 --proxy socks5://127.0.0.1:10810 https://www.google.com/generate_204
```

If only socks5 works, investigate remote DNS; if only socks5h works, investigate local DNS. If both fail, inspect the SSH transport, remote egress and destination availability. These comparisons are diagnostic clues, not definitive proof. Persistent upstream outages cannot be repaired by restarting SSH. Choose probe endpoints reachable from the remote server.

To disable automatic recovery for maintenance:

```bash
systemctl disable --now wraplink-socks5-health.timer
systemctl stop wraplink-socks5-health.service
```


## 2. APT (host package downloads)

APT on Debian supports `socks5h://`; `h` sends hostname resolution through the proxy.

Temporary test:

```bash
apt-get -o Acquire::http::Proxy="socks5h://127.0.0.1:10810" \
  -o Acquire::https::Proxy="socks5h://127.0.0.1:10810" update
```

Persist in `/etc/apt/apt.conf.d/90wraplink-proxy` (as root):

```conf
Acquire::http::Proxy "socks5h://127.0.0.1:10810";
Acquire::https::Proxy "socks5h://127.0.0.1:10810";
```

```bash
apt-config dump | grep -i proxy
apt-get update
```

Remove `/etc/apt/apt.conf.d/90wraplink-proxy` to revert. For another machine, replace loopback with its reachable, firewall-protected tunnel address.

## 3. Git (HTTPS remotes)

Configure **as the user that runs git**, typically `wraplink` (not via `sudo git`):

```bash
git config --global http.https://github.com.proxy socks5h://127.0.0.1:10810
git config --global --get http.https://github.com.proxy
git ls-remote https://github.com/Wraplink/web.git HEAD
git -C services/web pull origin main
```

To use the proxy for all HTTP(S) Git remotes instead, set `git config --global http.proxy socks5h://127.0.0.1:10810`. Remove the GitHub-only setting with `git config --global --unset http.https://github.com.proxy`. For `Could not resolve host: github.com`, check that the tunnel is listening and use `socks5h` (not `socks5`). SSH Git remotes (`git@github.com:...`) require separate SSH proxy configuration.

## 4. Docker: distinguish three different proxy paths

**A. Docker Compose build arguments (downloads inside image builds).** The existing mail build in `compose.yml` accepts:

```dotenv
BUILD_HTTP_PROXY=socks5h://PROXY_LAN_IP:10810
BUILD_HTTPS_PROXY=socks5h://PROXY_LAN_IP:10810
```

```bash
docker compose -f compose.yml -f compose.prod.yml build --no-cache mail
```

Use a proxy address reachable **from the build environment**. This SOCKS5 setting has been verified for the mail Dockerfile's APT operations; do not assume every build tool supports SOCKS5. These variables currently apply **only to the mail build**, not to all services. To proxy another build, explicitly wire suitable build arguments into that service's Dockerfile/Compose configuration. Do not pass secrets through public build arguments.

**B. Docker Engine image pulls (daemon).** `docker pull`, base-image fetching and registry access use the Docker daemon's egress, not APT or Git settings. Do not assume `socks5h://` works as a daemon HTTP(S) proxy. For blocked registries, provision a **trusted local HTTP CONNECT forward proxy** that itself routes through SOCKS5, then configure the Docker daemon to use its HTTP URL. Example, assuming an independently installed/verified HTTP CONNECT bridge listens at `127.0.0.1:3128`:

```bash
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:3128"
Environment="HTTPS_PROXY=http://127.0.0.1:3128"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
systemctl daemon-reload
systemctl restart docker
systemctl show --property=Environment docker
docker pull hello-world
```

**Do not apply this daemon configuration until the HTTP bridge exists and passes a test**, for example `curl -I --proxy http://127.0.0.1:3128 https://registry-1.docker.io/v2/` (an HTTP 401 from the registry is an expected sign of connectivity). Restarting Docker can interrupt running WrapLink containers; plan a maintenance window. Remove the drop-in, reload systemd and restart Docker to revert. If your daemon already has proxy settings, reconcile rather than overwrite them. The bridge is not installed by this guide.

**C. Runtime containers.** Host `127.0.0.1` does not refer to the host inside a container. Configure a host/LAN reachable proxy endpoint, network policy and per-service proxy variables as required. The mail relay's `MAIL_PROXY_ENABLED`, `MAIL_PROXY_HOST`, and `MAIL_PROXY_PORT` control **SMTP egress**, not Docker pulls or image builds. Do not route internal service-to-service traffic through an external proxy; set appropriate `NO_PROXY` for your deployment.

## 5. Shell convenience, validation and recovery

For optional CLI use, `source scripts/proxy-env.sh` reads `.env`:

```dotenv
PROXY_ENABLED=true
SOCKS5_PROXY_HOST=127.0.0.1
SOCKS5_PROXY_PORT=10810
```

The script exports `ALL_PROXY=socks5h://...` and `NO_PROXY`. Clients vary in their support for `ALL_PROXY`; Git's explicit config and APT's own proxy file are more predictable.

```bash
ss -lntp | grep 10810
curl -I --proxy socks5h://127.0.0.1:10810 https://github.com
git ls-remote https://github.com/Wraplink/web.git HEAD
apt-get update
journalctl -u wraplink-socks5 -n 50 --no-pager
```

If `Host key verification failed` appears, verify the remote fingerprint and the `known_hosts` file for the **service account**. If no listener appears, inspect SSH/authentication and port conflicts. If APT or Git fails while curl succeeds, inspect tool-specific proxy configuration. If Docker image pulls fail while curl succeeds, inspect Docker daemon egress separately.

The proxy affects **outbound** access only. Let's Encrypt HTTP-01 still requires inbound TCP 80 and correct public DNS for `wraplink.ir`; public HTTPS requires inbound TCP 443. Keep internal services and the proxy listener protected.
