#!/usr/bin/env bash
# Restore the previous "almost everything" config (17 intents, 4 excludes).
set -euo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/Documents/Code/posthog}"
cd "$POSTHOG_DIR"

hogli dev:apply \
    product_analytics error_tracking session_replay feature_flags experiments \
    llm_analytics web_analytics surveys data_warehouse pipelines ai_features \
    logs metrics tracing debug_tools mcp endpoints \
    --exclude dagster \
    --exclude personhog-replica \
    --exclude personhog-router \
    --exclude recording-rasterizer

echo
hogli dev:explain
