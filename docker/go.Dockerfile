FROM golang:1.26 AS builder
WORKDIR /src
ARG MAIN_PACKAGE=./cmd/api
COPY . .
RUN go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/service "$MAIN_PACKAGE"

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app
COPY --from=builder /out/service /service
USER 10001:10001
ENTRYPOINT ["/service"]
