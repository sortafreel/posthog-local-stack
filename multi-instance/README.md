# Extra PostHog instances on one Mac

Run a second (or third) PostHog dev stack from another worktree, next to the main one,
without touching any tracked file. Built for Conductor workspaces, works from any worktree.

Each extra instance is its own docker compose project (own Postgres, ClickHouse, Kafka,
Redis, object storage, Temporal, Elasticsearch) plus its own host processes. Nothing is
shared with the main instance, so migrations, data, and tests never collide.

## Use

```bash
# once per workspace (Conductor "setup" script)
multi-instance/build_env.sh <name> <port-base>     # Conductor sets both via env
# start (Conductor "run" script), same flags as `hogli start`
multi-instance/run.sh [-d]
# remove containers + volumes (Conductor "archive" script)
multi-instance/teardown.sh
```

Open `http://localhost:<port-base + 1>`. Temporal UI: `http://temporal-ui.posthog-<name>.orb.local:8080`.

The stack is the slim one from `../slim-stack` (Temporal, LLM gateway, MCP, embeddings,
flags; no ingestion, no Celery). Same limits apply, plus: ngrok and Modal sandboxes only
work on the main instance.

## Conductor setup (GUI, once)

Add the repo with root `~/Documents/Code/posthog`. Files to copy into new workspaces:
`.env`, `.env.local`, `services/mcp/.env`. Scripts:

| Conductor field | value |
| --- | --- |
| setup | `~/Documents/Code/posthog_configs/multi-instance/build_env.sh` |
| run | `~/Documents/Code/posthog_configs/multi-instance/run.sh` |
| archive | `~/Documents/Code/posthog_configs/multi-instance/teardown.sh` |

Conductor exports `CONDUCTOR_WORKSPACE_NAME`, `CONDUCTOR_WORKSPACE_PATH`,
`CONDUCTOR_ROOT_PATH`, and `CONDUCTOR_PORT` (a block of ten ports). The scripts read those
first and fall back to arguments and to the block they wrote into the workspace `.env`.

## Ports

Ten host ports from the port base: +0 backend, +1 proxy (the URL you open), +2 Vite,
+3 feature-flags, +4 hypercache-server, +5 embedding-worker, +6 LLM gateway, +7 MCP,
+8 Temporal worker metrics, +9 debugpy.

Containers publish no host ports. Host processes reach them by OrbStack DNS,
`<service>.posthog-<name>.orb.local`, on the native port. Two services advertise their
own address to clients and need the override to advertise the OrbStack name:

- Kafka: the host connects to the external listener on 19092, which the override makes
  Kafka advertise under its OrbStack name (the internal listener keeps `kafka:9092`).
- ClickHouse: the migration runner and everything on `posthog.clickhouse.cluster` read
  host names from `system.clusters` and connect to them from the Mac. The upstream name
  is the bare `clickhouse`, which `/etc/hosts` maps to 127.0.0.1, i.e. the main instance.
  The override mounts a copy of `config.d/default.xml` with the OrbStack name and adds a
  network alias so the name also resolves to the container's own IP inside the network
  (ClickHouse must recognise itself to execute `ON CLUSTER` DDL). Without this, a fresh
  instance's ClickHouse migrations run against the main instance. That happened once:
  it re-ran old migrations on main and resurrected Kafka tables that later migrations had
  dropped.

## How it stays out of the repo

- The instance settings live in a marked block at the end of the workspace `.env`
  (gitignored). flox exports `.env` on activation and `bin/start` never overrides a
  variable that is already set, so the block beats `.env.development` and `.env.services`.
- `bin/start --custom <file>` runs phrocs with our generated config and skips
  `hogli dev:generate`. The file lives in `.posthog/.generated/multi/` (gitignored).
- Compose gets a third `-f` file: it resets `ports:` on every service, republishes only
  the proxy, rewrites the proxy's Caddyfile (an env var in compose), and patches Kafka's
  advertised address. `gen_config.py` derives it from `docker compose config`, so it
  follows upstream compose changes.
- `bin/start` runs `hogli doctor:ports`, which offers to tear down "foreign" stacks; for
  an extra instance the main stack is foreign. `shim/hogli` swallows that one command.

## Copied lines that can drift

`gen_config.py` replaces four shells because the repo scripts hardcode ports:

- backend: the granian command from `bin/start-backend` (`--port`, debugpy port)
- migrate-clickhouse: upstream's shell plus a wait for `manage.py migrate --check`. On a
  fresh database the Postgres migration runs for minutes and the ClickHouse runner's own
  Postgres connection dies if the two overlap.
- frontend: the Vite command from `frontend/package.json` `start-vite` (`--port`)
- feature-flags, hypercache-server, embedding-worker: the env block from
  `bin/start-rust-service` (`ADDRESS` / `BIND_PORT`)
- temporal-worker: same as upstream minus `bin/check_ducklake_up`

When one of those upstream files changes, compare and update `gen_config.py`. The
generator fails loudly if the Caddyfile upstreams or the Kafka flags it patches disappear.

Known quirks:

- Vite proxies `/static` to `localhost:8000` (hardcoded in `vite.config.mts`), so assets
  requested from the Vite origin come from the main instance. Harmless in practice.
- hogli symlinks a worktree's `.posthog/.generated/mprocs.yaml` to the main checkout's.
  `gen_config.py` therefore reads the main checkout's config as its base and never runs
  `hogli dev:*` inside the worktree. Keep the main checkout on the slim config.
- Anything that falls back to a bare docker alias (`db`, `clickhouse`, `kafka`, `redis7`,
  `objectstorage`, `temporal`) from the Mac reaches the main instance, because `/etc/hosts`
  maps those names to 127.0.0.1. The instance block in `.env` covers every setting the
  slim stack reads; a new setting with such a default needs adding there.

## Candidate upstream knobs (small PR, later)

Env defaults that would delete the copied shells: `VITE_PORT` in `bin/start-frontend` and
`vite.config.mts`, `ADDRESS`/`BIND_PORT` defaults in `bin/start-rust-service`,
`CLICKHOUSE_HTTP_PORT` in `posthog/settings/data_stores.py`, a skip flag for
`hogli doctor:ports`, and a Vite `/static` proxy target env.

## Proving isolation after a change

```bash
# from the workspace, ClickHouse must advertise its own name and keep DDL to itself
docker exec posthog-<name>-clickhouse-1 clickhouse-client -q "select host_name from system.clusters where cluster='posthog'"
docker exec posthog-clickhouse-1 clickhouse-client -q "select count() from system.query_log where event_time > now() - interval 10 minute and query_kind in ('Create','Drop','Alter')"
```

The first must print `clickhouse.posthog-<name>.orb.local`; the second, run on the main
instance right after the extra instance migrated, must stay at 0.

## When it breaks

1. `run.sh` refuses to start: run `build_env.sh` again (it is idempotent).
2. Containers up but the app cannot reach them: `nc -z db.posthog-<name>.orb.local 5432`.
   OrbStack DNS must resolve; Docker Desktop does not provide it.
3. Kafka producers hang or write to the wrong stack: check the override's kafka
   `command` still carries `external://kafka.posthog-<name>.orb.local:19092`.
4. A host process dies on a port clash: `lsof -nP -iTCP:<port> -sTCP:LISTEN`; the ten
   ports must be free before `run.sh`.
5. Slim base config missing units: see `../slim-stack/README.md`.
