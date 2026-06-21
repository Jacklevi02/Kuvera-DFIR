# Kuvera

**Cloud-native digital forensics and incident response (DFIR) platform for Kubernetes.**

## Overview

Kuvera is a self-managed, Kubernetes-native forensics platform that automatically captures, preserves, and analyzes evidence from compromised containers and nodes before they disappear. It provides incident responders with a court-admissible chain of custody and a unified timeline of attacker activity, in minutes instead of hours.

## The problem

When something bad happens in a Kubernetes cluster, the evidence is already vanishing. Containers live for seconds. Pods get rescheduled. Nodes autoscale away. Traditional forensics assumes a static disk that can be imaged — that model breaks completely in cloud-native environments.

Today, when an incident is detected, responders must:

1. SSH into nodes (if possible)
2. Manually run `kubectl describe`, `docker diff`, `crictl inspect`
3. Manually snapshot EBS/PD/Managed Disk volumes
4. Manually pull logs from CloudTrail, Kubernetes audit logs, the container runtime
5. Manually correlate everything into a timeline
6. Preserve chain of custody well enough that findings stand up in court or in a board-level post-incident review

This takes hours. Attackers take minutes. The evidence is gone.

Existing point solutions do not close the gap. Velociraptor is endpoint-focused and not Kubernetes-native. Cado Security is a closed commercial product. Tracee and Tetragon are excellent eBPF _detection_ tools but do not perform post-incident _forensic capture_ with chain of custody. Kuvera fills this gap as a Kubernetes-native, self-managed platform that internal SOCs and MDR providers can deploy and operate themselves.

## The product

Kuvera consists of four components:

**1. The Sensor (DaemonSet)** — a lightweight eBPF agent that runs on every node, continuously recording process execution, file access, network connections, and container lifecycle events into a high-performance ring buffer. The sensor is passive in normal operation; it observes rather than alerting or blocking. It functions as an always-on flight recorder.

**2. The Collector (Operator)** — a Kubernetes operator that watches for forensic-trigger events: manual triggers via Custom Resource, integration with detection tools such as Falco, or webhooks from a SIEM. When triggered, it orchestrates evidence collection: snapshots the cloud volume, dumps container memory using CRIU, exports the container filesystem, pulls the writable overlay layer, captures the kernel ring buffer history from the sensor, scrapes pod manifests and Kubernetes audit logs, and packages everything with cryptographic hashes into a chain-of-custody bundle.

**3. The Analyzer (Workers)** — a pool of analysis workers that ingest evidence bundles and produce a normalized, queryable timeline. Memory is analyzed with Volatility3 plugins, filesystems are diffed against the original image, IOCs are matched against threat-intel feeds, and processes are reconstructed across the kernel, container, and pod boundary. The output is a single timeline that describes attacker activity in sequence.

**4. The Console (Web UI + API)** — an investigation UI showing the timeline, the evidence bundle, the affected resources, the blast radius across the cluster, and the chain-of-custody log. Investigators can pivot, tag, annotate, and export reports.

## Why now

- Kubernetes is dominant in enterprise. Every CISO needs an answer for "what happens when a pod is compromised?"
- eBPF has matured to the point where always-on, low-overhead capture is viable in production.
- The cloud forensics market is real but immature. Cado, Mitiga, and others have raised funding. The space is open for an open-core competitor.
- Regulators — including EU DORA and US SEC cyber disclosure rules — are increasing pressure for proper incident evidence.

## Differentiation

- Plays directly to modern infrastructure: agent-based architecture, Kubernetes orchestration, containers, multi-language services.
- Built on DFIR fundamentals: chain of custody, evidence preservation, timeline analysis, memory forensics.
- Differentiated positioning: the only Kubernetes-native, self-managed, open-core forensics platform.
- Clear commercial path: open source the sensor and operator; sell the enterprise console, multi-cluster federation, compliance reporting (DORA, SEC, HIPAA), and managed cloud version.
- Solo-buildable as an MVP, expandable to a team later.

## Technology stack

The stack is fixed. Each choice is deliberate. Contributors should not introduce new languages or runtimes without explicit project-level approval.

**Sensor (eBPF agent)**

