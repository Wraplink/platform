FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive

# Docker builds may run behind an HTTP(S) proxy. Fail immediately if
# repository metadata cannot be downloaded instead of reporting missing packages.
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy

RUN set -eux; \
    apt-get update -o APT::Update::Error-Mode=any; \
    apt-get install -y --no-install-recommends \
      postfix \
      opendkim \
      opendkim-tools \
      openssl \
      ca-certificates \
      proxychains4; \
    rm -rf /var/lib/apt/lists/*

COPY docker/mail/entrypoint.sh /usr/local/bin/mail-entrypoint
RUN chmod +x /usr/local/bin/mail-entrypoint
EXPOSE 25
ENTRYPOINT ["/usr/local/bin/mail-entrypoint"]
