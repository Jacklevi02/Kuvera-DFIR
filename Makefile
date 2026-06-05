# Kuvera root Makefile.
#
# Single entry point for building, testing, linting, and running Kuvera in a
# local dev cluster (see CLAUDE.md, "Development workflow").
#
# Several targets are still stubs at this stage: they print a uniform
# "not yet implemented" message and exit 0 so the target graph is usable and
# discoverable before the real logic lands. Sibling tickets in EPIC-1 replace
# each stub body with a real implementation:
#
#   build -> EPIC-1   test -> T1.6
#
# `clean`, `dev-cluster`/`dev-cluster-down` (T1.3), and `lint` (T1.4) are real.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

# kind dev cluster (T1.3). Override on the command line, e.g.:
#   make dev-cluster KIND_CLUSTER_NAME=kuvera-test KIND_NODE_IMAGE=kindest/node:v1.31.2
#   make dev-cluster KIND_RECREATE=1     # delete and rebuild an existing cluster
KIND_CLUSTER_NAME ?= kuvera-dev
KIND_NODE_IMAGE   ?=
export KIND_CLUSTER_NAME KIND_NODE_IMAGE

# Go linter (T1.4). Override if golangci-lint lives outside $PATH, e.g.:
#   make lint GOLANGCI_LINT=/usr/local/bin/golangci-lint
GOLANGCI_LINT ?= golangci-lint

# Python and TypeScript linters (T1.5). Override if tools live outside $PATH.
RUFF     ?= ruff
MYPY     ?= mypy
ESLINT   ?= eslint
PRETTIER ?= prettier

.PHONY: help dev-cluster dev-cluster-down build test lint deploy-dev e2e clean

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

build: ## Build all components (sensor, operator, api, analyzer, console)
	@echo "make build: not yet implemented (tracked in EPIC-1)"

test: ## Run unit tests across all components (T1.6)
	@echo "make test: not yet implemented (tracked in EPIC-1 / T1.6)"

lint: ## Run all linters: Go (T1.4), Python and TypeScript (T1.5)
	@cd sensor   && $(GOLANGCI_LINT) run ./...
	@cd operator && $(GOLANGCI_LINT) run ./...
	@cd api      && $(GOLANGCI_LINT) run ./...
	@cd analyzer && $(RUFF) check .
	@cd analyzer && $(MYPY) --strict kuvera_analyzer/
	@cd console  && $(ESLINT) --no-error-on-unmatched-pattern "src/**/*.{ts,tsx}"
	@cd console  && $(PRETTIER) --check "src/**/*.{ts,tsx,css}" --no-error-on-unmatched-pattern

deploy-dev: ## Install the Helm chart into the dev cluster
	@echo "make deploy-dev: not yet implemented (tracked in EPIC-1)"

e2e: ## Run end-to-end tests against the dev cluster
	@echo "make e2e: not yet implemented (tracked in EPIC-1)"

clean: ## Remove local build artifacts
	@rm -rf bin dist build console/dist console/build e2e-output
	@echo "make clean: removed local build artifacts"
