# Sensor

The Kuvera **sensor** is an eBPF-based DaemonSet that runs on every Kubernetes
node. It acts as an always-on flight recorder: it continuously captures
syscalls, file operations, and network events, scoped per container via cgroup
ID, and ships them to a local userspace agent over a UNIX socket.

> **Architecture rule:** the sensor never makes outbound network calls. It
> writes to a UNIX socket or a local ring buffer; the userspace agent ships
> events. This is a deliberate defense-in-depth boundary — do not add network
> egress to the sensor.

## MVP scope

Capture `execve`, `openat`, `connect`, and `clone`. Per-container scoping via
cgroup ID. Capture only — no detection logic (detection is upstream: Falco,
Tetragon, the user's SIEM).

## Layout

```
sensor/
├── bpf/            # eBPF C programs (CO-RE / BTF)
├── cmd/sensor/     # main.go — DaemonSet entrypoint
├── internal/       # userspace loader, ring-buffer reader, event shipping
└── go.mod
```

## Building

```bash
cd sensor
go build ./...
go test ./...
```

## eBPF programs

eBPF programs live in `bpf/` and are written in restricted C using CO-RE
(Compile Once, Run Everywhere) with BTF type information. They are loaded into
the kernel by the userspace agent via `cilium/ebpf`. Programs must be
verifier-friendly: bounded loops, no recursion, small stack frames.

## References

- [cilium/ebpf](https://github.com/cilium/ebpf) — userspace eBPF library
- [aquasecurity/tracee](https://github.com/aquasecurity/tracee) — reference eBPF DaemonSet
- [cilium/tetragon](https://github.com/cilium/tetragon) — reference eBPF observability
