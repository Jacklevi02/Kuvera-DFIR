# Testing

What checks Kuvera has, where each one runs, and what blocks a merge. Run
`make lint` and `make test` before opening a PR. Tool setup is in
[DEVELOPMENT-SETUP.md](./DEVELOPMENT-SETUP.md).

## Kinds of check

| Kind            | Run with                                 | Covers                                                                                                                                                                                           |
| --------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Unit tests      | `make test`                              | Go, Python and TypeScript tests, plus an offline check of the kind config and cluster scripts using a stub `kubectl`.                                                                            |
| Lint            | `make lint`                              | golangci-lint (including gofmt and goimports), ruff (lint and format), mypy, ESLint, Prettier, and ShellCheck on `scripts/*.sh`.                                                                 |
| Tooling scripts | `make test-tooling`                      | Config validity, version-pin rules, `make` wiring, and that lint and hooks really fail on bad input, using probes in a throwaway copy of the repo. Slow: it re-runs `make lint` and `make test`. |
| Live cluster    | [By hand](#what-only-runs-by-hand) or CI | A real kind cluster boots, nodes are Ready, BTF is present, and a node loads an eBPF program as root and refuses it as an unprivileged user.                                                     |
| End-to-end      | Nothing yet                              | No end-to-end tests exist.                                                                                                                                                                       |

Three gaps a green run does not show:

- **`make e2e` and `make deploy-dev` are stubs.** They print "not yet implemented"
  and exit 0 until T20.1 and T5.4. A pass proves nothing, and nothing deploys
  Kuvera to a cluster yet.
- **The analyzer and console have no tests.** `make test` still passes, because it
  accepts pytest's exit 5 (no tests collected) and vitest runs with
  `--passWithNoTests`. Each Go module has one test.
- **No eBPF program is tested,** because `sensor/bpf/` is empty. The live cluster
  check loads a trivial probe, not sensor code.

## Where each check runs

CI job names are shortened here; the full names are in the
[next section](#what-blocks-a-merge).

| Check                         | `make test` | `make lint` | CI job       | Pre-commit hook             | Run it alone                                           |
| ----------------------------- | ----------- | ----------- | ------------ | --------------------------- | ------------------------------------------------------ |
| Go tests                      | Yes         | No          | Test         | No                          | `go test ./...` in a module                            |
| pytest                        | Yes         | No          | Test         | No                          | `uv run pytest` in `analyzer/`                         |
| vitest                        | Yes         | No          | Test         | No                          | `pnpm test` in `console/`                              |
| Offline cluster config test   | Yes         | No          | Test         | No                          | `bash scripts/dev_cluster_config_test.sh`              |
| golangci-lint linters         | No          | Yes         | Lint         | No                          | `golangci-lint run ./...` in a module                  |
| gofmt, goimports              | No          | Yes         | Lint         | `gofmt + goimports`         | `golangci-lint fmt --diff`                             |
| ruff check                    | No          | Yes         | Lint         | `ruff`                      | `uv run ruff check .` in `analyzer/`                   |
| ruff format                   | No          | Yes         | Lint         | No                          | `uv run ruff format --check .` in `analyzer/`          |
| mypy                          | No          | Yes         | Lint         | No                          | `uv run mypy --strict kuvera_analyzer/` in `analyzer/` |
| ESLint                        | No          | Yes         | Lint         | `eslint`                    | `pnpm run lint` in `console/`                          |
| Prettier                      | No          | Yes         | Lint         | `prettier`                  | `pnpm run format:check` in `console/`                  |
| ShellCheck                    | No          | Yes         | Lint         | No                          | `shellcheck scripts/*.sh`                              |
| Tooling scripts               | No          | No          | Validate     | No                          | `make test-tooling`                                    |
| DCO sign-off                  | No          | No          | DCO          | No                          | CI only                                                |
| No commits to `main` or `dev` | No          | No          | No           | `no commits to main or dev` | Hook only; the ruleset blocks direct pushes            |
| Live cluster                  | No          | No          | Live cluster | No                          | [By hand](#what-only-runs-by-hand)                     |
| TypeScript typecheck          | No          | No          | No           | No                          | [By hand](#what-only-runs-by-hand)                     |

Bash scripts test themselves, with no framework. `scripts/makefile_smoke_test.sh`
fails if a `scripts/*_test.sh` file is not wired into `make test` or
`make test-tooling`.

## What blocks a merge

CI runs on every push and PR targeting `dev` or `main`; a PR stacked on a feature
branch gets only the DCO check until it is retargeted. The merge rules come from
the "Branch Protection" ruleset, which covers `dev` and `main`. It lives in GitHub
settings, not in this repo. To read it:

```bash
gh api repos/Jacklevi02/Kuvera-DFIR/rules/branches/dev
```

| Check                           | Required | Notes                                                  |
| ------------------------------- | -------- | ------------------------------------------------------ |
| `Lint (Go, Python, TypeScript)` | Yes      | Runs `make lint`                                       |
| `Test (Go, Python, TypeScript)` | Yes      | Runs `make test`                                       |
| `Validate tooling config`       | Yes      | Runs `make test-tooling`, after Lint and Test pass     |
| `DCO sign-off check`            | Yes      | Every commit needs `git commit -s`                     |
| `Live cluster (kind + eBPF)`    | No       | Runs on every PR, but a failure does not block a merge |

Required checks match by exact name, so renaming one of these jobs blocks every
PR until the ruleset is updated.

The ruleset also requires a PR with all review threads resolved (no approvals are
needed yet) and applies CodeQL and code quality gates. CodeQL default setup scans
GitHub Actions workflows only, not Go, Python or TypeScript.

## What only runs by hand

**TypeScript types.** Nothing checks them today, and this command cannot pass yet:
it fails with `TS18003` until `console/src/` has a `.ts` or `.tsx` file. It has to
be added to `make lint` by hand when that file lands.

```bash
cd console && pnpm run typecheck
```

**The cluster on your machine.** CI's Live cluster job boots a real kind cluster on
every push and PR targeting `dev` or `main`, but on GitHub's `ubuntu-latest` runner.
That says nothing about your own kernel or Docker setup. To check those, run the
same sequence locally. It needs Docker in normal mode, and an x86-64 host because
`scripts/ebpf-probe.go` hardcodes the syscall number:

```bash
make dev-cluster
scripts/dev-cluster-verify.sh     # nodes Ready, BTF present
CGO_ENABLED=0 go build -o bin/ebpf-probe scripts/ebpf-probe.go
docker cp bin/ebpf-probe kuvera-dev-control-plane:/ebpf-probe
docker exec kuvera-dev-control-plane /ebpf-probe     # expect: eBPF program loaded
docker exec --user 65534 kuvera-dev-control-plane /ebpf-probe 2>&1 \
  | grep -F 'operation not permitted'                # must refuse without privilege
make dev-cluster-down
```

**Cluster lifecycle.** CI boots one fresh cluster and never tears it down, so
these are only ever exercised by hand: re-running `make dev-cluster` on an existing
cluster, `make dev-cluster KIND_RECREATE=1`, and `make dev-cluster-down`.

**macOS.** BTF in the Docker VM is unverified. See the
[macOS caveat](./DEVELOPMENT-SETUP.md#6-ebpf-host-requirements).

## Pre-commit hooks

Optional, and set up in [CONTRIBUTING.md](../CONTRIBUTING.md#pre-commit-hooks-optional).
They check staged files only and never rewrite them, using the same config as
`make lint`. They run the hook subset shown in the table above, and no tests.
`pre-commit run --all-files` checks the whole repo.

To fix what they report, plus Python formatting, which only `make lint` checks:

```bash
golangci-lint fmt
(cd analyzer && uv run ruff check --fix && uv run ruff format .)
(cd console && pnpm run lint --fix && pnpm exec prettier --write src)
```

## Test conventions

[CLAUDE.md](../CLAUDE.md) owns these, so read them there:
[Go](../CLAUDE.md#go-sensor-operator-api),
[Python](../CLAUDE.md#python-analyzer),
[TypeScript](../CLAUDE.md#typescript-console) and
[eBPF](../CLAUDE.md#ebpf). What a ticket must include is in the
[Definition of Done](./PROJECT-MANAGEMENT.md#definition-of-done).
