# Kuvera root Makefile.
#
# Single entry point for building, testing, linting, and running Kuvera in a
# local dev cluster (see CLAUDE.md, "Development workflow").
#
# Two targets are still stubs at this stage: they print a uniform
# "not yet implemented" message and exit 0 so the target graph is usable and
# discoverable before the real logic lands. Later tickets replace each stub
# body with a real implementation:
#
#   deploy-dev -> T5.4
#   e2e        -> T20.1
#
# `build`, `clean`, `dev-cluster`/`dev-cluster-down` (T1.3), `lint` (T1.4/T1.5),
# `test` (T1.6), and `test-tooling` (T1.15) are real.
#
# Tool versions are NOT pinned here: the toolchain comes from mise.toml, uv and
# Python from analyzer/pyproject.toml and analyzer/.python-version (uv is
# installed standalone, not by mise), and per-language tools from
# analyzer/pyproject.toml and console/package.json.
# pytest exit 5 means "no tests collected" — valid on an empty scaffolding.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

# kind dev cluster (T1.3). Override on the command line, e.g.:
#   make dev-cluster KIND_CLUSTER_NAME=kuvera-test KIND_NODE_IMAGE=kindest/node:v1.36.1
#   make dev-cluster KIND_RECREATE=1     # delete and rebuild an existing cluster
#
# Docker is the only supported runtime. See docs/DEVELOPMENT-SETUP.md.
KIND_CLUSTER_NAME ?= kuvera-dev
KIND_NODE_IMAGE   ?=
export KIND_CLUSTER_NAME KIND_NODE_IMAGE

# Go linter (T1.4). Override if golangci-lint lives outside $PATH, e.g.:
#   make lint GOLANGCI_LINT=/usr/local/bin/golangci-lint
GOLANGCI_LINT ?= golangci-lint

# Bash linter (T1.15). Override if shellcheck lives outside $PATH.
SHELLCHECK ?= shellcheck

# Python tooling runs through uv, so ruff/mypy/pytest versions come from
# analyzer/pyproject.toml rather than whatever happens to be on $PATH.
UV ?= uv

# TypeScript tooling runs through pnpm, so eslint/prettier/typescript/vitest
# versions come from console/package.json. pnpm only — no npm, no yarn.
PNPM ?= pnpm

# Go toolchain. Override if go lives outside $PATH.
GO ?= go

.PHONY: help dev-cluster dev-cluster-down build test test-tooling lint deploy-dev e2e clean

help: ## List all available targets
	@echo "Kuvera — make targets:"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

dev-cluster: ## Boot (or ensure) a local kind cluster with eBPF support (T1.3)
	@scripts/dev-cluster.sh up

dev-cluster-down: ## Tear down the local kind dev cluster (T1.3)
	@scripts/dev-cluster.sh down

# Go binaries land in bin/, the analyzer wheel and sdist in dist/analyzer/. The
# console joins here with T17.1, which adds Vite and its build script.
build: ## Build all components (sensor, operator, api, analyzer)
	@cd sensor   && $(GO) build -o ../bin/ ./...
	@cd operator && $(GO) build -o ../bin/ ./...
	@cd api      && $(GO) build -o ../bin/ ./...
	@cd analyzer && $(UV) build --quiet --out-dir ../dist/analyzer

test: ## Run unit tests across all components (T1.6)
	@cd sensor   && $(GO) test ./...
	@cd operator && $(GO) test ./...
	@cd api      && $(GO) test ./...
	@cd analyzer && ($(UV) run pytest || [ $$? -eq 5 ])
	@cd console  && $(PNPM) run test
	@bash scripts/dev_cluster_config_test.sh

# These re-run make lint and make test, so this is the slowest target. CI's
# Validate job runs it. makefile_smoke_test.sh must never run this target, or
# the two would recurse.
test-tooling: ## Validate tooling config and make wiring (T1.15)
	@bash scripts/golangci_lint_test.sh
	@bash scripts/python_ts_lint_test.sh
	@bash scripts/make_test_smoke_test.sh
	@bash scripts/makefile_smoke_test.sh
	@bash scripts/pre_commit_test.sh

lint: ## Run all linters: Go (T1.4), Python and TypeScript (T1.5), Bash (T1.15)
	@cd sensor   && $(GOLANGCI_LINT) run ./...
	@cd operator && $(GOLANGCI_LINT) run ./...
	@cd api      && $(GOLANGCI_LINT) run ./...
	@cd analyzer && $(UV) run ruff check .
	@cd analyzer && $(UV) run ruff format --check .
	@cd analyzer && $(UV) run mypy --strict kuvera_analyzer/
	@cd console  && $(PNPM) run lint
	@cd console  && $(PNPM) run format:check
	@$(SHELLCHECK) scripts/*.sh
# `pnpm run typecheck` is deliberately not wired in yet: tsc exits TS18003
# ("no inputs were found") while console/src/ is empty scaffolding. Add it
# here once the first .ts/.tsx file lands.

deploy-dev: ## Install the Helm chart into the dev cluster
	@echo "make deploy-dev: not yet implemented (tracked in T5.4)"

e2e: ## Run end-to-end tests against the dev cluster
	@echo "make e2e: not yet implemented (tracked in T20.1)"

clean: ## Remove local build artifacts
	@rm -rf bin dist build console/dist console/build e2e-output
	@echo "make clean: removed local build artifacts"
