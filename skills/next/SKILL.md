---
name: next
description: Route the engineering workflow from live project state. Use when a workflow skill concludes or the user asks what to do next.
---

# Route the Workflow

This skill is the model-invoked router for the engineering flow. Inspect the
current state and return one recommendation. Leave source files and the issue
tracker unchanged. A chain spawn may write its ledger and create its reserved
branch and worktree; the spawned subagent owns work inside that worktree.

## 1. Refresh the durable state

Locate `docs/agents/issue-tracker.md` and `.github/hooks/git-loopy-chain.json`. If either is
missing, the repository is not configured for these skills: make `/setup-git-loopy-skills` the sole
candidate. In particular, a missing hook means the repository is not configured. Otherwise read the
file and refresh the
workstream referenced by the conversation from its configured tracker: issue or PR state,
labels, assignees, comments, sub-issues, and blockers. Inspect the local branch, commits, and
diff when review or publication may be next.

When the conversation names no workstream, review the open workflow-bearing
issues and their relationships to find the active maps, specs, tickets, and PRs.
Use live records rather than session summaries because concurrent sessions may
have changed them.

Then account for what is already **in flight**, which no tracker records: the
worktrees (`git worktree list`), the uncommitted files in each, and the runner
or agent process holding one. A git-loopy run names the issue it bound in the
newest `.git-loopy/logs/` file and works in the worktree it was started from.
Work recommended into a directory another agent is writing collides with it.

This step is complete when every candidate action has current state and blocker
information from its durable source, and every worktree is accounted for by the
process that holds it.

## 2. Find the earliest unresolved gate

The workflow is composable, not a fixed checklist. For each active workstream,
choose the first matching transition:

| Current state | Next route |
| --- | --- |
| The repository is not configured for the engineering skills | `/setup-git-loopy-skills` |
| An intentional phase boundary needs a context transition | Apply `PHASE-BOUNDARIES.md` before choosing a route |
| An idea outside a codebase still needs sharpening | `/grill-me` |
| An idea in a codebase still has human decisions | `/grill-with-docs` |
| The destination is too foggy or large for one planning context | `/wayfinder` |
| A hard bug lacks a tight command that reproduces it | `/diagnosing-bugs` |
| A factual unknown can be resolved from primary sources | `/research` |
| A decision depends on information only another person can provide | `/to-questionnaire` |
| A runnable behavior or visual answer is cheaper than more discussion | `/prototype` |
| Domain language itself blocks the decision | `/domain-modeling` |
| A module interface, seam, or boundary needs designing | `/codebase-design` |
| The destination is agreed but no durable spec exists | `/to-spec` |
| A spec exists but executable tracer-bullet tickets do not | `/to-tickets` |
| A raw incoming issue or external PR needs readiness work | `/triage` |
| An in-progress merge, rebase, or cherry-pick has conflicts | `/resolving-merge-conflicts` |
| A concrete behavior should be built test-first without the broader ticket flow | `/tdd` |
| An unblocked `ready-for-agent` ticket or small agreed change is available | `/implement` |
| Implemented work or review fixes still need a fixed-point review | `/code-review` |
| Reviewed work remains local or the current branch lacks its PR | `/push` |
| No delivery work is active and codebase health needs a survey | `/improve-codebase-architecture` |
| The user wants a stateful learning path | `/teach` |
| The task is to write or revise an agent skill | `/writing-for-agents` |
| The accepted work is closed, reviewed, and published | No next route: report completion |

Apply these flow rules:

- Keep `/grill-with-docs`, `/to-spec`, and `/to-tickets` in one unbroken context.
  Start each `/implement` ticket in a fresh context. A genuinely small change can
  move directly from grilling to `/implement` in the current context.
- At an intentional phase boundary, `PHASE-BOUNDARIES.md` alone chooses the
  context transition. Use `/handoff` only for its portability cases: a new
  harness, directory, colleague, or mid-phase side task.
- Bridge a prototype detour with `/handoff` in both directions when its new
  directory or mid-phase fork needs portability. Route the validated answer
  back into the main flow.
- Route source-answerable gaps to `/research` and answers held by another person
  to `/to-questionnaire`. Resume the decision flow with either result in
  `/grill-with-docs` or `/to-spec`.
- `/to-tickets` output is already agent-ready; reserve `/triage` for work that
  arrived raw.
- If a Wayfinder map has an open frontier, continue `/wayfinder`. When the
  destination is clear and no decision ticket remains, route to `/to-spec`, not
  directly to implementation unless the effort proved genuinely small.
- `/implement` drives `/tdd` internally and closes with `/code-review`. Route
  directly to those skills only for their standalone branches.
