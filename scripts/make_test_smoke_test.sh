#!/usr/bin/env bash
#
# Validates the `make test` target wiring across all components (EPIC-1 / T1.6).
#
# Checks that each test runner is reachable and that `make test` exits 0 on
# the current codebase. Does NOT recursively invoke `make test` itself inside
# the test checks — only validates configuration and individual runners.
#
# Run it from anywhere in the repo:
#
#   scripts/make_test_smoke_test.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0

# ---------------------------------------------------------------------------
# 1. Go test runner is available
# ---------------------------------------------------------------------------
echo "==> Go test runner available"
if command -v go >/dev/null 2>&1; then
    echo "  ok: $(go version)"
else
    echo "  FAIL: go not found in PATH"
    fail=1
fi

# ---------------------------------------------------------------------------
# 2. Go tests pass in each module
# ---------------------------------------------------------------------------
echo "==> Go tests pass in each module"
for module in sensor operator api; do
    if (cd "$module" && go test ./... >/dev/null 2>&1); then
        echo "  ok: $module"
    else
        echo "  FAIL: go test ./... failed in $module/"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 3. pytest is available
# ---------------------------------------------------------------------------
echo "==> pytest available"
if command -v pytest >/dev/null 2>&1; then
    echo "  ok: $(pytest --version 2>&1 | head -1)"
else
    echo "  FAIL: pytest not found in PATH"
    fail=1
fi

# ---------------------------------------------------------------------------
# 4. pytest exits 0 or 5 (no tests collected) in analyzer/
# ---------------------------------------------------------------------------
echo "==> pytest exits 0 or 5 in analyzer/"
if (cd analyzer && pytest >/dev/null 2>&1); then
    echo "  ok: pytest passed"
else
    code=$?
    if [[ "$code" -eq 5 ]]; then
        echo "  ok: pytest exited 5 (no tests collected — expected on empty scaffolding)"
    else
        echo "  FAIL: pytest exited $code"
        fail=1
    fi
fi

# ---------------------------------------------------------------------------
# 5. vitest is reachable via npx
# ---------------------------------------------------------------------------
echo "==> vitest reachable via npx"
if npx --yes vitest --version >/dev/null 2>&1; then
    echo "  ok: vitest available via npx"
else
    echo "  FAIL: npx vitest not available"
    fail=1
fi

# ---------------------------------------------------------------------------
# 6. vitest exits 0 with --passWithNoTests in console/
# ---------------------------------------------------------------------------
echo "==> vitest exits 0 with --passWithNoTests in console/"
if (cd console && npx --yes vitest run --passWithNoTests >/dev/null 2>&1); then
    echo "  ok: vitest passed"
else
    echo "  FAIL: vitest exited non-zero"
    fail=1
fi

# ---------------------------------------------------------------------------
# 7. Makefile wires go, pytest, vitest into the test target
# ---------------------------------------------------------------------------
echo "==> Makefile wires test runners into test target"
# Go is referenced via the $(GO) variable so check for the variable pattern.
if grep -qE '\$\(GO\).*test|go test' Makefile; then
    echo "  ok: go test referenced in Makefile"
else
    echo "  FAIL: go test not found in Makefile"
    fail=1
fi
for runner in pytest vitest; do
    if grep -q "$runner" Makefile; then
        echo "  ok: $runner referenced in Makefile"
    else
        echo "  FAIL: $runner not found in Makefile"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 8. make test exits 0
# ---------------------------------------------------------------------------
echo "==> make test exits 0"
if make test >/dev/null 2>&1; then
    echo "  ok: make test passed"
else
    echo "  FAIL: make test exited non-zero — run 'make test' to see the output"
    fail=1
fi

# ---------------------------------------------------------------------------
echo
if [[ "$fail" -ne 0 ]]; then
    echo "make test smoke test FAILED"
    exit 1
fi

echo "make test smoke test PASSED"
