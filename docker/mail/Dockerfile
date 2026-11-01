FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends postfix opendkim opendkim-tools openssl ca-certificates proxychains4 && rm -rf /var/lib/apt/lists/*
COPY docker/mail/entrypoint.sh /usr/local/bin/mail-entrypoint
RUN chmod +x /usr/local/bin/mail-entrypoint
EXPOSE 25
ENTRYPOINT ["/usr/local/bin/mail-entrypoint"]