- If review finds defects, route back to `/implement` with the findings. After a
  bug fix, route to `/improve-codebase-architecture` only when the diagnosis
  exposed a missing seam or structural cause.
- A candidate selected by `/improve-codebase-architecture` becomes an idea for
  `/grill-with-docs`; the survey does not implement it.
- Reach for `/domain-modeling` or `/codebase-design` directly only when the
  vocabulary or module shape is itself the unresolved gate.

This step is complete when every candidate is classified as ready, blocked, or
complete.

## 3. Rank the actions

An action another agent already holds is spoken for: the holder is its state,
and a second agent on the same target duplicates or corrupts the work. Leave it
out of the candidate set and rank what remains.

Rank ready actions before blocked actions. Within each group, prefer:

1. The workstream continued by this session.
2. The action that clears the most downstream blockers.
3. The action that shares no files with work in flight.
4. The oldest tracker item, then the lexical target name, as stable tie-breakers.

A shared file is a constraint to name, not a disqualification — an action that
unblocks the queue still wins rule 2 and carries its overlap into the prompt.

Return at most one action. A blocked action must name the condition that makes
it ready.

This step is complete when the ordering follows all four rules, every blocked
action carries a checkable readiness condition, and any file the chosen action
shares with work in flight is named.

## 4. Size the runtime

Every recommendation names the **pair** that carries it — a model and a
reasoning effort — plus a context tier.

Name the **task type** of the chosen route from git-loopy's closed taxonomy:
`planning`, `review`, `implementation`, `test`, `docs`, `chore`, `bugfix`.

Read the pair from the project's own calibration rather than deciding it:

```bash
git-loopy config list
```

Use the `task-type:<key>` line matching the route's task type. A key the map
leaves unset falls back to the `model` and `reasoning_effort` the same output
prints. Read the map even when it reports itself inert — that note is about
git-loopy's own serial iterations, while this pair carries a Copilot CLI
session the user launches.

A repository without git-loopy, or a command that fails, falls back to this
table, which balances speed against quality per task type:

| Task type | Model | `--effort` |
| --- | --- | --- |
| `planning` | strongest reasoning model available (`claude-opus-5`) | `xhigh` |
| `review` | strongest reasoning model available (`gpt-5.6-sol`) | `xhigh` |
| `bugfix` | strong general model (`claude-sonnet-5`, `gpt-5.6-terra`) | `high` |
| `implementation` | strong general model (`gpt-5.6-terra`) | `high` |
| `test` | strong general model (`gpt-5.6-terra`) | `medium` |
| `docs` | strong general model (`gpt-5.6-luna`) | `low` |
| `chore` | fast model (`claude-haiku-4.5`) | `none` |

Mark the action `AFK-safe` only when its target is fully specified and requires
no new human judgment; otherwise mark it `HITL`. Raise an `AFK-safe` action's
effort one level, capped at `xhigh`, **only when the pair came from the fallback
table** — a configured route is already calibrated against unattended runs, so
raising it counts the same allowance twice. Reserve `max` for a route an `xhigh`
pass has already failed. When the running CLI does not offer the named model,
use `auto` and let the effort level carry the demand.

Set `--context long_context` when the run must hold more at once than one
default window holds — a repo-wide survey, a review over a large diff, a map or
spec spanning many files. git-loopy configures no context tier, so this
judgment stays the skill's own; it bills at a higher tier, so `default` carries
every other run.

This step is complete when the action is marked `HITL` or `AFK-safe` and the
task type, model, effort, and context tier are each named, with the pair traced
either to a `task-type:` line in the routing map or to the fallback table.

## 5. Apply the phase-boundary procedure and chain gate

At every intentional phase boundary, apply the full ordered procedure in the co-installed
[`PHASE-BOUNDARIES.md`](PHASE-BOUNDARIES.md); its first yes wins. The procedure belongs in this
skill's directory so an installation of `/next` carries it without `/skill-router`.

The procedure's fourth question, “Can the task be done AFK?”, is the reasoning behind the chain's
spawn gate. A yes marks the action `AFK-safe`, but the chain may spawn it only when it is also
allowlisted: `/implement`, `/code-review`, `/research`, `/push`, or `/resolving-merge-conflicts`.
An allowlisted route that is `HITL` reaches the checkpoint boundary instead; it does not become safe
because the chain can run it.

For an `AFK-safe` allowlisted action, consult `chain.sh plan` with the route, target, custom agent,
runtime, and proposed worktree. Treat its returned JSON decision as authoritative. A `decline` means
do not spawn; report its reason and leave the action at the checkpoint boundary. A `spawn` selects
`Context: Subagent` and proceeds to step 7. The script owns the ledger, collision, and concurrency
decisions; do not reimplement them in this skill.

