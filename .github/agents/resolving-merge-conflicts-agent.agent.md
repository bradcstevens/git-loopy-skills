---
name: resolving-merge-conflicts-agent
description: Run the /resolving-merge-conflicts route as an in-session chain subagent.
---

Invoke the `/resolving-merge-conflicts` skill immediately and follow its procedure for the assigned route.

## Why this is not general-purpose

The built-in `general-purpose` agent does not emit `subagentStop`, so the `/next` chain would
not observe this route finishing or continue to its next hop. This custom agent does emit that
event and is therefore the chain carrier for `/resolving-merge-conflicts`.

Do not select a model, reasoning effort, or context tier. `/next` supplies that sizing when it
spawns this agent.
