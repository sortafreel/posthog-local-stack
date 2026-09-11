# Slim dev stack for signals (self-driving) and reviewhog

A local-only `hogli` config that starts about a third of the PostHog dev stack.
It lives outside the posthog repo on purpose: `hogli` stores its config in the gitignored
`.posthog/.generated/mprocs.yaml`, and this repo is the source of truth to re-apply from.

## Use

```bash
./apply.sh      # writes the config; then restart `hogli start`
./rollback.sh   # restores the previous 17-intent config
```

Set `POSTHOG_DIR` if the checkout is not `~/Documents/Code/posthog`.

## What still runs

Docker (15 containers): the 11 base ones (Postgres, ClickHouse, Kafka, ZooKeeper, Redis x3,
object storage, proxy, feature-flags, kafka-init) plus the `temporal` profile
(Temporal, its UI, admin tools, and Elasticsearch).

Host processes (12): backend, frontend, celery-worker, celery-beat, temporal-worker, embedding-worker,
llm-gateway, mcp, feature-flags, hypercache-server, ngrok (exits at once unless `SITE_URL` is an ngrok URL),
and the docker-compose log tail. Plus 5 one-shots: 4 migrations and ensure-local-setup.

Why each one stays:

- Temporal + worker: every signals and reviewhog workflow.
- Celery worker + beat: closing a PR when a report is dismissed, scout Slack delivery,
  refund sync, self-driving quota refresh, task emails and pushes.
- ClickHouse + Kafka + embedding-worker: signals are stored as embeddings; writes go through Kafka.
  The worker also serves the embedding HTTP call used during grouping. Needs `OPENAI_API_KEY` in `.env`.
- llm-gateway: `call_llm` and reviewhog's one-shot LLM calls default to `localhost:3308` in DEBUG.
- mcp: sandbox agents fetch perspectives and scout skills over MCP.
- feature-flags + hypercache-server: the dev proxy routes `/flags` and `/array/*` to these host
  processes, and the inbox and code-review scenes are flag-gated.
- object storage + Redis: signal batches, task-run logs, quota gates, Slack markers.

## What was dropped and why

- Personhog (6 processes) and etcd, the ingestion servers, capture, nodejs, property-defs-rs,
  property-vals-rs, cymbal x3, livestream, webhook-s3-sink, capture-ai, dagster: only needed
  when events or errors are ingested for real. Signals are fed by hand instead (see below).
- Docker profiles dynamodb, opensearch, browserless, duckgres, observability, replay, dev_tools.
- The MCP UI-apps watch build (kept as a manual unit; the server does not need it).
- agent-proxy and the Electron desktop app (they come with the borrowed `desktop` intent).

## What you lose

- No real signal sources. Feed the pipeline with `emit_signals_from_fixture`,
  `emit_signals_from_llm`, `ingest_signals_json`, `seed_inbox_data`. For scout data use
  `generate_demo_data` (writes straight to ClickHouse, no ingestion needed).
- No Kafka UI, Flower, maildev, webhook tester.

## Still required outside the stack

- Your own ngrok session with the three tunnels: django `:8010`, gateway `:3308`, mcp `:8787`.
- Modal tokens and `SANDBOX_LLM_GATEWAY_URL` in `.env` (sandboxes run on Modal).

## How the config is built

There is no signals or reviewhog intent in `devenv/intent-map.yaml`, and every product intent
that brings Temporal also brings `event_ingestion` (which drags personhog and etcd in).
The `desktop` intent is the one exception: Temporal + llm-gateway + agent-proxy + the app.
So `apply.sh` borrows `desktop` + `mcp`, includes `embedding-worker`, and excludes the
desktop-only units plus the hogli "always required" floor that neither product uses.
`hogli dev:explain` will say "needed for desktop"; that is cosmetic.

## When it stops working (notes for agents)

`hogli start` regenerates the file on every start from the saved selection (intents,
includes, excludes), so the slim config survives restarts and pulls. It changes only when
a `hogli dev:*` command overwrites the selection, or when upstream changes what the saved
intents resolve to. Check in this order:

1. `hogli dev:explain` in the posthog repo. Compare with "What still runs" above.
2. `devenv/intent-map.yaml`: does `desktop` still map to `temporal_workflows` without
   `event_ingestion`? If not, pick another intent with the same shape or add `--include`s.
3. `bin/mprocs.yaml`: were any excluded or included units renamed? Update `apply.sh`.
4. Did signals or reviewhog start needing a new service? Grep the product backend for the
   dependency and add an `--include`. Docker profiles only come from capabilities, not from
   `--include`, so a new container needs an intent that carries its profile.
5. Re-run `./apply.sh`, restart `hogli start`.

Known remaining weight: Elasticsearch (Temporal is wired with `ENABLE_ES=true` in
`docker-compose.base.yml`; dropping it needs a repo change) and ClickHouse.

## Next step (not done)

Run several local PostHog instances at once and add a `build_env` script for Conductor.
Ports will clash. Start at `tools/hogli-commands/hogli_commands/devenv/generator.py`:
the docker project name is pinned to `posthog` so all worktrees share one stack, and it
honors `COMPOSE_PROJECT_NAME`.
