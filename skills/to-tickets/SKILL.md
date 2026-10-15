---
name: to-tickets
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker (edges as text in one file per ticket locally, or native blocking links on a real tracker).
model: claude-opus-5.5
effort: medium
context: 1M
disable-model-invocation: false
---

# To Tickets

Break a plan, spec, or conversation into a set of **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it.

The issue tracker and triage label vocabulary should have been provided to you. If not, tell the user to run `/setup-git-loopy-skills`.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests): vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

Give each ticket its **blocking edges**: the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

### Bound deliberate host load

Any acceptance criterion that demands **deliberate host load** (stress loops, CPU burners, or extra concurrent command copies) must state its bounds in the ticket itself, not only in its parent spec. "Oversubscribe the CPU about 2x" alone is insufficient. Require:

- On macOS, `taskpolicy -c utility <command>` to protect the operator's foreground; `nice` is not a substitute. Do not run load if the clamp cannot be applied, and never raise inherited priority.
- A total concurrency ceiling of at most about 2x the logical CPUs, counting child workers and extra command copies.
- A wall-clock cap per invocation: an explicit issue-specific cap, otherwise 30 minutes. A cutoff before completion is **inconclusive**, never a pass; a completed invocation reports its actual result.
- No escalation beyond those bounds to force a reproduction: record observations and stop.
- Cleanup after completion, failure, or interruption: reap the processes started and their descendants, check survivors with `pgrep`, establish ownership before ending them by PID, and report cleanup or uncertain ownership.

Ordinary feedback loops declared in `AGENTS.md`, including their built-in test workers, are not deliberate load. They inherit the Run's Host yield policy without an additional clamp or time cap and run to completion; process cleanup still applies. Reject or rewrite an unbounded load criterion before publishing, and preserve tighter bounds already agreed in the spec.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change (rename a column, retype a shared symbol) whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket; green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct: does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `/setup-git-loopy-skills` configured; the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below: one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → publish one issue per ticket in dependency order (blockers first) so each ticket's blocking edges can reference real identifiers. Use the platform's native blocking relationship where it has one; otherwise set each ticket's "Blocked by" to the blocking issues. On GitHub, create every approved edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. If the source was an existing issue, make each ticket its sub-issue (tracker doc's operation): on GitHub, `gh api --method POST repos/<owner>/<repo>/issues/<spec>/sub_issues -F sub_issue_id=<child-db-id>`. Both commands require numeric database ids (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`), not issue numbers or node ids. Native edges are the lifecycle fact readiness is derived from; body text is only a fallback for trackers without dependencies.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue during decomposition; the evidence comment below is the only exception. Closing a delivered parent is later bookkeeping, not part of this session.

### Label each published ticket

For a tracker that supports labels, make three separate decisions while creating each
ticket. Read the exact label strings from the configured repository's triage-label
documentation; do not invent label names or substitutes.

1. Apply `ready-for-agent` (the configured AFK-ready triage role) unless instructed
   otherwise; the tickets are agent-grabbable by construction.
2. Apply exactly one `task-type:` label. For an agent-ready ticket, propose only the five execution types:
   `implementation`, `test`, `docs`, `chore`, or `bugfix`. A ticket handed to a
   human may carry any of the closed seven, including `planning` or `review`;
   keep those two off agent-ready tickets. Choose by **dominant risk**: the
   dimension whose failure is most expensive, not the one with the most files.
   Multiple labels fail silently because the router selects the first match from
   an unordered list. Never invent an eighth type: an out-of-taxonomy label looks
   labelled, so the classifier will not correct it and routing falls through.
3. Decide independently whether to add the configured `parallel-safe` marker. It is
   additive, alongside the triage and task-type labels, and applies only when the
   ticket can land beside another ticket without colliding. Do not infer a missing
   marker: unlike the task type, it has no classifier fallback, so its absence
   forfeits the parallel lane.

Treat label hazards as release-blocking. For local-file tickets, record the same
selected triage role, task type and parallel-safety judgement in the ticket file
so they can be applied when the ticket reaches a label-capable tracker.

<local-ticket-template>

# <NN>: <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective, not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None (can start immediately)".

**Status:** the triage label selected above.

**Task type:** the task-type label selected above.

**Parallel safety:** the independent marker decision above, including an explicit negative.

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</local-ticket-template>

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- A reference to each blocking ticket, or "None (can start immediately)". Omit this section when blockers were set as native edges.

</issue-template>

In either form, avoid specific file paths or code snippets: they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

## 6. Record the decomposition

Decomposition is a durable workflow transition. Record it so the next session, human or
agent, reads the same answer you did.

**Only record once the whole approved graph is durable.** The approved child set and its
edges are what make a ticket executable. Complete publication and labeling above, then
verify that the saved graph matches the approved breakdown before posting one short
evidence comment on the spec parent naming the tickets you created
(`gh issue comment <spec-issue> --body "..."`). With no source issue, record the same
evidence alongside the published tickets.

If you cannot finish the graph, do not leave it half-recorded: a partially wired
decomposition would make a ticket look executable against a plan that doesn't fully exist
yet. Finish creating and wiring every approved ticket before treating the decomposition as
done.

At the conclusion of a `/to-tickets` session, determine what to do after tickets are generated.
Call the Skill tool with "next".
