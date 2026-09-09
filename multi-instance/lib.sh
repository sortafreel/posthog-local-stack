#!/usr/bin/env bash
# Shared resolution for one extra PostHog instance. Sourced by build_env.sh, run.sh, teardown.sh.
#
# Inputs, first match wins:
#   name       CONDUCTOR_WORKSPACE_NAME  > $1              > POSTHOG_INSTANCE_NAME in <workspace>/.env
#   port base  CONDUCTOR_PORT            > $2              > POSTHOG_INSTANCE_PORT_BASE in <workspace>/.env
#   workspace  CONDUCTOR_WORKSPACE_PATH  > $PWD
#   main repo  CONDUCTOR_ROOT_PATH       > POSTHOG_DIR     > ~/Documents/Code/posthog
#
# Conductor hands each workspace ten ports (CONDUCTOR_PORT .. +9). One per host process:
#   +0 backend (granian)   +1 proxy (the URL you open)   +2 vite   +3 feature-flags
#   +4 hypercache-server   +5 embedding-worker          +6 llm-gateway   +7 mcp
#   +8 temporal-worker metrics   +9 debugpy
# Containers publish nothing; they are reached as <service>.<project>.orb.local (OrbStack DNS).

set -euo pipefail

CONFIGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLIM_DIR="$CONFIGS_DIR/../slim-stack"

WS_PATH="${CONDUCTOR_WORKSPACE_PATH:-$PWD}"
MAIN_REPO="${CONDUCTOR_ROOT_PATH:-${POSTHOG_DIR:-$HOME/Documents/Code/posthog}}"

_env_value() { # key -> value from <workspace>/.env, empty if absent
    [[ -f "$WS_PATH/.env" ]] || return 0
    sed -nE "s/^$1=(.*)$/\1/p" "$WS_PATH/.env" | tail -n 1
}

# Positional <name> <port-base> are only read by build_env.sh (LIB_ACCEPT_ARGS=1);
# run.sh and teardown.sh pass their own flags through to other commands.
_arg_name=""; _arg_port=""
if [[ "${LIB_ACCEPT_ARGS:-}" == "1" ]]; then _arg_name="${1:-}"; _arg_port="${2:-}"; fi
INSTANCE_NAME="${CONDUCTOR_WORKSPACE_NAME:-${_arg_name:-$(_env_value POSTHOG_INSTANCE_NAME)}}"
PORT_BASE="${CONDUCTOR_PORT:-${_arg_port:-$(_env_value POSTHOG_INSTANCE_PORT_BASE)}}"

if [[ -z "$INSTANCE_NAME" || -z "$PORT_BASE" ]]; then
    echo "usage: $(basename "${BASH_SOURCE[1]:-$0}") <instance-name> <port-base>" >&2
    echo "  (or run under Conductor, which sets CONDUCTOR_WORKSPACE_NAME and CONDUCTOR_PORT)" >&2
    exit 2
fi
if [[ ! "$PORT_BASE" =~ ^[0-9]+$ ]]; then
    echo "port base must be a number, got: $PORT_BASE" >&2
    exit 2
fi

# Compose project names must be lowercase alphanumerics, dashes, underscores.
SLUG="$(printf '%s' "$INSTANCE_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
PROJECT="posthog-$SLUG"
ORB="$PROJECT.orb.local"

BACKEND_PORT=$((PORT_BASE + 0))
PROXY_PORT=$((PORT_BASE + 1))
VITE_PORT=$((PORT_BASE + 2))
FLAGS_PORT=$((PORT_BASE + 3))
HYPERCACHE_PORT=$((PORT_BASE + 4))
EMBEDDING_PORT=$((PORT_BASE + 5))
GATEWAY_PORT=$((PORT_BASE + 6))
MCP_PORT=$((PORT_BASE + 7))
WORKER_METRICS_PORT=$((PORT_BASE + 8))
DEBUGPY_PORT=$((PORT_BASE + 9))

GENERATED_DIR="$WS_PATH/.posthog/.generated/multi"
OVERRIDE_FILE="$GENERATED_DIR/compose.override.yml"
PROCS_FILE="$GENERATED_DIR/mprocs.yaml"
COMPOSE_PROFILES_ARGS=(--profile temporal)

export CONFIGS_DIR SLIM_DIR WS_PATH MAIN_REPO INSTANCE_NAME PORT_BASE SLUG PROJECT ORB
export BACKEND_PORT PROXY_PORT VITE_PORT FLAGS_PORT HYPERCACHE_PORT EMBEDDING_PORT GATEWAY_PORT MCP_PORT WORKER_METRICS_PORT DEBUGPY_PORT
export GENERATED_DIR OVERRIDE_FILE PROCS_FILE

compose() { # run docker compose for this instance, from the workspace, with the override when present
    local files=(-f docker-compose.dev.yml -f docker-compose.profiles.yml)
    [[ -f "$OVERRIDE_FILE" ]] && files+=(-f "$OVERRIDE_FILE")
    (cd "$WS_PATH" && env -u COMPOSE_FILE docker compose -p "$PROJECT" "${files[@]}" "${COMPOSE_PROFILES_ARGS[@]}" "$@")
}
