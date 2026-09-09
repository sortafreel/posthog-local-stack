#!/usr/bin/env bash
# Prepare one extra PostHog instance in a worktree (Conductor "setup" script).
# Usage: build_env.sh [<instance-name> <port-base>]   (Conductor supplies both via env)
# Idempotent: re-run after pulling, after `hogli nuke`, or when the generated files look stale.
LIB_ACCEPT_ARGS=1 source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" "$@"
cd "$WS_PATH"

echo "== instance '$INSTANCE_NAME' → compose project '$PROJECT', host ports $PORT_BASE-$((PORT_BASE + 9))"
echo "   workspace: $WS_PATH"
echo "   main repo: $MAIN_REPO"
mkdir -p "$GENERATED_DIR"

# 1. .env: Conductor copies it when '.env*' is in the repo's files-to-copy list; fall back to the main checkout.
if [[ ! -f .env ]]; then
    [[ -f "$MAIN_REPO/.env" ]] || { echo "no .env in workspace or in $MAIN_REPO" >&2; exit 1; }
    cp "$MAIN_REPO/.env" .env
    echo "   copied .env from $MAIN_REPO"
fi

# 2. Instance block in .env. flox exports .env on activation, and bin/start never overrides
#    a variable that is already set, so these win over .env.development / .env.services.
block=$(cat <<BLOCK
# >>> posthog_configs multi-instance ($INSTANCE_NAME) >>>
POSTHOG_INSTANCE_NAME=$INSTANCE_NAME
POSTHOG_INSTANCE_PORT_BASE=$PORT_BASE
COMPOSE_PROJECT_NAME=$PROJECT
PGHOST=db.$ORB
PGPORT=5432
DATABASE_URL=postgres://posthog:posthog@db.$ORB:5432/posthog
DUCKLAKE_RDS_HOST=db.$ORB
CLICKHOUSE_HOST=clickhouse.$ORB
CLICKHOUSE_LOGS_HOST=clickhouse.$ORB
REDIS_URL=redis://redis7.$ORB:6379/
FLAGS_REDIS_URL=redis://redis7.$ORB:6379/1
CDP_REDIS_HOST=redis7.$ORB
SESSION_RECORDING_API_REDIS_HOST=redis7.$ORB
COOKIELESS_REDIS_HOST=redis7.$ORB
KAFKA_HOSTS=kafka.$ORB:19092
OBJECT_STORAGE_ENDPOINT=http://objectstorage.$ORB:19000
OBJECT_STORAGE_PUBLIC_ENDPOINT=http://objectstorage.$ORB:19000
TEMPORAL_HOST=temporal.$ORB
HOST_BIND=127.0.0.1
SITE_URL=http://localhost:$PROXY_PORT
JS_URL=http://localhost:$VITE_PORT
EMBEDDING_API_URL=http://localhost:$EMBEDDING_PORT
LLM_GATEWAY_URL=http://localhost:$GATEWAY_PORT
LLM_GATEWAY_PORT=$GATEWAY_PORT
PROMETHEUS_METRICS_EXPORT_PORT=$WORKER_METRICS_PORT
# <<< posthog_configs multi-instance <<<
BLOCK
)
tmp=$(mktemp)
awk '/^# >>> posthog_configs multi-instance/{skip=1} !skip{print} /^# <<< posthog_configs multi-instance/{skip=0}' .env > "$tmp"
{ cat "$tmp"; [[ -s "$tmp" && "$(tail -c1 "$tmp")" != "" ]] && echo; printf '%s\n' "$block"; } > .env
rm -f "$tmp"
echo "   wrote instance block into .env"

# 3. MCP server env (gitignored, per worktree): same tokens as the main checkout, this instance's URLs.
mcp_env=services/mcp/.env
if [[ ! -f "$mcp_env" ]]; then
    if [[ -f "$MAIN_REPO/services/mcp/.env" ]]; then cp "$MAIN_REPO/services/mcp/.env" "$mcp_env"; else cp services/mcp/.env.example "$mcp_env"; fi
fi
tmp=$(mktemp)
grep -Ev '^(POSTHOG_API_BASE_URL|MCP_APPS_BASE_URL|POSTHOG_MCP_APPS_ANALYTICS_BASE_URL|POSTHOG_ANALYTICS_HOST)=' "$mcp_env" > "$tmp" || true
{ cat "$tmp"; printf '\nPOSTHOG_API_BASE_URL=http://localhost:%s\nMCP_APPS_BASE_URL=http://localhost:%s\nPOSTHOG_MCP_APPS_ANALYTICS_BASE_URL=http://localhost:%s\nPOSTHOG_ANALYTICS_HOST=http://localhost:%s\n' \
    "$PROXY_PORT" "$MCP_PORT" "$PROXY_PORT" "$PROXY_PORT"; } > "$mcp_env"
rm -f "$tmp"
echo "   wrote $mcp_env"

# 4. Toolchain for this worktree: flox activation creates the venv, installs node modules
#    (in the background) and builds phrocs. Then wait for node modules explicitly.
echo "== flox activate (first run takes minutes: venv, node modules, phrocs build) → $GENERATED_DIR/bootstrap.log"
if ! flox activate -- true > "$GENERATED_DIR/bootstrap.log" 2>&1; then
    tail -n 40 "$GENERATED_DIR/bootstrap.log"; echo "flox activate failed" >&2; exit 1
fi
flox activate -- bash -c 'pnpm install --frozen-lockfile --prefer-offline' >> "$GENERATED_DIR/bootstrap.log" 2>&1
flox activate -- bash -c '[[ -x tools/phrocs/dist/phrocs ]] || hogli phrocs:build' >> "$GENERATED_DIR/bootstrap.log" 2>&1

# 5. Instance files, derived from the main checkout's hogli config (the slim one). hogli
#    symlinks a worktree's .posthog/.generated/mprocs.yaml to the main checkout's, so never
#    run `hogli dev:*` inside a worktree expecting a separate config.
echo "== generating configs"
[[ -f "$MAIN_REPO/.posthog/.generated/mprocs.yaml" ]] || { echo "no hogli config in $MAIN_REPO; run ../slim-stack/apply.sh there first" >&2; exit 1; }
flox activate -- bash -c "python '$CONFIGS_DIR/gen_config.py'"

cat <<SUMMARY

== ready. Start with:  $CONFIGS_DIR/run.sh [-d]
   app        http://localhost:$PROXY_PORT      (proxy → backend :$BACKEND_PORT, vite :$VITE_PORT)
   temporal   http://temporal-ui.$ORB:8080
   containers <service>.$ORB (no host ports published)
   tear down  $CONFIGS_DIR/teardown.sh
SUMMARY
