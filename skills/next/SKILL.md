---
name: next
description: Route the engineering workflow or choose a skill for the current situation. Use when a workflow skill concludes, the user asks what to do next, or needs help choosing a skill or flow.
---

# Route the Workflow

This skill is the model-invoked router for the skills and engineering flow. Inspect the
current state and return one recommendation. Leave source files and the issue
tracker unchanged. A chain spawn may write its ledger and create its reserved
branch and worktree; the spawned subagent owns work inside that worktree.

The merge gate's `review-clean` evidence uses the canonical producer/matcher in
[`scripts/review-clean-record.py`](../../scripts/review-clean-record.py). Do not
reimplement its record shape in the gate; match the comment against the exact
head being gated through that script.

A successful gate decision returns the exact evaluated `headRefOid`. Treat that
value as a merge precondition, not as diagnostic output: an unattended merge
consumer must pass the same value to
`gh pr merge --match-head-commit "$headRefOid"`. If the pull request advances
after the gate decision, the merge must refuse rather than substitute the new
head. Until `/merge` is implemented by issue #52, `chain.sh gate` owns this
decision contract but does not execute a merge.

## 1. Refresh the durable state

For a **skill-selection** question, read [`SKILL-SELECTION.md`](SKILL-SELECTION.md)
and identify the desired outcome from the conversation. A standalone request
uses that conversation as its target; refresh only the files or configuration
the chosen branch needs. An engineering workstream follows the full refresh
below. Outside a repository, route a general idea to `/grill-me` and standalone
requests to their matching skill.

Locate `docs/agents/issue-tracker.md` and `.github/hooks/git-loopy-chain.json`. If either is
missing, the repository is not configured for the engineering flow: make `/setup-git-loopy-skills` the sole
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

This step is complete when a standalone request has a concrete outcome and its
branch's required context, or every engineering candidate has current state and
blocker information from its durable source and every worktree is accounted for
by the process that holds it.

## 2. Find the earliest unresolved gate

The workflow is composable, not a fixed checklist. For each active workstream,
choose the first matching transition. For a standalone request, choose the
matching branch in `SKILL-SELECTION.md` instead; a completed delivery workstream
does not make an explicit standalone request complete.

| Current state | Next route |
| --- | --- |
| The repository is not configured for the engineering skills | `/setup-git-loopy-skills` |
| An intentional phase boundary needs a context transition | Apply `PHASE-BOUNDARIES.md` before choosing a route |
| A codebase property should improve through a measured, recurring agentic loop | `/design-control-loop` |
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
| The task is to write or revise a document an agent consumes | `/writing-for-agents` |
| The accepted work is closed, reviewed, and published | No next route: report completion |

Apply these flow rules:

- Keep `/grill-with-docs`, `/to-spec`, and `/to-tickets` in one unbroken context.
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

Every recommendation names the **runtime** that carries it — an entitlement-aware
model selector, an auto-routing tier, and a context tier.

Name the **task type** of the chosen route from git-loopy's closed taxonomy:
`planning`, `review`, `implementation`, `test`, `docs`, `chore`, `bugfix`.

Read the quality target from the project's own calibration rather than
hard-coding a model name:

```bash
git-loopy config list
```

If git-loopy is unavailable, name that limitation and use the task-type defaults
below. Otherwise use the `task-type:<key>` line matching the route's task type to choose the
Auto tier. Ignore its exact model and reasoning-effort values when constructing
a Copilot CLI command: organization policy and subscription availability can
change independently of the repository calibration.

Use `--model auto` for every recommendation. Copilot CLI's Auto model selection
chooses only models available to the user's plan and administrator policy, so
the recommendation remains valid when the organization's model catalog changes.
Set `--auto-tier intelligence` for `planning` and `review`, `balance` for
`implementation`, `bugfix`, and `test`, and `efficiency` for `docs` and
`chore`. The tier is a preference, not a promise of a particular model.
Do not combine `--model auto` with `--reasoning-effort`; Auto routing owns that
choice.

If a human explicitly asks for a named model, select it from Copilot CLI's
`/model` list first and use that exact identifier; never infer entitlement from
the repository's calibration or from a model name in this skill.

Mark the action `AFK-safe` only when its target is fully specified and requires
no new human judgment; otherwise mark it `HITL`. Use the `intelligence` Auto
tier for AFK-safe work whose quality target is not already `intelligence`;
otherwise preserve the calibrated tier.

Set `--context long_context` when the run must hold more at once than one
default window holds — a repo-wide survey, a review over a large diff, a map or
spec spanning many files. git-loopy configures no context tier, so this
judgment stays the skill's own; it bills at a higher tier, so `default` carries
every other run.

This step is complete when the action is marked `HITL` or `AFK-safe` and the
task type, `auto` model selector, auto tier, and context tier are each named,
with the tier traced either to a `task-type:` line in the routing map or to the
task-type defaults above.

