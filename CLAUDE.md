# CLAUDE.md

This file gives Claude Code the context it needs to be useful in this repository. Read it fully before doing anything substantive.

## Project: Kuvera

Kuvera is a Kubernetes-native digital forensics and incident response (DFIR) platform. It captures, preserves, and analyzes evidence from compromised containers with cryptographic chain of custody.

The full project spec is in `PROJECT.md`. Read it if you need product context. The user-facing summary is in `README.md`.

## What you're helping build

A self-managed, on-cluster forensics platform with these components:

1. **Sensor** — eBPF DaemonSet, written in Go using `cilium/ebpf`. Continuous capture of syscalls, file ops, and network events. Per-container scoping.
2. **Operator** — Kubernetes operator written in Go using Kubebuilder. Manages `ForensicCapture` and `EvidenceBundle` CRDs. Orchestrates evidence collection.
3. **API** — Go gRPC + REST gateway, shared types with the operator.
4. **Analyzer workers** — Python services for memory, filesystem, and IOC analysis. Use Volatility3, YARA, and custom logic.
5. **Console** — TypeScript + React + Vite SPA. shadcn/ui components, TanStack Query, TanStack Router. Talks to the API.

## Repository layout (target)

```
.
├── sensor/                 # Go, eBPF sensor (DaemonSet)
│   ├── bpf/                # eBPF C programs
│   ├── cmd/sensor/         # main.go
│   ├── internal/
│   └── go.mod
├── operator/               # Go, Kubernetes operator
│   ├── api/v1alpha1/       # CRD types
│   ├── controllers/        # reconciliation loops
│   ├── cmd/operator/
│   └── go.mod
├── api/                    # Go, API gateway
│   ├── cmd/api/
│   ├── internal/
│   ├── proto/              # gRPC definitions (shared with console)
│   └── go.mod
├── analyzer/               # Python, analysis workers
│   ├── kuvera_analyzer/
│   ├── pyproject.toml
│   └── tests/
├── console/                # TypeScript + React frontend
│   ├── src/
│   ├── package.json
│   └── vite.config.ts
├── deploy/                 # Helm charts, Kubernetes manifests
│   ├── helm/
│   └── manifests/
├── docs/                   # Markdown docs (architecture, ADRs, etc.)
├── PROJECT.md              # Full project spec
├── README.md               # User-facing
├── CLAUDE.md               # This file
└── Makefile
```

## Coding conventions

### Go (sensor, operator, api)

- Go 1.26+
- `gofmt`, `goimports`, `golangci-lint` (config in `.golangci.yaml`)
- Errors: wrap with `fmt.Errorf("doing X: %w", err)`. No `pkg/errors`. No bare `err.Error()`.
- Logging: `log/slog` only. Structured. Always include relevant K8s identifiers (namespace, pod, node).
- Context: every blocking function takes `ctx context.Context` as the first arg. Honor cancellation.
- No global state except in `main`.
- Tests: standard `testing`, table-driven where it makes sense, `t.Parallel()` by default. Use `testify/require` for assertions.
- Generated code (zz_generated.*, *.pb.go) is committed but never hand-edited.

### Python (analyzer)

- Python 3.12+
- `uv` for dependency management. `pyproject.toml` is canonical.
- `ruff` for lint+format, `mypy --strict` for typing.
- Type hints are mandatory. No `Any` without justification.
- Tests: `pytest`.
- Logging: `structlog`.

### TypeScript (console)

- TypeScript 6.0+, strict mode on, `noUncheckedIndexedAccess` enabled.
- React 19+, functional components, hooks. No class components.
- State: TanStack Query for server state. Zustand for client state if needed. No Redux.
- Routing: TanStack Router.
- Styling: Tailwind + shadcn/ui. No CSS modules. No styled-components.
- Forms: react-hook-form + zod.
- Tests: vitest + testing-library.
- Generated API client: from the gRPC proto via `buf generate`. Hand-written API clients are forbidden.

### eBPF

- C for the BPF programs themselves. CO-RE (Compile Once, Run Everywhere) using BTF.
- Verifier-friendly: small loops, bounded helpers, no recursion.
- Userspace loading via `cilium/ebpf`. No `libbpf-go` wrappers.
- Every BPF program has a corresponding userspace test that loads it into a kernel and checks events.

## Architecture rules

1. **Sensor never makes outbound network calls.** It writes to a UNIX socket or local ring buffer. The userspace agent ships events. This is for security review reasons.
2. **Operator is the only component that writes CRDs.** Everything else reads.
3. **Evidence is immutable.** Once a bundle is sealed (hash computed, transparency log updated), it is append-only. Re-analysis produces *new* artifacts that reference the original bundle's hash.
4. **Chain of custody is non-negotiable.** Every artifact in a bundle has a SHA-256. The bundle has a Merkle root. The root is signed by the operator's key and appended to the transparency log. Don't break this.
5. **No PII in logs.** Container contents are evidence, not logs. Log only K8s identifiers, hashes, and timestamps.
6. **Defense in depth on the operator.** The operator has cluster-wide read on pods and write on its CRDs. Nothing else. Strict RBAC. No `cluster-admin`.

