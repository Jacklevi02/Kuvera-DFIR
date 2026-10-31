#!/usr/bin/env bash
#
# Verify a running Kuvera kind dev cluster meets the eBPF prerequisites
# (EPIC-1 / T1.3). Run after `make dev-cluster`:
#
#   scripts/dev-cluster-verify.sh
#
# This needs a live cluster (Docker + kind + kubectl) and is therefore NOT
# part of `make test`; it is the manual/e2e counterpart to the offline
# scripts/dev_cluster_config_test.sh. It asserts the two T1.3 acceptance
# checks:
#
#   1. kubectl get nodes returns Ready nodes.
#   2. /sys/kernel/btf/vmlinux is present on a node (BTF available for CO-RE).
#
# It does not load an eBPF program, so it cannot catch a runtime that blocks
# one, such as rootless Docker. See docs/DEVELOPMENT-SETUP.md.
#
# Environment overrides:
#   KIND_CLUSTER_NAME   cluster name      (default: kuvera-dev)
#   DEBUG_IMAGE         debug pod image   (default: ubuntu)
#   KUBECTL            kubectl binary    (default: kubectl)
#   BTF_PATH            file to check     (default: /sys/kernel/btf/vmlinux)
#   DEBUG_TIMEOUT       seconds to wait for the debug pod (default: 120)
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kuvera-dev}"
DEBUG_IMAGE="${DEBUG_IMAGE:-ubuntu}"
BTF_PATH="${BTF_PATH:-/sys/kernel/btf/vmlinux}"
DEBUG_TIMEOUT="${DEBUG_TIMEOUT:-120}"
ctx="kind-${KIND_CLUSTER_NAME}"

log() { printf '==> %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
	err "'$KUBECTL' not found on PATH"
	exit 1
fi

log "checking all nodes are Ready (context ${ctx})"
"$KUBECTL" --context "$ctx" wait --for=condition=Ready nodes --all --timeout=120s
"$KUBECTL" --context "$ctx" get nodes

node="$("$KUBECTL" --context "$ctx" get nodes \
	-o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$node" ]]; then
	err "could not determine a node name"
	exit 1
fi

log "checking BTF at ${BTF_PATH} on node/${node}"
# Unattached, `kubectl debug` exits 0 as soon as the pod is created, whatever
# the command inside it does. Attaching races a command this short, so wait for
# the pod to finish and read its phase instead.
debug_output="$("$KUBECTL" --context "$ctx" debug "node/${node}" \
	--image="$DEBUG_IMAGE" -- ls -l "$BTF_PATH" 2>&1)"
pod="$(grep -oE 'node-debugger-[a-z0-9.-]*[a-z0-9]' <<<"$debug_output" | head -n 1 || true)"
if [[ -z "$pod" ]]; then
	err "could not determine the debug pod name from: ${debug_output}"
	exit 1
fi
trap '"$KUBECTL" --context "$ctx" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT

phase=""
for ((i = 0; i < DEBUG_TIMEOUT; i++)); do
	# A failed call is retried; a cluster that stays unreachable hits the timeout.
	phase="$("$KUBECTL" --context "$ctx" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
	[[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
	sleep 1
done

case "$phase" in
Succeeded)
	"$KUBECTL" --context "$ctx" logs "$pod" || true
	;;
Failed)
	"$KUBECTL" --context "$ctx" logs "$pod" || true
	err "BTF check failed for ${BTF_PATH} on node/${node}; see the ls output above"
	exit 1
	;;
*)
	reason="$("$KUBECTL" --context "$ctx" get pod "$pod" \
		-o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
	err "debug pod ${pod} did not finish within ${DEBUG_TIMEOUT}s (phase: ${phase:-unknown}, reason: ${reason:-unknown})"
	exit 1
	;;
esac

log "dev cluster '${KIND_CLUSTER_NAME}' satisfies the eBPF prerequisites"
