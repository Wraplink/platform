# Mail image build troubleshooting (Debian 13)

The mail image is built from `docker/mail/Dockerfile`. Build it with:

```sh
docker compose -f compose.yml -f compose.prod.yml build --no-cache --progress=plain mail
```

If the build reports `Unable to locate package postfix`, inspect the earlier `apt-get update` output. The Dockerfile uses `APT::Update::Error-Mode=any` to stop on failed index downloads instead of masking them.

## Check repository access inside Docker

```sh
docker run --rm debian:13-slim sh -ec 'cat /etc/apt/sources.list.d/debian.sources; apt-get update -o APT::Update::Error-Mode=any; apt-cache policy postfix opendkim openssl'
```

The container's network may differ from the host. Check DNS, blocked HTTP/HTTPS connections, and any `403` errors before changing package names or Debian suites.

## Build behind a proxy

`compose.yml` already passes `BUILD_HTTP_PROXY` and `BUILD_HTTPS_PROXY` as build arguments. Set these to reachable **HTTP proxy URLs** (for example `http://proxy.example:3128`), not `socks5://` URLs. Do not commit credentials to the repository.

```sh
BUILD_HTTP_PROXY=http://proxy.example:3128 \
BUILD_HTTPS_PROXY=http://proxy.example:3128 \
docker compose -f compose.yml -f compose.prod.yml build --no-cache --progress=plain mail
```

If only a SOCKS5 upstream is available, use an HTTP-to-SOCKS proxy bridge reachable from the Docker build environment, or configure an accessible Debian mirror. The mail container's runtime ProxyChains settings do not apply to Docker build steps.

Do not hide APT errors with `apt-get update || true`. The base image already contains the Debian Trixie APT source configuration; avoid replacing it without evidence of a mirror-specific failure.
