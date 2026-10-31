#!/usr/bin/env bash
#
# Validates .pre-commit-config.yaml and exercises the hooks with real commits
# (EPIC-1 / T1.10).
#
# The commits happen in a throwaway copy of the repo, so this never installs
# hooks into your checkout. Run it from anywhere in the repo:
#
#   scripts/pre_commit_test.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0

# ---------------------------------------------------------------------------
# 1. pre-commit is available and the config is valid
# ---------------------------------------------------------------------------
echo "==> pre-commit is installed"
if command -v pre-commit >/dev/null 2>&1; then
    echo "  ok: $(pre-commit --version)"
else
    echo "  FAIL: pre-commit not found (run: mise install)"
    exit 1
fi

echo "==> .pre-commit-config.yaml is valid"
if pre-commit validate-config .pre-commit-config.yaml; then
    echo "  ok: config validates"
else
    echo "  FAIL: .pre-commit-config.yaml is not valid"
    fail=1
fi

# ---------------------------------------------------------------------------
# 2. The config holds no version pins of its own (see docs/TOOLCHAIN.md)
# ---------------------------------------------------------------------------
echo "==> .pre-commit-config.yaml pins no versions"
if grep -qE '^[[:space:]]*rev:' .pre-commit-config.yaml; then
    echo "  FAIL: rev: found — hooks must be 'repo: local' and use the pinned toolchain"
    fail=1
else
    echo "  ok: no rev: keys"
fi

echo "==> mise.toml pins pre-commit on a uv-managed Python"
if grep -qE '^"pypi:pre-commit"[[:space:]]*=.*only-managed' mise.toml; then
    echo "  ok: pre-commit pinned"
else
    echo "  FAIL: no pypi:pre-commit entry with only-managed in mise.toml"
    fail=1
fi

# ---------------------------------------------------------------------------
# 3. Build a throwaway repo from the working tree
# ---------------------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -xf - -C "$work"
ln -s "$repo_root/console/node_modules" "$work/console/node_modules"

# The copy's mise.toml is new to mise, which refuses untrusted config files.
export MISE_TRUSTED_CONFIG_PATHS="$work"

cd "$work"
git init -q -b work
git config user.name "pre-commit test"
git config user.email "pre-commit-test@example.invalid"
git add -A
git commit -q -m "seed"

echo "==> pre-commit install works"
if pre-commit install >/dev/null && [[ -x .git/hooks/pre-commit ]]; then
    echo "  ok: hook installed"
else
    echo "  FAIL: pre-commit install did not create .git/hooks/pre-commit"
    exit 1
fi

echo "==> the hook runs on a uv-managed Python"
hook_python="$(readlink -f "$(sed -n 's/^INSTALL_PYTHON=//p' .git/hooks/pre-commit)")"
if [[ "$hook_python" == "$(readlink -f "$(uv python dir)")"/* ]]; then
    echo "  ok: $hook_python"
else
    echo "  FAIL: hook does not use a uv-managed Python: $hook_python"
    fail=1
fi

# ---------------------------------------------------------------------------
# 4. Staged files with problems block the commit; clean ones do not
# ---------------------------------------------------------------------------

# stage <path> <content>
stage() {
    printf '%b' "$2" >"$1"
    git add "$1"
}

# unstage <path>
unstage() {
    git reset -q
    rm -f "$1"
}

# expect_blocked <description> <hook name> <path> <content>
expect_blocked() {
    local output
    stage "$3" "$4"
    if output="$(git commit -m "test" 2>&1)"; then
        echo "  FAIL: $1 — commit was not blocked"
        git reset -q --soft HEAD~1
        fail=1
    elif grep -q "^$2\.*Failed" <<<"$output"; then
        echo "  ok: $1"
    else
        echo "  FAIL: $1 — commit failed, but not on the '$2' hook:"
        echo "$output"
        fail=1
    fi
    unstage "$3"
}

# expect_allowed <description> <path> <content>
expect_allowed() {
    local output
    stage "$2" "$3"
    if output="$(git commit -m "test" 2>&1)"; then
        echo "  ok: $1"
        git reset -q --soft HEAD~1
    else
        echo "  FAIL: $1 — commit was blocked:"
        echo "$output"
        fail=1
    fi
    unstage "$2"
}

go_file=sensor/cmd/sensor/hook_probe.go
py_file=analyzer/kuvera_analyzer/hook_probe.py
ts_file=console/src/hook_probe.ts
tsx_file=console/src/hook_probe.tsx

echo "==> staged files with problems block the commit"
expect_blocked "gofmt violation" "gofmt + goimports" "$go_file" \
    'package main\n\nfunc   probe() {}\n'
expect_blocked "goimports violation" "gofmt + goimports" "$go_file" \
    'package main\n\nfunc probe() { fmt.Println() }\n'
expect_blocked "ruff violation" "ruff" "$py_file" 'import os\n'
expect_blocked "eslint violation" "eslint" "$ts_file" 'const unused = 1;\n'
expect_blocked "prettier violation" "prettier" "$ts_file" 'export const used = 1\n'

echo "==> clean staged files commit normally"
expect_allowed "clean Go file" "$go_file" 'package main\n\nfunc probe() {}\n'
expect_allowed "clean Python file" "$py_file" '"""Probe."""\n'
expect_allowed "clean TypeScript file" "$ts_file" 'export const used: number = 1;\n'
expect_allowed "clean TSX file" "$tsx_file" 'export const element = <div />;\n'

# ---------------------------------------------------------------------------
# 5. The branch guard refuses main and dev
# ---------------------------------------------------------------------------
echo "==> commits to main and dev are refused"
for branch in main dev; do
    git switch -q -c "$branch"
    expect_blocked "commit on $branch" "no commits to main or dev" notes.txt 'probe\n'
    git switch -q work
    git branch -q -D "$branch"
done
expect_allowed "commit on a feature branch" notes.txt 'probe\n'

# ---------------------------------------------------------------------------
echo
if [[ "$fail" -ne 0 ]]; then
    echo "pre-commit test FAILED"
    exit 1
fi

echo "pre-commit test PASSED"
