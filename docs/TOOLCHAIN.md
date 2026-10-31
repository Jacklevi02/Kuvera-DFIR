# Toolchain

Which tools Kuvera uses, and where each version is pinned.

**No version numbers live in prose.** Every version has exactly one home. If you
need to know what version of something the project uses, read the file in the
"Pinned in" column — not this document, not a README.

## Where versions live

| Layer                | Tools                                                                                                                   | Pinned in                            |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Toolchain / runtimes | Go, Node.js, pnpm, golangci-lint, kind, kubectl, Helm, buf, pre-commit                                                  | `mise.toml`                          |
| uv                   | uv itself (installed standalone, **not** by mise)                                                                       | `[tool.uv] required-version` in `analyzer/pyproject.toml` |
| Python interpreter   | CPython, installed and managed by uv                                                                                    | `analyzer/.python-version`           |
| Go modules           | `cilium/ebpf`, controller-runtime, grpc-gateway                                                                           | `sensor/`, `operator/`, `api/go.mod` |
| Python packages      | ruff, mypy, pytest, structlog (Volatility3, YARA post-MVP)                                                                | `analyzer/pyproject.toml`            |
| Console packages     | TypeScript, React, Vite, Vitest, ESLint, Prettier, TanStack Query, TanStack Router, Tailwind, shadcn/ui, react-hook-form, zod | `console/package.json`               |

Lockfiles (`analyzer/uv.lock`, `console/pnpm-lock.yaml`) are committed and CI
installs from them with `pnpm install --frozen-lockfile` / `uv sync --locked`. Go modules have no
`go.sum` yet because no component has dependencies.

## Getting set up

```bash
mise install                        # Go, Node, pnpm, golangci-lint, kind, kubectl, helm, buf, pre-commit
cd analyzer && uv sync              # Python interpreter + ruff, mypy, pytest, structlog
cd console  && pnpm install         # TypeScript, ESLint, Prettier, Vitest
```

That assumes mise, uv, and a container runtime are already installed.
[DEVELOPMENT-SETUP.md](./DEVELOPMENT-SETUP.md) is the full walkthrough from a
clean machine, including Docker/Podman install and the eBPF host requirements.

## Rules

- **pnpm only.** No npm, no yarn. `console/package-lock.json` and
  `console/yarn.lock` are treated as errors by
  `scripts/python_ts_lint_test.sh`.
- **uv only** for Python. Do not `pip install` into the analyzer environment;
  `analyzer/pyproject.toml` is canonical. Dev tools live in
  `[dependency-groups] dev`, which `uv sync` and `uv run` install by default.
- **Python and uv stay out of `mise.toml`.** uv is installed standalone and
  owns the interpreter (`uv python install` / `uv python pin`). Pinning either
  in mise would give the project two Python managers fighting over `PATH`.
  `scripts/python_ts_lint_test.sh` fails if either appears in `mise.toml`.
- **pre-commit is a mise tool that runs on uv's Python.** It is repo-wide, so it
  is pinned in `mise.toml` rather than in the analyzer. `pypi:pre-commit` makes
  mise install it through uv into its own environment under mise's data
  directory, and `--python-preference only-managed` keeps that environment off
  system Python. uv must therefore be installed before `mise install`, in CI too.
- **Bump versions in one place.** A toolchain bump is an edit to `mise.toml`
  and nothing else — CI reads the same file via `jdx/mise-action`, so there is
  no second copy to keep in sync. Likewise CI's `astral-sh/setup-uv` reads uv's
  version from `analyzer/pyproject.toml`, and `uv sync` reads the interpreter
  from `analyzer/.python-version`.
- The Go language version in each `go.mod` tracks the `go` pin in `mise.toml`,
  as does `run.go` in `.golangci.yaml`. These three move together.
- **`.pre-commit-config.yaml` pins nothing.** Every hook is `repo: local` and runs
  the tool already pinned above, so a bump never needs a second edit.
  `scripts/pre_commit_test.sh` fails if a `rev:` appears.
- `analyzer/pyproject.toml` keeps a *lower bound* (`requires-python`,
  `ruff target-version`, `mypy python_version`) that is deliberately older than
  the interpreter in `analyzer/.python-version`. The floor is what the analyzer
  supports; `.python-version` is what developers and CI actually run.

