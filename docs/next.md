Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=next
```

```bash
npx skills update next
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next)

## What it does

`next` is the router over the skills in this repo. It reads the live state of your work and returns a single recommendation: the one action to take now, the skill that performs it, the exact invocation to paste, and the runtime to run it on — the model, reasoning effort, and context window that skill's own header sets. For a narrowly defined set of **AFK-safe** delivery routes, it can also spawn that recommendation as an in-session subagent.

It also replaces `/skill-router`: ask `/next` which skill or flow fits the current
situation. Its co-installed `SKILL-SELECTION.md` covers interview wrappers, build
scope, and standalone requests such as release, human-only setup, learning, agent
writing, and model configuration. Those requests use the context their branch
needs rather than requiring an engineering tracker and chain hook.

It does not itself grill, write a spec, or fix anything. It either orients at a checkpoint boundary or, when the chain gate approves, records and launches work owned by the spawned route. What separates it from a checklist is where it looks: not at what you told it in conversation, but at `docs/agents/issue-tracker.md`, the tracker itself, and your branch and diff. Concurrent sessions move that state underneath you, so the recommendation is drawn from live records rather than from a session summary.

## When to reach for it

This one is model-invoked — the agent reaches for it on its own when a workflow skill concludes and the next step is unclear. You can also invoke `/next` directly.

Reach for it whenever you're unsure which skill or flow a situation calls for: a skill just finished and you don't know what follows, you have an idea and don't know where to start, or two skills look interchangeable and you can't tell them apart. If you already know the skill you want, skip the router and invoke it directly.

## The earliest unresolved gate

The idea `next` runs on is the **gate** — the first unresolved condition standing between the work and its destination. The flow is composable, not a fixed sequence, so it doesn't ask "which step comes after the last one" but "what is the earliest thing still unresolved". An idea that still has human decisions in it gates on grilling; an agreed destination with no durable spec gates on [to-spec](./to-spec.md); an unblocked ticket gates on [implement](./implement.md). Ranking follows from that: ready actions before blocked ones, the workstream you're already in before a cold one, and the action that clears the most downstream blockers before the rest.

Every recommendation is labelled **HITL** or **AFK-safe** — whether the next action needs your judgement, or is specified tightly enough to be left to run on its own. Blocked actions are still returned, but must name the condition that would make them ready.

## The sessions it tracks

Before ranking anything, `next` runs `scripts/sessions.py scan` to see which GitHub Copilot CLI sessions are live in the repository. A session counts as live when its `~/.copilot/session-state/<id>/inuse.<pid>.lock` names a running `copilot` process. The session's `workspace.yaml` places it in the main checkout or in one of its worktrees. The scan reports each worktree with the sessions working in it, along with their names, branches, and any chain targets they hold. An action another session already holds is left to that session.

Each run appends its scan to the **session log**, `.git-loopy/next/sessions.jsonl` at the repository root. The `.git-loopy/` runtime directory is gitignored and shared by every worktree. Each line records when the scan ran, which session invoked `/next`, and the sessions it saw. The next scan compares against that line, so it reports each session as `new` or `continuing` and lists the ones that have `ended` since. Pass `--no-record` to look without logging.

## The runtime it names

A recommendation also names the **runtime** to run it on, and `next` reads that runtime rather than sizing one. A skill's `SKILL.md` header sets the GitHub Copilot `model`, reasoning `effort`, and `context` window to choose in `/model` before running it. `next` reads the header of the skill it routes to with `scripts/runtime.py`, so a route to a skill whose header sets `gpt-6.1-sol`, `medium`, and `272K` comes back as:

```text
Runtime: model gpt-6.1-sol, effort medium, context 272K (default)
```

The tier in parentheses, `default` or `long_context`, is the one that window belongs to. Copilot CLI's `--context` flag and a subagent's context tier take the tier, not the window. `runtime.py` reads it from the model catalog `/model-scorecard` keeps in `references/skill-headers.json`: a window larger than the model's default one is `long_context`. Without that catalog, it falls back to `default`. A route that names no header, such as the built-in `/compact`, reads `Runtime: current session`.

`SKILL.md` is the authoritative source for a skill's `model`, `effort` and `context`. If those header settings are missing, incomplete, malformed or unreadable, `/next` resolves them from that skill's entry in `/model-scorecard`'s generated `references/skill-headers.json`. The resolver reports the selected source as `skill-header` or `model-scorecard`; if neither source has a complete valid runtime, it reads `Runtime: current session`.

There is no command to run. Pick the runtime in `/model` and paste the prompt into the session the recommendation names, or run [handoff](./handoff.md), which launches the prompt in the background on the same runtime.

## The chain it can spawn

