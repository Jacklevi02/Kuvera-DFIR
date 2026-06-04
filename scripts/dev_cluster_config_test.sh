#!/usr/bin/env bash
#
# Offline tests for the kind dev-cluster tooling (EPIC-1 / T1.3).
#
# Runs without Docker, kind, or kubectl, so it is safe in CI and `make test`.
# It is the offline counterpart to scripts/dev-cluster-verify.sh (which needs a
# live cluster). Like scripts/makefile_smoke_test.sh, it is standalone so it can
# be wired into `make test` (T1.6) and CI (T1.7) once those land. Verifies:
#
#   1. The dev-cluster shell scripts are syntactically valid bash.
#   2. deploy/dev/kind-config.yaml is a valid v1alpha4 kind Cluster that
#      bind-mounts bpffs and debugfs into every node.
#   3. The Makefile exposes dev-cluster and dev-cluster-down.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

config="deploy/dev/kind-config.yaml"
fail=0

echo "==> bash syntax check on dev-cluster scripts"
for s in scripts/dev-cluster.sh scripts/dev-cluster-verify.sh scripts/dev_cluster_config_test.sh; do
	if bash -n "$s"; then
		echo "  ok: $s"
	else
		echo "  FAIL: $s has syntax errors"
		fail=1
	fi
done

echo "==> validating $config"
if ! command -v python3 >/dev/null 2>&1; then
	echo "  FAIL: python3 is required to validate the kind config"
	exit 1
fi
if python3 - "$config" <<'PY'; then
import sys

import yaml

path = sys.argv[1]
with open(path) as fh:
    doc = yaml.safe_load(fh)

errors: list[str] = []

if doc.get("kind") != "Cluster":
    errors.append(f"kind must be 'Cluster', got {doc.get('kind')!r}")
if doc.get("apiVersion") != "kind.x-k8s.io/v1alpha4":
    errors.append(
        f"apiVersion must be 'kind.x-k8s.io/v1alpha4', got {doc.get('apiVersion')!r}"
    )

nodes = doc.get("nodes") or []
if not nodes:
    errors.append("no nodes defined")

required = {"/sys/fs/bpf", "/sys/kernel/debug"}
roles = set()
for i, node in enumerate(nodes):
    roles.add(node.get("role"))
    mounts = node.get("extraMounts") or []
    host_paths = {m.get("hostPath") for m in mounts}
    missing = required - host_paths
    if missing:
        errors.append(
            f"node[{i}] ({node.get('role')}) missing eBPF mounts: {sorted(missing)}"
        )
    for m in mounts:
        if m.get("hostPath") in required and m.get("hostPath") != m.get("containerPath"):
            errors.append(
                f"node[{i}] mount {m.get('hostPath')} must map to the same containerPath"
            )

if "control-plane" not in roles:
    errors.append("no control-plane node defined")

if errors:
    print("  FAIL:")
    for e in errors:
        print(f"    - {e}")
    sys.exit(1)

print(f"  ok: {len(nodes)} node(s); bpffs and debugfs mounted on every node")
PY
	:
else
	fail=1
fi

echo "==> Makefile exposes the dev-cluster lifecycle targets"
help_output="$(make help)"
for t in dev-cluster dev-cluster-down; do
	if grep -qE "^  ${t} " <<<"$help_output"; then
		echo "  ok: '$t' listed"
	else
		echo "  FAIL: '$t' missing from 'make help'"
		fail=1
	fi
done

if [[ "$fail" -ne 0 ]]; then
	echo "dev-cluster config test FAILED"
	exit 1
fi

echo "dev-cluster config test PASSED"