The chain stops and asks a human before an unexplained runaway: it permits a route at most **three**
times for one target and a target lineage at most **eight** hops deep. A fourth repeat or ninth hop
is declined. `subagentStop` closes the finished run's ledger row; `agentStop`, not `subagentStop`,
carries re-entry into `/next`.

The chain and `/handoff` have different lifetimes. The chain runs an in-session subagent alongside
this session and ends with it. `/handoff` launches detached work that outlives this session. Keep
`/handoff` separate; never use it as the chain's launcher.

This step is complete when the first applicable phase-boundary choice is known, every eligible
subagent action has a `plan` decision, every decline carries its reason, and every spawn is handed
to step 7.

## 6. Return the recommendation

Use this shape:

````markdown
1. **<concrete action>** - `/<route>` - <HITL | AFK-safe>
Target: <linked issue, PR, map, spec, branch, document, or current conversation>
State: <Ready | Blocked by ...>
Context: <Continue here | Fresh session | Fresh session in a new worktree | Subagent>
Runtime: `--model <model> --effort <level> --context <default | long_context>`
Why now: <one sentence grounded in live state>

Prompt:
```text
/<route> <concise imperative naming the target and desired outcome>
```

Command:
```bash
PROMPT=$(cat <<'PROMPT_EOF'
/<route> <concise imperative naming the target and desired outcome>
PROMPT_EOF
)
co -n "<descriptive name>" --model "<model>" --effort "<level>" --context "<default | long_context>" --no-mouse -p "$PROMPT"
```
````

Write the prompt **paste-safe**: one physical line of plain ASCII that opens with
the exact skill invocation and names its target in bare words, so the shell
receives a single argument whether the prompt reaches it through the heredoc
below or a hand-typed `-p "..."`. Keep every label and explanation outside the
code fence. For `/compact`, pass no argument. Match `Context` to the flow rules
above, choosing `Fresh session in a new worktree` when another agent holds the
primary worktree — and open the prompt with the `git worktree add` that clears
it, so the agent moves itself before it writes.

Carry into the prompt every constraint that came from live state and is absent
from the target's own record: the worktree to work in, the files it shares with
work in flight, and what to do about each. The target's record travels with the
target; what this session learned travels only in the prompt.

The `Command` block is the whole recommendation as one selection the user can
copy and run. Repeat the prompt inside it byte for byte between the quoted
heredoc markers, which carry its apostrophes and `#` through to `-p "$PROMPT"`
as one argument, and splice the same three runtime flags in verbatim. Name the
session with `-n` in a few words drawn from the action, because a launched
session has no terminal to identify it and that name is how the user returns to
it with `copilot --yolo --resume="<descriptive name>"`. The command
runs the session in the user's own terminal; `/handoff` launches the same pair
in the background instead.

Emit the `Command` block only when `Context` names a fresh session the user
launches — a `Continue here` recommendation is a prompt for this conversation and
has no session to launch, and a `Subagent` recommendation is launched by the
chain gate in step 7, so a second copyable launcher would put two agents on one
worktree. When the context is `Fresh session in a new worktree`, the
command still runs from the current directory, because the prompt it carries
opens with the `git worktree add` that moves the agent before it writes.

For `/handoff`, use `Continue here` and say that its output opens the fresh
session. Give `Runtime` as the three flags verbatim, so a launcher such as
`/handoff` splices them straight into its background agent.

For a terminal workstream, return:

```markdown
**Complete:** <why no further workflow skill is needed>.
```

This step is complete when the recommendation names its live target, state, context, runtime, and
paste-safe prompt, and includes a `Command` block exactly when its context requires a
user-launched fresh session.

## 7. Spawn a chain-approved route

Set `Context: Subagent` only for the `spawn` decision from step 5. Reserve the target before
launching the returned custom agent in background mode, bind the returned agent identity
immediately after launch, and carry the recommendation's paste-safe prompt and runtime into that
agent. Do not launch a declined action, an action that reaches the checkpoint boundary, or an action
whose phase-boundary choice is `/handoff`.

Every other route ends at step 6 and leaves a user-launched fresh session, continued session, or
`/handoff` transition to its own documented behavior.

Routing is complete when every active candidate has been classified and every
recommendation names a live target, an exact invocation, a paste-safe prompt in
its own code fence, a copyable `copilot` command whenever the user launches the
fresh session, the correct context, a sized runtime, and any blocker — and every
`Subagent` recommendation has a live, bound in-session agent.
