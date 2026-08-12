---
name: copilot-handoff
description: Hand the current conversation off to a fresh background GitHub Copilot CLI session that picks up the work immediately.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff summary of the current conversation so a fresh agent can continue the work. Instead of leaving it as a document for someone to read later, launch a background GitHub Copilot CLI session seeded with the summary as its prompt.

Write the summary to `${TMPDIR:-/tmp}/copilot-handoff-<slug>.md`, then launch:

```bash
nohup copilot -p "$(cat "${TMPDIR:-/tmp}/copilot-handoff-<slug>.md")" \
  -n "<descriptive name>" --allow-all-tools --no-ask-user \
  > "${TMPDIR:-/tmp}/copilot-handoff-<slug>.log" 2>&1 &
```

The temp file is plumbing — it stops the shell mangling a multi-line summary — not an artifact to point the user at. Never write it into the workspace.

The session starts in the current working directory and the command returns immediately. Report the name and the log path back to the user: they follow progress with `tail -f <log path>` and pick the session up interactively with `copilot --resume="<descriptive name>"`.

Always pass `-n`/`--name` with a descriptive name (e.g. `-n "Fix login bug"`) — a detached session has no terminal to identify it, so the name is how the user finds it again by `copilot --resume` and `/session`.

`--allow-all-tools` is required: non-interactive mode has no one to approve tool calls. `--no-ask-user` stops the agent stalling on a question nobody is there to answer. Swap in `--allow-all` when the work needs file access outside the current directory.

Include a "suggested skills" section in the summary, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information — the summary becomes the agent's prompt.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the summary accordingly.