- Language: Go with `cilium/ebpf` for userspace loading; eBPF programs themselves are written in restricted C and compiled to BPF bytecode.
- Rationale: `cilium/ebpf` is the standard used by Cilium, Tetragon, and the majority of the cloud-native eBPF ecosystem, giving Kuvera a large community and a clear path for contributors.
- Reference projects (study, do not copy without license review): Tracee, Tetragon, Falco.

**Operator / Collector**

- Language: Go, using Kubebuilder.
- Rationale: Kubebuilder is the standard for Kubernetes operators. Custom Resource Definitions (`ForensicCapture`, `EvidenceBundle`) provide a clean, declarative API.

**Analyzer workers**

- Language: Python 3.12+.
- Rationale: Volatility3 is Python. YARA has its best bindings in Python. The forensics ecosystem (plaso, dfvfs, libforensic-artifacts) is overwhelmingly Python.
- Orchestration: a job queue backed by NATS JetStream, with workers running as Kubernetes Jobs.

**API gateway**

- Language: Go (gRPC with a REST gateway via `grpc-gateway`).
- Rationale: type safety, performance, and shared types with the operator.

**Console (web UI)**

- Language: TypeScript with React 19+ and Vite 8.
- UI: shadcn/ui components, TanStack Query for server state, TanStack Router for routing.
- Forms: react-hook-form + zod.
- Visualization: a timeline component built on visx or vis-timeline; a graph view for blast radius using Cytoscape.js or react-flow.

**Storage**

- Evidence bundles (large, immutable binary blobs): S3-compatible object storage. SeaweedFS for self-hosted deployments (MinIO was archived in February 2026; SeaweedFS is the S3-compatible replacement); S3, GCS, or Azure Blob for cloud. Bundles are content-addressed by SHA-256.
- Metadata, timelines, and queries: PostgreSQL with the `timescaledb` extension for time-series timeline data.
- Search across evidence: OpenSearch (post-MVP). The MVP omits search.
- Sensor event stream: NATS JetStream. Lightweight, Kubernetes-friendly, no Kafka operational burden.

**Cryptographic chain of custody**

- Every evidence artifact receives a SHA-256 hash at the moment of capture.
- Hashes are appended to a Merkle log, signed with the operator's signing key.
- The transparency log design is loosely modelled on Sigstore Rekor.
- The system provides "this evidence existed in this state at this time" guarantees — the legal cornerstone of digital forensics.

**Deployment**

- Helm chart for the entire platform.
- Multi-tenant by namespace; RBAC-aware.
- Runs on any conformant Kubernetes distribution (EKS, GKE, AKS, k3s, OpenShift).

## MVP scope (first 3 months)

The MVP proves the core thesis: forensic evidence can be captured from a compromised pod in under 60 seconds with verifiable chain of custody.

**MVP includes:**

1. eBPF sensor capturing exec/open/connect syscalls into a ring buffer (capture only; no analysis).
2. Operator with a `ForensicCapture` CRD that, when created against a pod, triggers:
   - Pause the container via the runtime API
   - Dump the container filesystem to a tar archive
   - Export the last 60 minutes of sensor events for that pod
   - Pull the pod manifest, events, and logs
   - Hash everything, build a bundle, and upload it to S3-compatible storage
   - Append the bundle hash to a local transparency log
3. A simple analyzer that ingests a bundle and produces a JSON timeline.
4. A minimal web UI: list captures, view timeline, download bundle.

**Explicitly NOT in MVP:**

- Memory dumping (CRIU is complex; deferred to v2)
- Cloud volume snapshots (cloud-specific; deferred to v3)
- Volatility integration (deferred to v2)
- Multi-cluster federation (deferred to v3)
- Detection signatures — Kuvera is a forensics tool, not a detector. This is a deliberate scope boundary, not a missing feature.

## Go-to-market strategy

**Phase 1 (months 0–6): open source core**

- Apache 2.0 license the sensor, operator, and basic analyzer.
- Content marketing: blog about Kubernetes forensics, present at KubeCon, contribute to Falco and Tracee communities.
- Targets: 1,000 GitHub stars, an active community channel, 5 production users.

**Phase 2 (months 6–12): commercial console**

