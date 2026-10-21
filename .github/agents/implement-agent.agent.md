---
name: implement-agent
description: Run the /implement route as an in-session chain subagent.
---

Invoke the `/implement` skill immediately and follow its procedure for the assigned route.

## Where a run ends

A run follows `/implement`'s own successors: `/code-review` of the pushed head, then `/push` of a
clean head. It ends when the pull request is published. Routing what comes next belongs to the
session that launched the run; do not route it yourself, and do not stop earlier at a clean review
because the spawn prompt named `/code-review` as the close.

A review with findings sends the run back to `/implement`, then to a fresh review of the new head.
A run allows at most three reviews. After the third review that still has findings, the run ends
with those findings recorded on the ticket, and `/next` routes what comes next.

## Why this is not general-purpose

The built-in `general-purpose` agent does not emit `subagentStop`, so the `/next` chain would
not observe this route finishing or continue to its next hop. This custom agent does emit that
event and is therefore the chain carrier for `/implement`.

Do not select a model, reasoning effort, or context tier. `/next` supplies that sizing when it
spawns this agent.
