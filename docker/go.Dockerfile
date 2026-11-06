FROM golang:1.26 AS builder
WORKDIR /src
ARG MAIN_PACKAGE=./cmd/api
COPY . .
# Embed the IANA time-zone database in the Go binary; no runtime apk is needed.
RUN go mod download && CGO_ENABLED=0 GOOS=linux go build -tags timetzdata -trimpath -ldflags="-s -w" -o /out/service "$MAIN_PACKAGE"

# The statically linked Go binary needs no shell or Alpine package manager.
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/service /service
USER 10001:10001
ENTRYPOINT ["/service"]
