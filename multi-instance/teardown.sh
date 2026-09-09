#!/usr/bin/env bash
# Remove an extra instance's containers and volumes (Conductor "archive" script).
# Stop phrocs first if it is still running in the workspace.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
echo "== removing compose project '$PROJECT' (containers + volumes)"
compose down -v --remove-orphans
rm -rf "$GENERATED_DIR"
echo "   done. The workspace's .env still carries the instance block; build_env.sh rewrites it."