- Enterprise console: SSO/SAML, multi-cluster, compliance reports (DORA, SOC2, HIPAA), audit log, advanced timeline analytics.
- Pricing: per-cluster or per-node, with self-hosted enterprise and managed cloud tiers.
- Target customers: MDR providers, IR consultancies (Mandiant, Crowdstrike Services, regional firms), regulated enterprises (banks, healthcare, fintech).

**Phase 3 (year 2+): integrations and ecosystem**

- SIEM integrations (Splunk, Elastic, Chronicle), SOAR platforms, ticketing.
- Cloud-native expansion: serverless forensics (Lambda, Cloud Run), service-mesh forensics.
- Professional services and training. Forensics is a services-heavy field.

## Target market

**Primary buyers (order of reachability):**

1. **Incident response consultancies and MDR providers.** Firms running IR engagements where clients have Kubernetes and responders lack adequate tooling. High pain, existing budget, vocal community influence.
2. **Internal SOCs and security engineering teams at cloud-native enterprises.** Banks, fintech, healthcare, SaaS at scale. Larger long-term market, slower sales cycle.
3. **Regulated industries facing new compliance pressure.** EU DORA, SEC cyber disclosure rules, HIPAA, PCI-DSS, SOC 2 evidence-preservation requirements.

**Buyer persona:** senior security engineer, IR lead, or DFIR consultant. Technical, skeptical, allergic to marketing. Lives on GitHub, reads Hacker News, attends BSides and KubeCon, trusts open source.

## Competitive landscape

| Tool                      | What it does                 | Where Kuvera differs                                                     |
| ------------------------- | ---------------------------- | ------------------------------------------------------------------------ |
| Velociraptor              | Open-source endpoint DFIR    | Endpoint-focused, not K8s-native, no eBPF                                |
| Cado Security             | Cloud forensics SaaS         | Closed source, expensive, AWS-first                                      |
| Tracee / Tetragon / Falco | Runtime detection via eBPF   | Detection, not forensics; no chain of custody; no investigation workflow |
| Sysdig / Wiz              | Cloud security platforms     | Detection-and-posture, light on deep forensics; very expensive           |
| GRR                       | Endpoint forensics (Google)  | Not maintained; not cloud-native                                         |
| Mitiga                    | Cloud IR services + platform | Services-led, expensive, closed                                          |

The gap is real: no project owns "open-core, Kubernetes-native, chain-of-custody-correct forensics."

## Licensing

Apache License 2.0 for the open core: sensor, operator, basic analyzer, basic console.

Future commercial enterprise features — multi-cluster federation, SSO/SAML, compliance reporting, managed cloud — will live in a separate repository under a source-available license (BSL or Elastic License v2). The architectural boundary between open and commercial code is enforced at the repository level, not via feature flags.

DCO sign-off is required on every commit. No CLA.

## Risks and constraints

- **eBPF learning curve.** Manageable. Tracee's source code is the recommended starting reference.
- **Sensor overhead.** The primary reason a customer would remove Kuvera. Target: under 2% CPU on a busy node.
- **Cloud snapshot APIs.** Complex and provider-specific. Deferred to v3. MVP uses container filesystem export only.
- **CRIU for memory dumping.** Fragile. Deferred to v2.
- **Liability.** Chain of custody is a legal claim. Documentation must be precise. Claims of court admissibility require legal review before any public statement.
- **Open-core balance.** The open source version must remain genuinely useful. Gutting it to drive commercial sales would destroy adoption and community trust.

## Prior art

Reference projects (study, do not copy without license review):

- `aquasecurity/tracee` — eBPF event capture in Go, DaemonSet pattern
- `cilium/tetragon` — eBPF security observability
- `falcosecurity/falco` — mature runtime detection
- `Velocidex/velociraptor` — closest non-Kubernetes analog
- `kubernetes-sigs/kubebuilder` — operator scaffolding
- `sigstore/rekor` — transparency log design

Most are Apache 2.0. Verify per file before any code reuse.

## Etymology

Kuvera is the Hindu deity of wealth and the guardian of the north — keeper of treasure. In digital forensics, evidence is treasure. Kuvera guards it.
