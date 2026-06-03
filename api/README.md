# API

The Kuvera **API** is a Go gRPC service with a REST gateway (via
`grpc-gateway`). It exposes evidence bundles and forensic captures to the
Console and to external integrations. It shares type definitions with the
operator via generated protobuf code.

> **Architecture rule:** the API reads CRDs; it never writes them. Only the
> operator writes `ForensicCapture` and `EvidenceBundle` resources.

## MVP scope

- List forensic captures
- Get a specific evidence bundle
- Download an artifact from a bundle

## Layout

```
api/
├── cmd/api/    # main.go — API server entrypoint
├── internal/   # server implementation, storage clients
├── proto/      # gRPC/protobuf definitions (buf.yaml, *.proto)
└── go.mod
```

## Building

```bash
cd api
go build ./...
go test ./...
```

## gRPC / protobuf

Proto definitions live in `proto/`. The Go client and server stubs are
generated via `buf generate` and committed to the repo as `*.pb.go` and
`*_grpc.pb.go` files. Never edit generated files by hand.

## References

- [grpc-ecosystem/grpc-gateway](https://github.com/grpc-ecosystem/grpc-gateway)
- [bufbuild/buf](https://github.com/bufbuild/buf)
