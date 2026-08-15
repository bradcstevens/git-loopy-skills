---
name: handoff
description: Pass the runtime and prompt output of a `/next` skill run to a fresh background agent that picks up the work immediately.
disable-model-invocation: true
---

If the `/next` skill output isnt the last part of the current conversation, run it before doing anything else. 

Launch a background agent seeded with the runtime details and prompt output by the `/next` skill run that starts in the current working directory and returns immediately; the user manages it with `copilot --yolo --resume="<descriptive name>"`:

```bash
nohup copilot --yolo -n "<descriptive name>" --model "<model>" --effort "<level>" --context "<default | long_context>" -p "<prompt"
```

Always pass `-n`/`--name` with a descriptive name (e.g. `-n "Fix login bug"`) — a detached session has no terminal to identify it, so the name is how the user finds it again by `copilot --yolo --resume` and `/session`.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information — the summary becomes the agent's prompt.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the summary accordingly.