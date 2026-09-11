#!/usr/bin/env bash
# Start an extra instance (Conductor "run" script). Flags go to bin/start, e.g. `run.sh -d`.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$WS_PATH"
[[ -f "$PROCS_FILE" ]] || { echo "no generated config for this workspace; run build_env.sh first" >&2; exit 1; }

# Export the workspace .env ourselves. flox does it on activation, but a shell that was
# activated earlier (direnv, or `flox activate` before build_env.sh ran) keeps its old
# environment, and flox does not re-run the hook for an environment that is already
# active. Without the instance block every process falls back to the docker aliases in
# /etc/hosts, which are the main instance.
set -o allexport
# shellcheck disable=SC1091
source "$WS_PATH/.env"
set +o allexport

# Refuse to start unless the environment really points at this instance's containers.
[[ "${DATABASE_URL:-}" == *"db.$ORB:"* && "${CLICKHOUSE_HOST:-}" == "clickhouse.$ORB" ]] || {
    echo "DATABASE_URL / CLICKHOUSE_HOST do not point at $ORB; re-run build_env.sh" >&2; exit 1; }
[[ "${COMPOSE_PROJECT_NAME:-}" == "$PROJECT" ]] || { echo "COMPOSE_PROJECT_NAME is not $PROJECT" >&2; exit 1; }

# Zombie and git checks are for the main checkout; the port check would offer to tear the
# main stack down (see shim/hogli). Everything else in bin/start runs unchanged.
exec flox activate -d "$WS_PATH" -- env \
    HOGLI_SKIP_ZOMBIE_CHECK=1 HOGLI_SKIP_GIT_CHECK=1 \
    POSTHOG_REAL_HOGLI="$WS_PATH/bin/hogli" PATH="$CONFIGS_DIR/shim:$PATH" \
    bin/start "$@" --custom "$PROCS_FILE"
