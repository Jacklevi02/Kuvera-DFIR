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
# Environment overrides:
#   KIND_CLUSTER_NAME   cluster name      (default: kuvera-dev)
#   DEBUG_IMAGE         debug pod image   (default: ubuntu)
#   KUBECTL            kubectl binary    (default: kubectl)
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kuvera-dev}"
DEBUG_IMAGE="${DEBUG_IMAGE:-ubuntu}"
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

log "checking BTF at /sys/kernel/btf/vmlinux on node/${node}"
"$KUBECTL" --context "$ctx" debug "node/${node}" \
	--image="$DEBUG_IMAGE" -q -- ls -l /sys/kernel/btf/vmlinux

log "dev cluster '${KIND_CLUSTER_NAME}' satisfies the eBPF prerequisites"
