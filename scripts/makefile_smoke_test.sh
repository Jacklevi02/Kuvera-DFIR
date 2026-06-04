#!/usr/bin/env bash
#
# Smoke test for the root Makefile (EPIC-1 / T1.2).
#
# Verifies the two acceptance criteria for the stub Makefile:
#   1. `make help` lists every target.
#   2. Every target runs and exits 0.
#
# This is intentionally standalone (it shells out to `make` rather than living
# inside a component test runner) so it can be wired into `make test` (T1.6)
# and CI (T1.7) once those land. Run it from anywhere:
#
#   scripts/makefile_smoke_test.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Every target the Makefile is expected to expose, per CLAUDE.md, T1.2, and
# T1.3 (which adds dev-cluster-down).
targets=(help dev-cluster dev-cluster-down build test lint deploy-dev e2e clean)

# Targets safe to actually run in any environment. dev-cluster and
# dev-cluster-down provision/destroy a real kind cluster (Docker + kind) as of
# T1.3, so they are exercised by scripts/dev_cluster_config_test.sh and e2e
# instead of being invoked blindly here.
runnable=(help build test lint deploy-dev e2e clean)

fail=0

echo "==> 'make help' lists every target"
help_output="$(make help)"
for t in "${targets[@]}"; do
	if grep -qE "^  ${t} " <<<"$help_output"; then
		echo "  ok: '$t' listed"
	else
		echo "  FAIL: '$t' missing from 'make help' output"
		fail=1
	fi
done

echo "==> every runnable target exits 0"
for t in "${runnable[@]}"; do
	if make "$t" >/dev/null 2>&1; then
		echo "  ok: make $t"
	else
		echo "  FAIL: make $t exited non-zero"
		fail=1
	fi
done

if [[ "$fail" -ne 0 ]]; then
	echo "Makefile smoke test FAILED"
	exit 1
fi

echo "Makefile smoke test PASSED"