## 5. Apply the phase-boundary procedure and chain gate

At every intentional phase boundary, apply the full ordered procedure in the co-installed
[`PHASE-BOUNDARIES.md`](PHASE-BOUNDARIES.md); its first yes wins. The procedure is
co-installed with `/next`, so a standalone installation carries the full reference.

The procedure's fourth question, “Can the task be done AFK?”, is the reasoning behind the chain's
spawn gate. Only when it is the first yes does the procedure select `Subagent`. That action is
`AFK-safe`, but the chain may spawn it only when it is also allowlisted: `/implement`,
`/code-review`, `/research`, `/push`, or `/resolving-merge-conflicts`. A `HITL` or non-allowlisted
action reaches the checkpoint boundary instead; it does not become safe because the chain can run it.

Only for that `Subagent` outcome, consult `chain.sh plan` with the route, target, `--safety
AFK-safe`, custom agent, runtime, and proposed worktree. Treat its returned JSON decision as
authoritative. A `decline` means do not spawn; report its reason and leave the action at the
checkpoint boundary. A `spawn` proceeds to step 7. The script owns the ledger, collision, and
concurrency decisions; do not reimplement them in this skill.

The chain fills capacity one recommendation at a time. After each successful spawn, return to step 1
and ask for one more recommendation. `chain.sh plan` takes a single candidate and rejects a repeated
`--route`, `--target`, or `--worktree`, so there is no form in which to ask it for a list. Give every
pass a new proposed worktree, and never re-offer a candidate an earlier pass declined.

Three things end a fill, and the same command the fill has been asking all along records which one.
A `concurrency-limit` decline ends it at the ceiling of ten. When no ready action is left,
`chain.sh plan --no-ready` returns `exhausted` / `no-ready-action`. When ready actions remain but
every one of them takes a `worktree-in-flight` decline, `chain.sh plan --all-collide` returns
`exhausted` / `all-candidates-collide` — a separate terminal, because work waiting on a held
worktree is not the same as no work. Both forms take no candidate, record nothing, and retry
nothing, so a fill that cannot spawn stops on its first full pass instead of circling.

The fill belongs to this chain gate, not to `/next` itself. Invoked by hand, `/next` returns exactly
one recommendation at step 6 and stops there; only a `spawn` decision reached through this gate goes
round again.

The chain stops and asks a human before an unexplained runaway: it permits a route at most **three**
times for one target and a target lineage at most **eight** hops deep. A fourth repeat or ninth hop
is declined. Bare issue numbers, `issue-N`, and pull request numbers that close that issue share
those guards, including ledger rows written with an older spelling. `subagentStop` closes the
finished run's ledger row; `agentStop`, not `subagentStop`, carries re-entry into `/next`. See
[ADR-0008](../../docs/adr/0008-a-route-is-confirmed-not-assumed.md) for the route-request
confirmation contract.

The chain and `/handoff` have different lifetimes. The chain runs an in-session subagent alongside
this session and ends with it. `/handoff` launches detached work that outlives this session. Keep
`/wayfinder`, `/grilling`, `/grill-with-docs`, and `/grill-me` in this session: return their route
directly, never `/handoff`. Keep `/handoff` separate; never use it as the chain's launcher.

This step is complete when the first applicable phase-boundary choice is known, every `Subagent`
outcome has a `plan` decision, every decline carries its reason, every fill that stopped short of
the ceiling has recorded the terminal that stopped it, and every spawn is handed to step 7.

## 6. Return the recommendation

Use this shape:

