#!/usr/bin/env bash
#
# Validates the golangci-lint configuration and exercises `make lint` against
# the Go modules (EPIC-1 / T1.4).
#
# This script is intentionally standalone — it does not require a test runner
# and can be wired into `make test` (T1.6) and CI (T1.7) once those land.
# Run it from anywhere in the repo:
#
#   scripts/golangci_lint_test.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0

# ---------------------------------------------------------------------------
# 1. Config file exists
# ---------------------------------------------------------------------------
echo "==> .golangci.yaml exists"
if [[ -f ".golangci.yaml" ]]; then
    echo "  ok: .golangci.yaml found"
else
    echo "  FAIL: .golangci.yaml missing"
    fail=1
fi

# ---------------------------------------------------------------------------
# 2. Config file is valid YAML
# ---------------------------------------------------------------------------
echo "==> .golangci.yaml is valid YAML"
if python3 -c "import yaml, sys; yaml.safe_load(open('.golangci.yaml'))" 2>/dev/null; then
    echo "  ok: YAML parses cleanly"
else
    echo "  FAIL: .golangci.yaml is not valid YAML"
    fail=1
fi

# ---------------------------------------------------------------------------
# 3. Config declares v2 format
# ---------------------------------------------------------------------------
echo "==> .golangci.yaml declares version 2"
if grep -q '^version:' .golangci.yaml; then
    echo "  ok: version key present"
else
    echo "  FAIL: version key missing (expected 'version: \"2\"' for golangci-lint v2)"
    fail=1
fi

# ---------------------------------------------------------------------------
# 4. Required linters are referenced in the config
# ---------------------------------------------------------------------------
echo "==> required linters present in .golangci.yaml"
required_linters=(errcheck govet staticcheck gosec revive gofmt goimports)
for linter in "${required_linters[@]}"; do
    if grep -q "$linter" .golangci.yaml; then
        echo "  ok: $linter"
    else
        echo "  FAIL: $linter not found in .golangci.yaml"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 5. Makefile invokes golangci-lint
# ---------------------------------------------------------------------------
echo "==> Makefile wires golangci-lint into the lint target"
if grep -q "golangci-lint" Makefile; then
    echo "  ok: golangci-lint referenced in Makefile"
else
    echo "  FAIL: golangci-lint not found in Makefile"
    fail=1
fi

# ---------------------------------------------------------------------------
# 6. make lint exits 0 on the current codebase
# ---------------------------------------------------------------------------
echo "==> make lint exits 0"
if make lint >/dev/null 2>&1; then
    echo "  ok: make lint passed"
else
    echo "  FAIL: make lint exited non-zero — run 'make lint' to see the issues"
    fail=1
fi

# ---------------------------------------------------------------------------
echo
if [[ "$fail" -ne 0 ]]; then
    echo "golangci-lint config test FAILED"
    exit 1
fi

echo "golangci-lint config test PASSED"
