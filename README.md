# Kuvera

> Kubernetes-native digital forensics and incident response. Capture, preserve, and analyze evidence from compromised containers before they disappear.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Status: Pre-alpha](https://img.shields.io/badge/Status-Pre--alpha-orange.svg)](#)

## What Kuvera does

When a container in your Kubernetes cluster is compromised, you have seconds — not hours — before the evidence vanishes. Containers die. Pods reschedule. Nodes autoscale away.

Kuvera is an always-on forensic flight recorder for Kubernetes. It runs an eBPF sensor on every node that continuously captures process, file, and network events. When you (or an automated detection) trigger a forensic capture against a pod, Kuvera freezes the container, snapshots its state, packages every piece of evidence with a cryptographic chain of custody, and gives you a unified timeline of exactly what happened.

It is built for incident responders, SOC analysts, and DFIR consultants who need court-admissible evidence from cloud-native environments.

## Core capabilities

- **Always-on eBPF sensor** — continuous, low-overhead capture of syscalls, file access, and network events, scoped to containers
- **One-command capture** — `kubectl create -f capture.yaml` to trigger evidence collection on a target pod
- **Chain of custody** — every artifact SHA-256 hashed, signed, and recorded in an append-only transparency log
- **Unified timeline** — kernel events, container events, Kubernetes audit logs, and cloud audit logs merged into a single investigator view
- **Self-managed** — runs entirely inside your cluster; your evidence never leaves your environment
- **Pluggable analyzers** — extend with custom YARA rules, Volatility plugins, or IOC feeds

## Status

Pre-alpha. Active early development. Not production-ready.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
│                                                                 │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐               │
│  │   Node 1   │   │   Node 2   │   │   Node N   │               │
│  │ ┌────────┐ │   │ ┌────────┐ │   │ ┌────────┐ │               │
│  │ │ Sensor │ │   │ │ Sensor │ │   │ │ Sensor │ │  DaemonSet    │
│  │ │ (eBPF) │ │   │ │ (eBPF) │ │   │ │ (eBPF) │ │  (Go)         │
│  │ └────┬───┘ │   │ └────┬───┘ │   │ └────┬───┘ │               │
│  └──────┼─────┘   └──────┼─────┘   └──────┼─────┘               │
│         │                │                │                     │
│         └────────────────┴────────────────┘                     │
│                          │                                      │
│                  NATS JetStream                                 │
│                          │                                      │
│         ┌────────────────┼────────────────┐                     │
│         │                │                │                     │
│    ┌────▼─────┐    ┌─────▼──────┐    ┌────▼──────┐              │
│    │ Operator │    │  Analyzer  │    │  Console  │              │
│    │   (Go)   │    │  Workers   │    │ API (Go)  │              │
│    │          │    │  (Python)  │    │           │              │
│    └────┬─────┘    └─────┬──────┘    └────┬──────┘              │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          │                                      │
│              ┌───────────┼───────────┐                          │
│              │           │           │                          │
│         ┌────▼────┐  ┌────▼───┐  ┌────▼─────┐                   │
│         │SeaweedFS│  │Postgres│  │OpenSearch│                   │
│         │ (blobs) │  │(meta)  │  │(timeline)│                   │
│         └─────────┘  └────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                      ┌──────────────┐
                      │ Web Console  │
                      │ (TypeScript) │
                      └──────────────┘
```

## Tech stack

- **Sensor:** Go + `cilium/ebpf`
- **Operator:** Go + Kubebuilder
- **API gateway:** Go (gRPC + REST)
- **Analyzer workers:** Python (Volatility3, YARA, custom)
- **Console:** TypeScript, React, Vite, shadcn/ui, TanStack Query
- **Storage:** SeaweedFS (blobs), PostgreSQL + TimescaleDB (metadata), OpenSearch (search)
- **Messaging:** NATS JetStream
- **Deployment:** Helm

## Quickstart (target experience)

```bash
# Install Kuvera into your cluster
helm install kuvera oci://ghcr.io/kuvera/charts/kuvera \
  --namespace kuvera-system --create-namespace

# Verify the sensor DaemonSet is running on every node
kubectl get ds -n kuvera-system

# Trigger a forensic capture on a suspicious pod
cat <<EOF | kubectl apply -f -
apiVersion: forensics.kuvera.io/v1alpha1
kind: ForensicCapture
metadata:
  name: incident-2026-05-18-001
spec:
  target:
    namespace: production
    pod: api-server-78d9c5b8f6-x4q7m
  evidence:
    - filesystem
    - sensorHistory: 1h
    - kubernetesAudit
    - podManifest
EOF

# Watch the capture progress
kubectl get forensiccapture -w

# Open the console to investigate
kubectl port-forward -n kuvera-system svc/kuvera-console 8080:80
open http://localhost:8080
```

## Development

### Documentation

| Document                                                   | What it covers                                                                     |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [PROJECT.md](./PROJECT.md)                                 | Full product spec: capabilities, architecture, CRDs, MVP scope, post-MVP roadmap   |
| [CLAUDE.md](./CLAUDE.md)                                   | Coding conventions, architecture rules, component layout, and what to push back on |
| [docs/PROJECT-MANAGEMENT.md](./docs/PROJECT-MANAGEMENT.md) | Project board schema, label taxonomy, workflow conventions, and branch naming      |
| [CONTRIBUTING.md](./CONTRIBUTING.md)                       | DCO sign-off requirement, pre-alpha status, branch naming                          |

### Prerequisites

Go 1.26+, Node 24+, Python 3.12+, Docker with `kind`.

### Common commands

```bash
make dev-cluster   # Boot a local kind cluster with eBPF support
make build         # Build all components
make deploy-dev    # Deploy to the dev cluster
make test          # Run all tests
make lint          # Run all linters (Go, Python, TypeScript)
```

### Component structure

```
sensor/     Go + eBPF — syscall, file, and network event capture (DaemonSet)
operator/   Go + Kubebuilder — ForensicCapture and EvidenceBundle CRDs
api/        Go — gRPC + REST API gateway
analyzer/   Python — evidence analysis workers (Volatility3, YARA)
console/    TypeScript + React + Vite — investigator SPA
deploy/     Helm charts and Kubernetes manifests
docs/       Architecture docs, ADRs, roadmap
```

## Licensing

Apache 2.0 for the core (sensor, operator, basic analyzer, basic console).

Future commercial enterprise features (multi-cluster, SSO, compliance reporting, managed cloud) will live in a separate repository under a source-available license.

## Why "Kuvera"?

Kuvera is the Hindu deity of wealth, riches, and the guardian of the north — keeper of treasure. In digital forensics, evidence _is_ treasure. We guard it.

## Contributing

Not yet open for external contributions — pre-alpha and the architecture is still settling. Star the repo to follow along.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the DCO sign-off requirement and branch naming convention that apply to all commits.

## Inspiration and prior art

- Velociraptor (endpoint DFIR)
- Tracee, Tetragon, Falco (eBPF runtime security)
- Cado Security, Mitiga (commercial cloud forensics)
- Volatility (memory forensics)
- Sigstore Rekor (transparency log design)

We aim to be the open-core, Kubernetes-native, forensics-first synthesis of these ideas.
