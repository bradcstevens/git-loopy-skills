---
name: handoff
description: Launch a `/next` recommendation — its prompt and its sized runtime — as a background agent. Use when `/next` routes to `/implement`, or work moves to a fresh session that runs on its own.
---

If the `/next` skill output isn't the last part of the current conversation, run it before doing anything else.

Launch a background agent seeded with the runtime details and prompt output by the `/next` skill run that starts in the current working directory and returns immediately:

```bash
LOG="${TMPDIR:-/tmp}/copilot-<slug>.log"
PROMPT=$(cat <<'PROMPT_EOF'
<the prompt from /next, verbatim>
PROMPT_EOF
)
nohup copilot --yolo --no-ask-user -n "<descriptive name>" --model "<model>" --effort "<level>" --context "<default | long_context>" -p "$PROMPT" > "$LOG" 2>&1 &
```

Paste the `/next` prompt between the markers unaltered: `<<'PROMPT_EOF'` carries
its apostrophes and `#` through to the agent as one argument. `--no-ask-user`
keeps a background agent working on its own, because a question it raises reaches
nobody. The log lands outside the repository, clear of any worktree another agent
owns.

When `/next` returned `Fresh session in a new worktree`, still launch from the
current directory: its prompt opens with the `git worktree add` that moves the
agent before it writes.

Confirm the agent is alive before reporting it — a few seconds on, `$LOG` shows
its first tool calls. `nohup ... &` reports success whether the session started
or died on a rejected flag, so the log is the only evidence either way: an
`error:` line at the top of it means the flags never parsed, so correct them and
relaunch.

Always pass `-n`/`--name` with a descriptive name (e.g. `-n "Fix login bug"`) — a detached session has no terminal to identify it, so the name is how the user finds it again by `copilot --yolo --resume` and `/session`. Give the user that command:

```bash
copilot --yolo --resume="<descriptive name>"
```

Reference specs, plans, ADRs, issues, commits and diffs by path or URL, and spend the prompt on what those records lack — the constraints `/next` gathered from live state, such as the worktree to work in and the files it shares with work in flight.

Keep credentials, keys and personal data out of the prompt; it is stored with the session.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the prompt accordingly.