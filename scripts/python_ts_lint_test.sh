#!/usr/bin/env bash
#
# Validates the Python and TypeScript lint configuration and exercises
# `make lint` against the analyzer and console scaffolding (EPIC-1 / T1.5).
#
# This script is intentionally standalone — it does not require a test runner
# and can be wired into `make test` (T1.6) and CI (T1.7) once those land.
# Run it from anywhere in the repo:
#
#   scripts/python_ts_lint_test.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0

# ---------------------------------------------------------------------------
# 1. analyzer/pyproject.toml exists
# ---------------------------------------------------------------------------
echo "==> analyzer/pyproject.toml exists"
if [[ -f "analyzer/pyproject.toml" ]]; then
    echo "  ok: analyzer/pyproject.toml found"
else
    echo "  FAIL: analyzer/pyproject.toml missing"
    fail=1
fi

# ---------------------------------------------------------------------------
# 2. analyzer/pyproject.toml is valid TOML
# ---------------------------------------------------------------------------
echo "==> analyzer/pyproject.toml is valid TOML"
if python3 -c "import tomllib; tomllib.load(open('analyzer/pyproject.toml','rb'))" 2>/dev/null; then
    echo "  ok: TOML parses cleanly"
else
    echo "  FAIL: analyzer/pyproject.toml is not valid TOML"
    fail=1
fi

# ---------------------------------------------------------------------------
# 3. analyzer/pyproject.toml references ruff and mypy
# ---------------------------------------------------------------------------
echo "==> analyzer/pyproject.toml references ruff and mypy"
for tool in ruff mypy; do
    if grep -q "$tool" analyzer/pyproject.toml; then
        echo "  ok: $tool referenced"
    else
        echo "  FAIL: $tool not found in analyzer/pyproject.toml"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 4. console/package.json exists
# ---------------------------------------------------------------------------
echo "==> console/package.json exists"
if [[ -f "console/package.json" ]]; then
    echo "  ok: console/package.json found"
else
    echo "  FAIL: console/package.json missing"
    fail=1
fi

# ---------------------------------------------------------------------------
# 5. console/package.json is valid JSON
# ---------------------------------------------------------------------------
echo "==> console/package.json is valid JSON"
if python3 -c "import json; json.load(open('console/package.json'))" 2>/dev/null; then
    echo "  ok: JSON parses cleanly"
else
    echo "  FAIL: console/package.json is not valid JSON"
    fail=1
fi

# ---------------------------------------------------------------------------
# 6. console/package.json references eslint, prettier, typescript
# ---------------------------------------------------------------------------
echo "==> console/package.json references eslint, prettier, typescript"
for tool in eslint prettier typescript; do
    if grep -q "\"$tool\"" console/package.json; then
        echo "  ok: $tool referenced"
    else
        echo "  FAIL: $tool not found in console/package.json"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 7. console/tsconfig.json exists and has strict + noUncheckedIndexedAccess
# ---------------------------------------------------------------------------
echo "==> console/tsconfig.json exists"
if [[ -f "console/tsconfig.json" ]]; then
    echo "  ok: console/tsconfig.json found"
else
    echo "  FAIL: console/tsconfig.json missing"
    fail=1
fi

echo "==> console/tsconfig.json has strict and noUncheckedIndexedAccess"
for key in strict noUncheckedIndexedAccess; do
    if grep -q "\"$key\"" console/tsconfig.json; then
        echo "  ok: $key present"
    else
        echo "  FAIL: $key not found in console/tsconfig.json"
        fail=1
    fi
done

# ---------------------------------------------------------------------------
# 8. make lint exits 0
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
    echo "Python and TypeScript lint config test FAILED"
    exit 1
fi

echo "Python and TypeScript lint config test PASSED"
