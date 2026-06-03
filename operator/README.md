# Operator

The Kuvera **operator** is a Kubernetes operator (built with Kubebuilder) that
manages `ForensicCapture` and `EvidenceBundle` Custom Resource Definitions. It
is the sole component that writes CRDs; everything else reads.

When a `ForensicCapture` is created — by a manual trigger, a Falco webhook, or
a SIEM integration — the operator orchestrates evidence collection: it pauses
the target container, exports the filesystem, dumps the sensor ring-buffer
history, scrapes pod manifests and Kubernetes audit logs, and seals the
resulting bundle with a cryptographic chain of custody.

> **Architecture rule:** the operator is the only component that writes CRDs.

## MVP scope

`ForensicCapture` CRD: filesystem export, sensor history dump, pod manifest
scrape, and bundle sealing (SHA-256 Merkle root + operator signing key).

## Layout

```
operator/
├── api/v1alpha1/   # CRD type definitions (ForensicCapture, EvidenceBundle)
├── controllers/    # reconciliation loops
├── cmd/operator/   # main.go — operator entrypoint
└── go.mod
```

## Building

```bash
cd operator
go build ./...
go test ./...
```

## References

- [kubernetes-sigs/kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)
- [sigstore/rekor](https://github.com/sigstore/rekor) — transparency log design
