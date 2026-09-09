#!/usr/bin/env bash
# Start an extra instance (Conductor "run" script). Flags go to bin/start, e.g. `run.sh -d`.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$WS_PATH"
[[ -f "$PROCS_FILE" ]] || { echo "no generated config for this workspace; run build_env.sh first" >&2; exit 1; }
# Zombie and git checks are for the main checkout; the port check would offer to tear the
# main stack down (see shim/hogli). Everything else in bin/start runs unchanged.
exec flox activate -- env \
    HOGLI_SKIP_ZOMBIE_CHECK=1 HOGLI_SKIP_GIT_CHECK=1 \
    POSTHOG_REAL_HOGLI="$WS_PATH/bin/hogli" PATH="$CONFIGS_DIR/shim:$PATH" \
    bin/start "$@" --custom "$PROCS_FILE"