For an **AFK-safe** action, `next` may spawn exactly five routes. An ordinary `/next` invocation still returns exactly one recommendation. The chain is the separate
AFK-safe path: after the phase-boundary procedure selects a subagent, the spawn gate requires both an
AFK-safe target and one of its five allowlisted routes — `/implement`, `/code-review`, `/research`,
`/push`, or `/resolving-merge-conflicts`. Planning declines a target the tracker confirms is
unresolvable, and reservation checks it again before writing the ledger row or creating the
worktree. A transient tracker failure is reported as tracker unavailability rather than as a
missing target. A bare number is first resolved to its canonical issue, a lookup bounded at 10
seconds; if it fails or a pull request does not close exactly one issue, `plan` declines with
`target-resolution-failed` and the cause, `reserve` refuses with both, and `complete` closes the row
as a transient `tracker-failed` rather than leaving it open. An older ledger row whose pull request
has no single closing issue keeps its own spelling and does not block unrelated targets; a row
whose number the tracker can no longer find still fails the lookup. A valid target
reserves a worktree and a concurrency slot in the spawn ledger
before starting the in-session subagent, then binds the run to that reservation.

The ledger records each reservation, binding, worktree, completion, and per-target chain depth so the
chain neither duplicates in-flight work nor exceeds ten concurrent runs. Numeric issue targets and
their `issue-N` spelling share one identity; a pull request number uses the issue it closes, including
when older ledger rows retain a previous spelling. A reservation also names the process identity of
its reserving parent — the routing session itself, never the shell that runs the command, which exits
with it: recovery reclaims an unbound orphan immediately when that
parent is gone, or after `CHAIN_RESERVATION_STALE_SECONDS` (300 seconds by default), marking it
`reclaimed` rather than as a completed run. An abandoned run is reclaimed only when the same
liveness check proves its reserving parent is gone; age alone never reclaims an in-flight run.
Reclaiming releases the row's slot and applies the same worktree rule as completion, below. Every
`plan` runs recovery before checking capacity, so
reclaimed slots immediately become available to the next candidate. It stops at a checkpoint
boundary rather than spawning when the route is HITL or not allowlisted, a route would take its
fourth repeat for a target, or a target would take its ninth hop. `subagentStop` closes the completed
ledger row; if its tracker lookup fails, the row closes as `tracker-failed` and records whether the
failure was transient or permanent. A transient rate limit, server error, network failure,
30-second tracker timeout, or malformed tracker response leaves the target retryable. Only a tracker
error saying the target is missing or invalid is permanent: it halts the target instead of being
mistaken for `no-evidence`. Completion and recovery remove a clean worktree and report any other as
a retained worktree (`CONTEXT.md`).
`agentStop` re-enters `/next` for the batch of completed, unrouted runs, allowing one fill to replace
every slot that batch freed.
AFK-safe and allowlisted are the two eligibility conditions for consulting `chain.sh plan`, not a
guarantee of a spawn. The planner is authoritative and may decline an otherwise eligible action when
its target or worktree is already in flight, the target is halted or failed, or the concurrency limit
is reached. A completed run without an issue comment timestamped between its spawn and completion
halts its target with `no-evidence`; the
repetition and depth guards likewise decline a fourth repeat for one route and target or a ninth
lineage hop. Every decline remains at the checkpoint boundary for a human rather than launching a
subagent.

## It's working if

- You get back exactly one action, with a live target — a linked issue, PR, spec, branch, or the current conversation — and never a menu of possibilities.
- Fan-out never turns that into a menu either: the chain reaches its ten concurrent worktrees by asking for one recommendation at a time, and names which of the three limits stopped it — the ceiling of ten, no ready action left, or every remaining candidate waiting on a worktree another agent holds.
- Once the ten are running, the chain keeps itself full: each finished run frees its slot, and the batch of runs that finished since the last turn comes back as one re-entry that refills every one of them while ready work remains.
- A recommendation names the model, effort, and context window its routed skill's header sets, and carries no command to run.
- An AFK-safe recommendation for one of the five allowlisted routes arrives with its in-session
  subagent already running only when `chain.sh plan` returns `spawn`; on `decline`, it remains at
  the checkpoint boundary as a prompt.
- The recommendation names whether to continue in this context, start a fresh session, or run as a
  subagent, matching the flow's own rules: grill → spec → tickets stays in one context, while the
  chain starts only approved delivery work.
- For engineering work in a repo missing either its tracker configuration or
  `.github/hooks/git-loopy-chain.json`, it routes to
  [setup-git-loopy-skills](./setup-git-loopy-skills.md) and nothing else.
- When the work is genuinely finished, it says so instead of inventing a next step.

## Where it fits

`next` is the **router** — the standalone map that sits over the whole set. It points into every
flow and carries the bounded chain when its gate approves. From here you'll most often land on
[grill-with-docs](./grill-with-docs.md), the head of the main flow, or [triage](./triage.md), the
on-ramp for work you didn't create. The engineering flow's prerequisite is
[setup-git-loopy-skills](./setup-git-loopy-skills.md), because the tracker config and chain hook
that skill writes are the state `next` reads. When even the router's own picture is stale, its
[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next) is the map of
record.
