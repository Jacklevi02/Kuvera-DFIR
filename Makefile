# Kuvera root Makefile.
#
# Single entry point for building, testing, linting, and running Kuvera in a
# local dev cluster (see CLAUDE.md, "Development workflow").
#
# Most targets are intentionally stubs at this stage: they print a uniform
# "not yet implemented" message and exit 0 so the target graph is usable and
# discoverable before the real logic lands. Sibling tickets in EPIC-1 replace
# each stub body with a real implementation:
#
#   dev-cluster -> T1.3   build -> EPIC-1   test -> T1.6   lint -> T1.4 / T1.5
#
# `clean` is implemented now (it only removes local, git-ignored build output).

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help dev-cluster build test lint deploy-dev e2e clean

help: ## List all available targets
	@echo "Kuvera — make targets:"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

dev-cluster: ## Boot a local kind cluster with eBPF support (T1.3)
	@echo "make dev-cluster: not yet implemented (tracked in EPIC-1 / T1.3)"

build: ## Build all components (sensor, operator, api, analyzer, console)
	@echo "make build: not yet implemented (tracked in EPIC-1)"

test: ## Run unit tests across all components (T1.6)
	@echo "make test: not yet implemented (tracked in EPIC-1 / T1.6)"

lint: ## Run all linters: Go (T1.4), Python and TypeScript (T1.5)
	@echo "make lint: not yet implemented (tracked in EPIC-1 / T1.4, T1.5)"

deploy-dev: ## Install the Helm chart into the dev cluster
	@echo "make deploy-dev: not yet implemented (tracked in EPIC-1)"

e2e: ## Run end-to-end tests against the dev cluster
	@echo "make e2e: not yet implemented (tracked in EPIC-1)"

clean: ## Remove local build artifacts
	@rm -rf bin dist build console/dist console/build e2e-output
	@echo "make clean: removed local build artifacts"
