FROM golang:1.26 AS builder
WORKDIR /src
ARG MAIN_PACKAGE=./cmd/api
COPY . .
RUN go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/service "$MAIN_PACKAGE"

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/service /service
USER nonroot:nonroot
ENTRYPOINT ["/service"]
