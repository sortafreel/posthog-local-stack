#!/usr/bin/env bash
# Apply the slim dev stack for signals (self-driving) and reviewhog work.
# Re-run this after `hogli dev:setup`, `hogli nuke`, or when the stack grew back.
set -euo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/Documents/Code/posthog}"
cd "$POSTHOG_DIR"

# Intents: `desktop` is the only intent that brings Temporal without the
# ingestion pipeline (and personhog + etcd behind it). `mcp` brings the MCP server.
# Excludes: the desktop-only units, plus the hogli "always required" floor
# that neither product uses.
hogli dev:apply desktop mcp \
    --include embedding-worker \
    --exclude desktop \
    --exclude agent-proxy \
    --exclude capture \
    --exclude nodejs \
    --exclude property-defs-rs \
    --exclude celery-worker \
    --exclude celery-beat \
    --exclude personhog-replica \
    --exclude personhog-router \
    --skip-autostart mcp-ui-apps

echo
echo "Resolved stack:"
hogli dev:explain
