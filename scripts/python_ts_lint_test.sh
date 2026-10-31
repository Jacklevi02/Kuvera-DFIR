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
# 6b. console/pnpm-lock.yaml is committed (pnpm only — no npm, no yarn)
# ---------------------------------------------------------------------------
echo "==> console/pnpm-lock.yaml is committed"
if [[ -f "console/pnpm-lock.yaml" ]]; then
    echo "  ok: console/pnpm-lock.yaml found"
else
    echo "  FAIL: console/pnpm-lock.yaml missing (run: cd console && pnpm install)"
    fail=1
fi

echo "==> no npm/yarn lockfiles in console/"
for stray in console/package-lock.json console/yarn.lock; do
    if [[ -f "$stray" ]]; then
        echo "  FAIL: $stray present — this project uses pnpm only"
        fail=1
    else
        echo "  ok: $stray absent"
    fi
done

# ---------------------------------------------------------------------------
# 6c. analyzer/uv.lock is committed
# ---------------------------------------------------------------------------
echo "==> analyzer/uv.lock is committed"
if [[ -f "analyzer/uv.lock" ]]; then
    echo "  ok: analyzer/uv.lock found"
else
    echo "  FAIL: analyzer/uv.lock missing (run: cd analyzer && uv sync)"
    fail=1
fi

# ---------------------------------------------------------------------------
# 6d. Python and uv are pinned by uv, not mise (see docs/TOOLCHAIN.md)
# ---------------------------------------------------------------------------
echo "==> analyzer/.python-version pins the interpreter"
if [[ -s "analyzer/.python-version" ]]; then
    echo "  ok: analyzer/.python-version = $(head -1 analyzer/.python-version)"
else
    echo "  FAIL: analyzer/.python-version missing (run: cd analyzer && uv python pin <version>)"
    fail=1
fi

echo "==> analyzer/pyproject.toml pins uv via [tool.uv] required-version"
if python3 -c "import tomllib, sys; sys.exit(0 if tomllib.load(open('analyzer/pyproject.toml','rb')).get('tool', {}).get('uv', {}).get('required-version') else 1)" 2>/dev/null; then
    echo "  ok: required-version set"
else
    echo "  FAIL: [tool.uv] required-version missing from analyzer/pyproject.toml"
    fail=1
fi

echo "==> mise.toml does not manage python or uv"
for tool in python uv; do
    if grep -qE "^[[:space:]]*\"?$tool\"?[[:space:]]*=" mise.toml; then
        echo "  FAIL: $tool is pinned in mise.toml — uv and Python are managed by uv"
        fail=1
    else
        echo "  ok: $tool not in mise.toml"
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
