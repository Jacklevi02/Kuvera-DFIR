#!/usr/bin/env bash
#
# Manage the Kuvera local kind dev cluster (EPIC-1 / T1.3).
#
# Usage:
#   scripts/dev-cluster.sh up     # create the cluster (idempotent)
#   scripts/dev-cluster.sh down   # delete the cluster (idempotent)
#
# `up` is idempotent: if the named cluster already exists it just waits for
# the nodes to be Ready and returns. Set KIND_RECREATE=1 to delete and rebuild
# (e.g. after changing deploy/dev/kind-config.yaml). `down` is a no-op when the
# cluster is absent.
#
# Environment overrides:
#   KIND_CLUSTER_NAME   cluster name                 (default: kuvera-dev)
#   KIND_CONFIG         path to the kind config      (default: deploy/dev/kind-config.yaml)
#   KIND_NODE_IMAGE     pinned kindest/node image    (default: kind's built-in)
#   KIND_RECREATE       non-empty => rebuild on `up` (default: unset)
#   KIND               kind binary                   (default: kind)
#   KUBECTL            kubectl binary                (default: kubectl)
#   KIND_EXPERIMENTAL_PROVIDER
#                       container runtime kind uses: docker | podman | nerdctl
#                       (default: unset => kind auto-detects)
#
# Docker and Podman are both supported. See docs/DEVELOPMENT-SETUP.md for
# runtime install steps and the eBPF host requirements.
set -euo pipefail

KIND="${KIND:-kind}"
KUBECTL="${KUBECTL:-kubectl}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kuvera-dev}"
KIND_CONFIG="${KIND_CONFIG:-deploy/dev/kind-config.yaml}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-}"
KIND_RECREATE="${KIND_RECREATE:-}"
KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-}"
export KIND_EXPERIMENTAL_PROVIDER

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

log() { printf '==> %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

require() {
	local bin="$1"
	if ! command -v "$bin" >/dev/null 2>&1; then
		err "'$bin' not found on PATH; install it before running the dev cluster"
		exit 1
	fi
}

cluster_exists() {
	"$KIND" get clusters 2>/dev/null | grep -qxF "$KIND_CLUSTER_NAME"
}

wait_ready() {
	log "waiting for nodes to report Ready"
	"$KUBECTL" --context "kind-${KIND_CLUSTER_NAME}" \
		wait --for=condition=Ready nodes --all --timeout=120s
}

# kind needs a container runtime to host the nodes. Check for one up front so a
# missing runtime produces an actionable message instead of a provider error
# from deep inside kind.
require_runtime() {
	local wanted="$KIND_EXPERIMENTAL_PROVIDER"
	if [[ -n "$wanted" ]]; then
		if ! command -v "$wanted" >/dev/null 2>&1; then
			err "KIND_EXPERIMENTAL_PROVIDER='${wanted}' but '${wanted}' is not on PATH"
			err "see docs/DEVELOPMENT-SETUP.md to install a container runtime"
			exit 1
		fi
		log "using container runtime '${wanted}'"
		return 0
	fi

	local found=()
	local candidate
	for candidate in docker podman nerdctl; do
		if command -v "$candidate" >/dev/null 2>&1; then
			found+=("$candidate")
		fi
	done

	if [[ "${#found[@]}" -eq 0 ]]; then
		err "no container runtime found (looked for docker, podman, nerdctl)"
		err "see docs/DEVELOPMENT-SETUP.md to install one"
		exit 1
	fi

	if [[ "${#found[@]}" -gt 1 ]]; then
		log "multiple container runtimes available (${found[*]}); letting kind auto-detect"
		log "set KIND_EXPERIMENTAL_PROVIDER to choose explicitly"
	fi
}

up() {
	require "$KIND"
	require "$KUBECTL"
	require_runtime
	if [[ ! -f "$KIND_CONFIG" ]]; then
		err "kind config not found at ${KIND_CONFIG}"
		exit 1
	fi

	if cluster_exists; then
		if [[ -n "$KIND_RECREATE" ]]; then
			log "cluster '${KIND_CLUSTER_NAME}' exists and KIND_RECREATE is set; deleting first"
			"$KIND" delete cluster --name "$KIND_CLUSTER_NAME"
		else
			log "cluster '${KIND_CLUSTER_NAME}' already exists; ensuring it is Ready (set KIND_RECREATE=1 to rebuild)"
			wait_ready
			log "cluster '${KIND_CLUSTER_NAME}' is ready"
			return 0
		fi
	fi

	local args=(create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG" --wait 120s)
	if [[ -n "$KIND_NODE_IMAGE" ]]; then
		args+=(--image "$KIND_NODE_IMAGE")
	fi

	log "creating kind cluster '${KIND_CLUSTER_NAME}'"
	"$KIND" "${args[@]}"
	wait_ready
	log "cluster '${KIND_CLUSTER_NAME}' is ready (run scripts/dev-cluster-verify.sh to check eBPF prerequisites)"
}

down() {
	require "$KIND"
	if cluster_exists; then
		log "deleting kind cluster '${KIND_CLUSTER_NAME}'"
		"$KIND" delete cluster --name "$KIND_CLUSTER_NAME"
	else
		log "cluster '${KIND_CLUSTER_NAME}' does not exist; nothing to do"
	fi
}

main() {
	local cmd="${1:-up}"
	case "$cmd" in
	up) up ;;
	down) down ;;
	*)
		err "unknown command: '${cmd}' (expected 'up' or 'down')"
		exit 2
		;;
	esac
}

main "$@"
