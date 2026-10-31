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
#   4. scripts/dev-cluster.sh pins kind to Docker.
#   5. scripts/dev-cluster-verify.sh fails when the BTF check inside the debug
#      pod fails, using a stub kubectl.
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
# uv supplies the interpreter and PyYAML; see docs/TOOLCHAIN.md.
if ! command -v uv >/dev/null 2>&1; then
	echo "  FAIL: uv not found (see docs/DEVELOPMENT-SETUP.md)"
	exit 1
fi
if uv run --quiet --with pyyaml python3 - "$config" <<'PY'; then
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

echo "==> dev-cluster.sh pins kind to Docker"
if grep -qx 'export KIND_EXPERIMENTAL_PROVIDER=docker' scripts/dev-cluster.sh; then
	echo "  ok: provider fixed to docker"
else
	echo "  FAIL: scripts/dev-cluster.sh does not pin KIND_EXPERIMENTAL_PROVIDER=docker"
	fail=1
fi

echo "==> dev-cluster-verify.sh reports the debug pod's result"
stub_dir="$(mktemp -d)"
trap 'rm -rf "$stub_dir"' EXIT
cat >"$stub_dir/kubectl" <<'STUB'
#!/usr/bin/env bash
# Stands in for kubectl: args are `--context <ctx> <subcommand> ...`.
case "$3" in
get)
	if [[ "$4" == "nodes" ]]; then
		echo stub-node
	elif [[ "$7" == *waiting.reason* ]]; then
		echo "$STUB_REASON"
	elif [[ -n "$STUB_FLAKY" && ! -e "$STUB_FLAKY" ]]; then
		touch "$STUB_FLAKY" # fail the first phase check only
		exit 1
	else
		echo "$STUB_PHASE"
	fi
	;;
debug)
	echo "Creating debugging pod node-debugger-stub-node-abc12 with container debugger on node stub-node."
	;;
delete)
	touch "$STUB_DELETED"
	;;
esac
STUB
chmod +x "$stub_dir/kubectl"

# expect_verify <description> <phase> <expected exit: 0 or 1> <expected output> [reason] [flaky]
expect_verify() {
	local status=0 output flaky="" timeout=1
	if [[ -n "${6:-}" ]]; then
		flaky="$stub_dir/flaky"
		timeout=2
	fi
	rm -f "$stub_dir/deleted" "$stub_dir/flaky"
	output="$(KUBECTL="$stub_dir/kubectl" STUB_PHASE="$2" STUB_REASON="${5:-}" STUB_FLAKY="$flaky" \
		STUB_DELETED="$stub_dir/deleted" DEBUG_TIMEOUT="$timeout" \
		bash scripts/dev-cluster-verify.sh 2>&1)" || status=$?
	if [[ "$status" -ne "$3" ]]; then
		echo "  FAIL: $1: exited $status, expected $3"
		fail=1
	elif ! grep -qF -- "$4" <<<"$output"; then
		echo "  FAIL: $1: output missing '$4'"
		fail=1
	elif [[ ! -e "$stub_dir/deleted" ]]; then
		echo "  FAIL: $1: debug pod not deleted"
		fail=1
	else
		echo "  ok: $1"
	fi
}

expect_verify "file present passes" Succeeded 0 "satisfies the eBPF prerequisites"
expect_verify "file missing fails" Failed 1 "BTF check failed"
expect_verify "pod never finishing fails" Running 1 "did not finish within 1s"
expect_verify "image pull failure reports the reason" Pending 1 \
	"did not finish within 1s (phase: Pending, reason: ImagePullBackOff)" ImagePullBackOff
expect_verify "one failed status call is retried" Succeeded 0 \
	"satisfies the eBPF prerequisites" "" flaky

if [[ "$fail" -ne 0 ]]; then
	echo "dev-cluster config test FAILED"
	exit 1
fi

echo "dev-cluster config test PASSED"
