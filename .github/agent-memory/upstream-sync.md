# Agent Memory: Upstream sync

Standing feedback for future `Agent: upstream sync` runs. This is the human-on-the-loop steering
channel: it is loaded into the actuator on every run, after the controller, so edits here change
future behavior, not just one pull request. Keep durable guidance only, not one-off instructions or
single-run logs.

Scope, labels and limits live in `.github/upstream-sync.json`. How a synced file is written lives in
`.github/skills/upstream-sync/references/sync-rules.md`. Keep each rule in one place.

## Guidance

- Other agents work this repository's tickets from local worktrees while the loop runs. If a branch
  or pull request for your ticket appears while you work, stop and report it rather than race it.
