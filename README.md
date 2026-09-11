# posthog_configs

Local-only tweaks to the PostHog dev stack. Nothing here is tracked in the posthog repo.

- `slim-stack/` — run a third of the dev stack for signals and reviewhog work. `apply.sh`, then restart `hogli start`.
- `multi-instance/` — run a second or third PostHog from another worktree, fully isolated. See its README's quick start.

Main checkout: `~/Documents/Code/posthog`. When something stops working after a pull, start with the README of the folder you use.