## Custom Resource Definitions

```yaml
apiVersion: forensics.kuvera.io/v1alpha1
kind: ForensicCapture
metadata:
  name: incident-2026-05-18-001
spec:
  target:
    namespace: production
    pod: api-server-78d9c5b8f6-x4q7m
    containers: ["app"]   # optional, all if omitted
  evidence:
    - filesystem
    - sensorHistory: 1h
    - kubernetesAudit
    - podManifest
    - memory          # v2
    - cloudVolume     # v3
  preservation:
    pauseContainer: true
    timeout: 5m
status:
  phase: Pending | Capturing | Analyzing | Sealed | Failed
  bundleRef: EvidenceBundle/abc123...
  startedAt: ...
  completedAt: ...
  conditions: [...]
```

```yaml
apiVersion: forensics.kuvera.io/v1alpha1
kind: EvidenceBundle
metadata:
  name: bundle-abc123
spec:
  captureRef: ForensicCapture/incident-2026-05-18-001
  merkleRoot: sha256:...
  signature: ...
  transparencyLogIndex: 12345
  artifacts:
    - kind: Filesystem
      sha256: ...
      sizeBytes: ...
      objectStoreKey: ...
    - kind: SensorEvents
      sha256: ...
      ...
```

## Development workflow

- `make dev-cluster` — boots a `kind` cluster with the right kernel modules (BTF, eBPF).
- `make build` — builds all components.
- `make deploy-dev` — installs the Helm chart to the dev cluster.
- `make test` — runs all unit tests.
- `make e2e` — runs end-to-end tests against the dev cluster (slow, CI only).
- `make lint` — runs all linters.

Pre-commit: lint must pass. Tests must pass. No commits to main directly — feature branches and PRs only.

## What to do when asked to write code

1. Read `PROJECT.md` if you don't have product context.
2. Check this file's conventions before writing anything.
3. For Go code, default to the project's existing patterns. If you're starting a new package, mirror the structure of an existing similar one.
4. For new features, prefer the smallest possible vertical slice. Make it work end-to-end before making it good.
5. For eBPF: be skeptical of complexity. The verifier is unforgiving. Start with the simplest possible program that demonstrates the capability, then expand.
6. For the console: every API call goes through the generated client. Every form goes through react-hook-form + zod. No exceptions.
7. Always include tests. Untested code is rejected.
8. If a change touches the chain-of-custody flow (capture, sealing, hashing, signing, transparency log), flag it explicitly in the PR description. Those changes need extra scrutiny.

## What to push back on

- Requests to add a feature to the *sensor* that requires network egress from the sensor. (Defense-in-depth rule.)
- Requests to weaken chain of custody for performance reasons. (We can be slower. We cannot be wrong.)
- Requests to add detection logic to the operator or sensor. Kuvera is a forensics tool. Detection is upstream — Falco, Tetragon, the user's SIEM. Adding detection scope-creeps the project.
- Requests to add Kafka, Cassandra, or other heavyweight infra. We are self-managed and the operational footprint must stay small.
- Requests to support non-Kubernetes environments in v1. We win by being the best at one thing.

## What's MVP vs later

MVP (current focus):
- Sensor: capture `execve`, `openat`, `connect`, `clone`. Per-container scoping via cgroup ID.
- Operator: `ForensicCapture` CRD, filesystem export, sensor history dump, manifest scrape, bundle sealing.
- API: list captures, get bundle, download artifact.
- Console: list view, capture detail view, simple timeline (table, not visualization).
- Storage: SeaweedFS + PostgreSQL. No OpenSearch yet.
- Chain of custody: SHA-256 + local Merkle log + operator signing key.

Post-MVP:
- Memory dumping (CRIU)
- Volatility3 integration
- Cloud volume snapshots
- Visualization (timeline chart, blast radius graph)
- OpenSearch
- Multi-cluster
- RBAC, SSO, compliance reports

## Useful prior art to reference

Look at these projects' source when stuck:

- `aquasecurity/tracee` — eBPF event capture in Go, runs as a DaemonSet
- `cilium/tetragon` — eBPF security observability, also Go
- `falcosecurity/falco` — runtime detection, mature
- `Velocidex/velociraptor` — endpoint DFIR, the closest non-K8s analog to Kuvera
- `kubernetes-sigs/kubebuilder` — operator scaffolding
- `sigstore/rekor` — transparency log design we're loosely emulating

Do NOT copy code from these projects without checking their licenses (most are Apache 2.0, but verify per file).

## Communication style for this project

- Be direct. The user is an experienced engineer.
- Skip pleasantries in code suggestions.
- When suggesting a design, give the recommendation first and the alternatives after.
- When refactoring, explain the *why* once, then just do the work.
- If you're unsure about a Kubernetes API behavior, eBPF verifier quirk, or forensics convention, *say so* and look it up — don't guess. This domain has real legal implications.