## What each tool is for

| Tool              | Used by            | Purpose                                                        |
| ----------------- | ------------------ | -------------------------------------------------------------- |
| **Go**            | sensor, operator, api | All three services; the eBPF userspace loader                |
| **golangci-lint** | sensor, operator, api | Lint (`errcheck`, `govet`, `staticcheck`, `gosec`, `revive`, `sloglint`) |
| **Python**        | analyzer           | Evidence analysis workers                                       |
| **uv**            | analyzer           | Dependency resolution, virtualenv, task running                 |
| **ruff**          | analyzer           | Lint + format                                                   |
| **mypy**          | analyzer           | Static typing, `--strict`                                       |
| **pytest**        | analyzer           | Tests                                                           |
| **structlog**     | analyzer           | Structured logging                                              |
| **Node.js**       | console            | Runtime for the build and test toolchain                        |
| **pnpm**          | console            | Dependency management                                           |
| **TypeScript**    | console            | Language; `strict` + `noUncheckedIndexedAccess`                 |
| **Vite**          | console            | Dev server and production bundle                                |
| **Vitest**        | console            | Tests, with testing-library                                     |
| **ESLint**        | console            | Lint (flat config)                                              |
| **Prettier**      | console            | Format                                                          |
| **buf**           | api, console       | Protobuf/gRPC codegen; the generated console API client         |
| **pre-commit**    | all                | Optional local git hooks; see [CONTRIBUTING.md](../CONTRIBUTING.md#pre-commit-hooks-optional) |
| **kind**          | deploy             | Local dev cluster with BTF and bpffs for eBPF                   |
| **kubectl**       | deploy             | Cluster interaction                                             |
| **Helm**          | deploy             | Chart packaging and install                                     |

## Adding a tool

First decide where it belongs. Most things are not mise tools.

| What you are adding                                          | Where it goes                                                        |
| ------------------------------------------------------------- | -------------------------------------------------------------------- |
| A CLI the project needs (linter, codegen, cluster tool)       | `mise.toml`                                                          |
| A Python CLI used only by the analyzer (e.g. a linter)        | `[dependency-groups] dev` via `uv add --dev`                         |
| A Go / Python / TypeScript **library**                        | `go.mod`, `analyzer/pyproject.toml`, `console/package.json`          |
| A system daemon or OS-level dependency                        | Nothing to pin — document it in [DEVELOPMENT-SETUP.md](./DEVELOPMENT-SETUP.md) |

### Adding a CLI to mise.toml

Check that mise knows the tool, then add it:

```bash
mise registry stern          # -> aqua:stern/stern
mise use stern@1.32          # installs it and rewrites mise.toml
```

`mise use` edits `mise.toml` in place, so review the diff before committing. CI
needs no change at all — `jdx/mise-action` reads the same file, so the tool is
available to every job on the next run.

Pin to **major.minor** (`"1.32"`), not an exact patch. That is what the existing
entries do: patch releases are picked up automatically, minor and major bumps
stay deliberate.

### When the tool is not in the registry

`mise registry <name>` returning `tool not found in registry` does not mean the
tool is unavailable — it means there is no short alias. Name a backend directly:

```bash
mise use aqua:owner/repo@1.2          # aqua registry (most CLI tools)
mise use ubi:owner/repo@1.2           # any GitHub/GitLab release asset
mise use go:github.com/owner/repo@1.2 # installed with `go install`
mise use npm:some-cli@1.2             # published to npm
mise use pipx:some-cli@1.2            # published to PyPI
mise use cargo:some-cli@1.2           # published to crates.io
```

The full backend list is `aqua`, `asdf`, `cargo`, `conda`, `core`, `dotnet`,
`forgejo`, `gem`, `github`, `gitlab`, `go`, `npm`, `pipx`, `pkgx`, `spm`, `http`,
`s3`, `ubi`, `vfox`.

When a release asset's binary name differs from the repo name, pass a tool
option:

```bash
mise use ubi:BurntSushi/ripgrep[exe=rg]
```

Prefer `aqua:` where available — it verifies checksums, and several of this
project's tools (pnpm, golangci-lint, kind, kubectl, helm, buf) resolve through
it already.

### Adding a library instead

Libraries never go in `mise.toml`:

```bash
cd analyzer && uv add structlog          # updates pyproject.toml + uv.lock (--dev for tools)
cd console  && pnpm add -D some-package  # updates package.json + pnpm-lock.yaml
cd sensor   && go get github.com/cilium/ebpf   # updates go.mod + go.sum
```

Commit the manifest **and** the lockfile together — CI installs with
`--frozen-lockfile`, so a lockfile that lags its manifest fails the build.

## What mise does not manage

- **uv and Python — by choice.** uv is installed standalone
  ([installer](https://docs.astral.sh/uv/getting-started/installation/)) and
  manages Python itself; see the pins in the table at the top. Upgrade uv with
  `uv self update` and bump `required-version`; change the interpreter with
  `cd analyzer && uv python pin <version>`.
- **Nothing runs on system Python.** `analyzer/.python-version` pins an exact
  version, and `python-preference = "only-managed"` makes uv ignore system
  interpreters, so `analyzer/.venv` is built on a Python that uv installed under
  `~/.local/share/uv/python`. A venv already keeps the project's packages off the
  system. This protects in the other direction: an OS update cannot change or
  remove the project's interpreter, and developers and CI run the same version.
  The setting is in two places because uv does not merge config files: `uv.toml`
  covers repo-root `uv run` calls, such as the ones in `scripts/`, and
  `[tool.uv]` in `analyzer/pyproject.toml` covers the analyzer. Scripts call
  `uv run python3`, never a bare `python3`, and fail if uv is missing.
  `scripts/python_ts_lint_test.sh` fails if either setting is removed.

Other dependencies cannot be a versioned binary in a project config. These are
documented in [DEVELOPMENT-SETUP.md](./DEVELOPMENT-SETUP.md) instead.

- **The container runtime (Docker / Podman).** `mise registry docker` returns
  `tool not found in registry`. A container runtime is a privileged system daemon
  wired into the kernel, started by systemd, and shared by everything on the
  machine — a per-project version pin would be meaningless. Note the nuance:
  `docker-compose` *is* available (`github:docker/compose`), because the CLI
  plugin is just a binary. The daemon is not.
- **`git`, `make`, `bash`.** `git` and `bash` are likewise absent from the mise
  registry. System tools, installed by your OS.
- **The kernel.** BTF at `/sys/kernel/btf/vmlinux` is what makes CO-RE eBPF work,
  and cgroup v2 is what makes the dev cluster work. Nothing in userspace can
  install either.

### Why kind and not minikube

minikube *is* mise-installable (`aqua:kubernetes/minikube`), but nothing in this
repo invokes it: `make dev-cluster` runs `scripts/dev-cluster.sh`, which runs
kind against `deploy/dev/kind-config.yaml` — the config carrying the bpffs and
debugfs bind mounts the eBPF sensor needs. Pinning a second cluster provider
would add a ~120MB download to every developer's setup and every CI run for a
binary nothing calls. kind is the supported dev cluster; revisit only if a second
provider earns its place.

Choosing between Docker and Podman as kind's *runtime* is a separate question,
and both are supported — see
[DEVELOPMENT-SETUP.md](./DEVELOPMENT-SETUP.md#3-install-a-container-runtime).

## Upgrading

```bash
mise outdated          # what has newer releases
mise use go@1.28       # rewrites mise.toml
mise install
make lint && make test
```

Bumping Go also means editing the `go` directive in all three `go.mod` files
and `run.go` in `.golangci.yaml`. Everything else is picked up automatically.

uv and Python are upgraded outside mise:

```bash
uv self update                         # then bump [tool.uv] required-version
cd analyzer && uv python pin 3.15.1    # rewrites .python-version; always an exact version
uv sync && make lint && make test
```

For the console and analyzer, `pnpm update --latest` and `uv lock --upgrade`
refresh the library pins; commit the resulting lockfile.

## Deliberate version holds

- **TypeScript stays on 6.x.** TypeScript 7 (the Go-native compiler) is
  released, but `typescript-eslint` peers `typescript <6.1.0` — TS 7.0 ships no
  stable programmatic compiler API, so type-aware linting cannot run against
  it. Revisit when TS 7.1 lands that API.
- **Node stays on the Active LTS line.** Move to the next even release once it
  reaches Active LTS, not when it is first published as Current.