````markdown
1. **<concrete action>** - `/<route>` - <HITL | AFK-safe>
Target: <linked issue, PR, map, spec, branch, document, or current conversation>
State: <Ready | Blocked by ...>
Context: <Continue here | Fresh session | Fresh session in a new worktree | Subagent>
Runtime: `--model auto --auto-tier <efficiency | balance | intelligence> --context <default | long_context>`
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
copilot -n "<descriptive name>" --model auto --auto-tier "<tier>" --context "<default | long_context>" -p "$PROMPT"
```
````

Write the prompt **paste-safe**: one physical line of plain ASCII that opens with
the exact skill invocation and names its target in bare words, so the shell
receives a single argument on every path it travels — the heredoc below, a
hand-typed `-p "..."`, or a background launcher that re-quotes the whole command
in single quotes. That last path makes paste-safe also mean apostrophe-free:
write *the meaning of every ticket* rather than *every ticket's meaning*, and
spell contractions out. An apostrophe closes the launcher's own quoting and the
session dies before it starts, leaving no log and no process to explain why.
Keep every label and explanation outside the code fence. For `/compact`, pass
the instruction the phase-boundary procedure requires. Match
`Context` to the phase-boundary procedure. When another agent holds the primary
worktree, carry that constraint into the prompt and do not direct work into it.
If the procedure selects `Fresh session in a new worktree`, open the prompt with
the command that makes that worktree and records its owner in one step, so the
constraint is cleared before the agent writes:

`chain.sh claim --worktree <path> --create-branch <branch> --owner-pid "$PPID"`

Use this rather than a bare `git worktree add`. A prompt-created worktree is the
second producer of an ownership marker and never passes through the chain's
`reserve`, so nothing else vouches for it; `claim` writes the same marker
`reserve` writes and records the pair as a pending worktree, so an interrupted
prompt cannot leave a worktree a later reader mistakes for abandoned clutter. Give the prompt that one
command, do not restate the marker format, and splice in this skill's own
absolute path to `chain.sh`, because the fresh session starts somewhere that has
not loaded `/next`.

Carry into the prompt every constraint that came from live state and is absent
from the target's own record: the worktree to work in, the files it shares with
work in flight, and what to do about each. The target's record travels with the
target; what this session learned travels only in the prompt.

The `Command` block is the whole recommendation as one selection the user can
copy and run. Repeat the prompt inside it byte for byte between the quoted
heredoc markers, which carry its `#` and spacing through to `-p "$PROMPT"` as
one argument, and splice the same runtime flags in verbatim. Name the
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
opens with the `chain.sh claim` that makes the worktree and moves the agent
before it writes.

For `/handoff`, use `Continue here` and say that its output opens the fresh
session. Give `Runtime` as the runtime flags verbatim, so a launcher such as
`/handoff` splices them straight into its background agent.

For a terminal workstream, return:

```markdown
**Complete:** <why no further workflow skill is needed>.
```

This step is complete when the recommendation names its live target, state, context, runtime, and
paste-safe prompt, and includes a `Command` block exactly when its context requires a
user-launched fresh session.

## 7. Spawn a chain-approved route

Set `Context: Subagent` only for the `spawn` decision from step 5. Reserve the target in the
decision's new worktree before launching the returned custom agent in background mode. For the
serial first hop, reserve the current working directory instead with `chain.sh reserve --in-place`
and record `COPILOT_AGENT_SESSION_ID` with `--session-id` on that reservation: it is the
deterministic parent-session value the completion payload will carry, so the transcript can be
correlated even before the runtime returns the agent identity. An in-place reservation never
creates, and `complete` and `recover` never remove, the working directory it names. The routing
agent performs the background custom-agent `task` invocation; `chain.sh` deliberately owns only
the durable reserve, bind, complete, and guard operations. Each reservation records the process
identity of its reserving parent, which is this routing session and never the shell that runs the
command: pass `--parent-pid "$PPID"` from that shell, whose own parent is the session. Recovery
reclaims an unbound orphan when that parent is gone, with the configured timeout as a backstop. It
reclaims a bound abandoned run only when that parent is proven gone. `plan` runs that recovery before
it evaluates concurrency, so an orphan cannot make a later candidate appear to be at the ceiling.
Bind the run immediately after launch, then carry the recommendation's paste-safe prompt and
runtime into the agent. Do not launch a declined action, an action that reaches the checkpoint
boundary, or an action whose phase-boundary choice is anything other than `Subagent`.

Three of the four `bind` arguments decide whether the row ever closes, and only one of them comes
back from the `task` invocation. `--agent-id` takes the agent id it returned and `--agent-type` the
custom agent it ran, but `--session-id` takes **this routing session's own id**, the same session
whose process is passed as `--parent-pid`, and never that returned agent id: `subagentStop` reports
a run under the session that launched it, so a row bound with the agent id there matches no payload
and stays open forever.

`--agent-name` is decorative — it is recorded on the row so a human reading the ledger can tell one
hop from another, and nothing matches on it. Do not treat a descriptive name as identity: the
`subagentStop` payload carries no field holding it, so a name is never what a completion finds its
row by.

When a run completes, `subagentStop` frees its reservation and `agentStop` requests `/next` again.
Each completion frees one slot, and a re-entry may carry several completed runs at once: fan-out
finishes in batches, so one block requests the whole batch and names every freed target. The
following `stop_hook_active` turn confirms that request before the helper records the rows as
routed. Begin the same one-recommendation fill again and refill every freed slot while ready work
remains, rather than waiting for the other in-flight runs to finish.

Every other route ends at step 6 and leaves a user-launched fresh session, continued session, or
`/handoff` transition to its own documented behavior.

Routing is complete when every active candidate has been classified and every
recommendation names a live target, an exact invocation, a paste-safe prompt in
its own code fence, a copyable `copilot` command whenever the user launches the
fresh session, the correct context, a sized runtime, and any blocker — and every
`Subagent` recommendation has a live, bound in-session agent.
