#!/usr/bin/env bash
# Open one Ghostty window per devbox, two tabs each, every tab ssh'd into ~/posthog.
# Warms every devbox first (Coder starts a stopped one) and opens nothing until all answer.
#
#   open-devboxes              # dev1 dev2 dev3
#   open-devboxes dev1 dev2    # subset
set -euo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/Documents/Code/posthog}"
REMOTE_DIR='~/posthog'
TABS_PER_WINDOW=2

devboxes=("$@")
if [ ${#devboxes[@]} -eq 0 ]; then
  devboxes=(dev1 dev2 dev3)
fi

# --- warm-up: hogli gives readable Tailscale/Coder errors, raw ssh just hangs ---
# "dev1" is a hogli label; the ssh host alias needs the Coder workspace name
# (devbox-<user>-dev1), so the warm-up command prints it for the tabs to use.
log_dir=$(mktemp -d)
trap 'rm -rf "$log_dir"' EXIT

pids=()
for box in "${devboxes[@]}"; do
  echo "waiting for $box..."
  # flox only sources its [profile] venv activation for interactive shells,
  # so a fresh terminal needs the venv sourced by hand before hogli exists.
  (
    cd "$POSTHOG_DIR" && flox activate -- bash -c \
      'source "$FLOX_ENV_CACHE/venv/bin/activate" && hogli devbox:exec -n "$1" -- printenv CODER_WORKSPACE_NAME' _ "$box"
  ) >"$log_dir/$box.name" 2>"$log_dir/$box.log" &
  pids+=($!)
done

failed=()
names=()
for i in "${!devboxes[@]}"; do
  box=${devboxes[$i]}
  name=""
  if wait "${pids[$i]}"; then
    name=$(tr -d '[:space:]' <"$log_dir/$box.name")
  fi
  if [ -n "$name" ]; then
    echo "$box ready ($name)"
    names+=("$name")
  else
    echo "$box FAILED:"
    sed 's/^/  /' "$log_dir/$box.log" "$log_dir/$box.name"
    failed+=("$box")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "not opening anything: ${failed[*]} not reachable" >&2
  exit 1
fi

# --- open: one AppleScript call, one window per devbox, TABS_PER_WINDOW tabs each ---
# Each tab is a local shell in POSTHOG_DIR that immediately runs the ssh line,
# so a dropped connection leaves a local prompt instead of a dead tab.
ssh_line_for() {
  printf "ssh -t coder.%s 'cd %s && exec \$SHELL -l'" "$1" "$REMOTE_DIR"
}

script="tell application \"Ghostty\""$'\n'"  activate"$'\n'
for name in "${names[@]}"; do
  line=$(ssh_line_for "$name")
  for ((t = 1; t <= TABS_PER_WINDOW; t++)); do
    script+="  set cfg to new surface configuration"$'\n'
    script+="  set initial working directory of cfg to \"$POSTHOG_DIR\""$'\n'
    script+="  set initial input of cfg to \"$line\" & return"$'\n'
    if [ "$t" -eq 1 ]; then
      script+="  set win to new window with configuration cfg"$'\n'
    else
      script+="  new tab in win with configuration cfg"$'\n'
    fi
  done
done
script+="end tell"$'\n'

osascript <<<"$script" >/dev/null
echo "opened ${#devboxes[@]} Ghostty windows with $TABS_PER_WINDOW tabs each"
