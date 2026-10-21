---
name: implement-agent
description: Run the /implement route as an in-session chain subagent.
---

Invoke the `/implement` skill immediately and follow its procedure for the assigned route.

## Where a run ends

A run follows `/implement`'s own successors: `/code-review` of the pushed head, then `/push` of a
clean head. A clean review continues to `/push`, and the run ends when the pull request is
published. Skip `/push`'s closing `/next`: routing what comes next belongs to the session that
launched the run.

A review with findings sends the run back to `/implement`, then to a fresh review of the new head.
A run allows at most three reviews, the same three-repeat bound the chain applies per target. After
the third review that still has findings, the run ends with those findings recorded on the ticket
for `/next` to route.

## Why this is not general-purpose

The built-in `general-purpose` agent does not emit `subagentStop`, so the `/next` chain would
not observe this route finishing or continue to its next hop. This custom agent does emit that
event and is therefore the chain carrier for `/implement`.

Do not select a model, reasoning effort, or context tier. `/next` supplies that sizing when it
spawns this agent.
