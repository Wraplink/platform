# WrapLink outbound proxy runbook (Debian 13)

This guide covers the SSH SOCKS5 service, APT, Git, Docker builds, and Docker Engine image pulls on a restricted-egress WrapLink host. Example values from this deployment:

- SSH endpoint: `root@PROXY_SERVER_IP`
- Private key: `/home/wraplink/vpn/id.rsa`
- SOCKS5 listener: `127.0.0.1:10810` on the tunnel host; LAN clients may use `192.168.10.114:10810` **only when intentionally allowed by firewall**.
- The local Linux account running the service is `wraplink`; it does **not** require sudo. Administrative installation commands below are run as root.

**Security:** A SOCKS5 listener on `0.0.0.0:10810` is unauthenticated. Prefer `127.0.0.1:10810` when all consumers are local, or restrict the LAN listener to trusted source IPs. Do not expose TCP 10810 to the internet. Confirm the remote SSH host-key fingerprint through a trusted channel before accepting it. Never disable SSH host-key verification to work around connection errors.

## 1. Persistent SSH SOCKS5 service

Install as root:

```bash
apt-get update
apt-get install -y autossh openssh-client
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

[Service]
Type=simple
User=wraplink
Group=wraplink
WorkingDirectory=/home/wraplink
Environment=AUTOSSH_GATETIME=0
ExecStart=/usr/bin/autossh -M 0 -N -i /home/wraplink/vpn/id.rsa -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=15 -D 127.0.0.1:10810 root@PROXY_SERVER_IP
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

If Docker containers or other **LAN hosts** must access this tunnel, replace `-D 127.0.0.1:10810` with `-D 192.168.10.114:10810` or `-D 0.0.0.0:10810` and explicitly firewall TCP 10810 to the required client IPs. The Docker container's `127.0.0.1` is **not** the host loopback. `-f` is intentionally omitted: systemd manages the foreground process.

```bash
systemctl daemon-reload
systemctl enable --now wraplink-socks5
systemctl status wraplink-socks5
journalctl -u wraplink-socks5 -n 50 --no-pager
ss -lntp | grep 10810
curl -fsS --proxy socks5h://127.0.0.1:10810 https://api.ipify.org
```

`systemctl active (running)` alone does not prove the SSH tunnel is established: autossh can remain active while SSH exits with status 255 (for example, due to missing `known_hosts`). Confirm the listening port and a successful proxied request. `ServerAliveInterval=30` and `ServerAliveCountMax=3` detect a dead session; autossh/systemd restart it.

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
BUILD_HTTP_PROXY=socks5h://192.168.10.114:10810
BUILD_HTTPS_PROXY=socks5h://192.168.10.114:10810
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
