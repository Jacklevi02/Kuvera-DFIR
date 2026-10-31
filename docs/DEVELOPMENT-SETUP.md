# Development setup

Getting from a clean machine to a running Kuvera dev cluster.

For *which* tools the project uses and where each version is pinned, see
[TOOLCHAIN.md](./TOOLCHAIN.md). This document is the walkthrough.

## What mise provides, what your system provides

Nearly every tool Kuvera needs is installed by [mise](https://mise.jdx.dev) from
`mise.toml`. The exceptions are uv and Python, which are managed by uv by
choice, and a short list of system daemons and kernel features that are not
versioned binaries at all.

| mise installs (from `mise.toml`) | uv installs / manages              | Your system must provide                   |
| -------------------------------- | ---------------------------------- | ------------------------------------------ |
| Go, Node.js, pnpm                | Python (from `analyzer/.python-version`) | Docker                                 |
| golangci-lint, ShellCheck        | ruff, mypy, pytest, structlog      | `git`, `make`, `bash`                      |
| kind, kubectl, Helm              |                                    | A Linux kernel with BTF (for CO-RE eBPF)   |
| buf, pre-commit                  |                                    | `sudo` access, to install the runtime once |

You never install Go, Node, or kubectl by hand, and you never pin their versions
anywhere but `mise.toml`. Python and uv are deliberately **not** in `mise.toml`
— see [step 2](#2-install-uv). The container runtime is not a mise tool either —
`mise registry docker` returns `tool not found in registry`, because a runtime
is a privileged daemon wired into the kernel, not a per-project binary.

## 1. Install mise

```bash
curl https://mise.run | sh
```

Then activate it in your shell, so mise's shims land on `PATH`:

```bash
# bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# zsh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc

# fish
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish
```

Open a new shell and confirm:

```bash
mise --version
```

> **Do not skip activation.** Without it the shims are not on `PATH`, and every
> command in this document fails with `command not found` even though the tools
> are installed. This is the single most common setup problem.

Distro packages (`dnf`, `apt`, `brew`, `nix`) are also available — see
[installing mise](https://mise.jdx.dev/installing-mise.html).

## 2. Install uv

uv is installed standalone, not through mise, and manages the Python interpreter
itself — you do not install Python separately.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

The project's supported uv range is `[tool.uv] required-version` in
`analyzer/pyproject.toml`; uv refuses to run against the project if your version
is outside it (`uv self update` fixes that). The interpreter version is in
`analyzer/.python-version`, and `uv sync` downloads it automatically in step 5.

Other install methods (`brew install uv`, `pipx`, distro packages) are listed in
[uv's installation docs](https://docs.astral.sh/uv/getting-started/installation/).

## 3. Install Docker

`make dev-cluster` runs [kind](https://kind.sigs.k8s.io), which runs each
Kubernetes node as a container. Docker is the only supported runtime.

**Fedora**

```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

**Ubuntu / Debian**

```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**macOS** — install [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/),
or [Colima](https://github.com/abiosoft/colima) (`brew install colima docker` then
`colima start`). See the macOS caveat in [eBPF host requirements](#6-ebpf-host-requirements).

**Post-install (Linux)** — run Docker without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

> The `docker` group grants root-equivalent privileges to its members. That is a
> deliberate trade-off documented by Docker itself; on a shared or production
> machine, prefer `sudo docker`.

Use Docker's normal mode, not rootless mode. Rootless nodes run in a user
namespace, and the kernel requires `CAP_BPF` in the initial user namespace, so
eBPF programs cannot load there even though the node looks fully privileged.

## 4. Install the toolchain

From the repo root:

```bash
mise install
```

That reads `mise.toml` and installs Go, Node.js, pnpm, golangci-lint, ShellCheck,
kind, kubectl, Helm, buf, and pre-commit at the pinned versions. Confirm:

```bash
mise ls
```

## 5. Install per-component dependencies

Toolchain versions come from `mise.toml`; library versions come from each
component's own manifest.

```bash
cd analyzer && uv sync               # pinned Python + ruff, mypy, pytest, structlog
cd console  && pnpm install          # TypeScript, ESLint, Prettier, Vitest
```

**pnpm only** for the console — no npm, no yarn. **uv only** for the analyzer —
never `pip install`. Both lockfiles are committed and CI installs from them.

Confirm the whole thing works:

```bash
make lint
make test
```

Optionally, install the git hooks. They catch lint errors at commit time and
refuse direct commits to `main` or `dev`:

```bash
pre-commit install
```

See [TESTING.md](./TESTING.md#pre-commit-hooks) for what they check.

## 6. eBPF host requirements

Kuvera's sensor is a CO-RE eBPF DaemonSet. That needs BTF type information and a
cgroup v2 host:

```bash
stat -fc %T /sys/fs/cgroup      # expect: cgroup2fs
ls -l /sys/kernel/btf/vmlinux   # must exist — this is what makes CO-RE work
```

`deploy/dev/kind-config.yaml` bind-mounts bpffs (`/sys/fs/bpf`) and debugfs
(`/sys/kernel/debug`) into every node, and `make dev-cluster` applies it
automatically.

> **macOS caveat.** On macOS, kind runs inside a Linux VM (Docker Desktop's
> LinuxKit VM or Colima's). Whether that VM's kernel exposes
> BTF at `/sys/kernel/btf/vmlinux` depends on the VM image and is not something
> this project has verified. `scripts/dev-cluster-verify.sh` is the check — run
> it before assuming sensor work will function on macOS. A Linux host or VM is
> the safe choice for sensor development.

## 7. First dev cluster

```bash
make dev-cluster              # boot a kind cluster (idempotent)
scripts/dev-cluster-verify.sh # nodes Ready + BTF present on a node
make dev-cluster-down         # tear it down
```

`make dev-cluster` is idempotent — re-running it against an existing cluster just
re-checks node readiness. Useful overrides:

```bash
make dev-cluster KIND_CLUSTER_NAME=kuvera-test
make dev-cluster KIND_NODE_IMAGE=kindest/node:v1.36.1
make dev-cluster KIND_RECREATE=1            # delete and rebuild
```

`scripts/dev-cluster-verify.sh` confirms nodes are Ready and that BTF is present
*on a node*, which CO-RE needs. It does not load an eBPF program, so a pass does
not prove the sensor can load: rootless Docker would pass it and still fail (see
[step 3](#3-install-docker)). CI's `Live cluster (kind + eBPF)` job covers that
gap by loading a program in a node with `scripts/ebpf-probe.go`, and
[TESTING.md](./TESTING.md#what-only-runs-by-hand) shows how to run the same load
by hand.

## Troubleshooting

| Symptom                                                        | Cause                                                      | Fix                                                                     |
| -------------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| `mise: command not found`                                       | mise not on `PATH`                                          | Re-run the install one-liner; open a new shell                          |
| `go`/`pnpm`/`kubectl: command not found` after `mise install`   | mise not activated in your shell                            | Add the `mise activate` line to your rc file (step 1), open a new shell |
| `uv: command not found`                                         | uv is not installed by mise                                 | Install it standalone (step 2)                                          |
| `mise install` fails on `pypi:pre-commit` and mentions pipx     | mise installs pre-commit through uv, and uv is missing      | Install uv (step 2), then re-run `mise install`                         |
| `pre-commit` reports a missing interpreter                      | The uv-managed Python its environment uses was removed      | `mise install --force pypi:pre-commit`                                  |
| `Required uv version ... does not match the running version`    | Your uv is outside `[tool.uv] required-version`             | `uv self update`                                                        |
| `VIRTUAL_ENV=... does not match the project environment path`   | Another virtualenv is activated in your shell               | `deactivate`; uv always uses `analyzer/.venv`                           |
| `pnpm install` fails with a lockfile mismatch                   | `package.json` changed without the lockfile                 | `pnpm install` locally and commit `console/pnpm-lock.yaml`              |
| `permission denied` on `/var/run/docker.sock`                   | Your user is not in the `docker` group                      | `sudo usermod -aG docker $USER && newgrp docker`                        |
| `dev-cluster-verify.sh` reports no BTF                          | Kernel built without BTF, or a VM whose kernel lacks it     | Use a Linux host/VM with `CONFIG_DEBUG_INFO_BTF=y`                      |
| Loading eBPF fails with `operation not permitted` in a kind node | Rootless Docker: no `CAP_BPF` in the initial user namespace | Run Docker in its normal mode                                           |

## Adding tools later

Adding a tool to the project means adding it to `mise.toml` (or, for Python
tools, to the analyzer's dev dependency group), not to your machine.
See [TOOLCHAIN.md § Adding a tool](./TOOLCHAIN.md#adding-a-tool).
