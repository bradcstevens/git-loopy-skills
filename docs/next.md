Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=next
```

```bash
npx skills update next
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next)

## What it does

`next` is the router over the skills in this repo. It reads the live state of your work and returns a single recommendation: the one action to take now, the skill that performs it, the exact invocation to paste, and the runtime to run it on — model, reasoning effort, and context tier. For a narrowly defined set of unattended delivery routes, it can also spawn that recommendation as an in-session subagent.

It does not itself grill, write a spec, or fix anything. It either orients at a checkpoint boundary or, when the chain gate approves, records and launches work owned by the spawned route. What separates it from a checklist is where it looks: not at what you told it in conversation, but at `docs/agents/issue-tracker.md`, the tracker itself, and your branch and diff. Concurrent sessions move that state underneath you, so the recommendation is drawn from live records rather than from a session summary.

## When to reach for it

This one is model-invoked — the agent reaches for it on its own when a workflow skill concludes and the next step is unclear. You can also invoke `/next` directly.

Reach for it whenever you're unsure which skill or flow a situation calls for: a skill just finished and you don't know what follows, you have an idea and don't know where to start, or two skills look interchangeable and you can't tell them apart. If you already know the skill you want, skip the router and invoke it directly.

## The earliest unresolved gate

The idea `next` runs on is the **gate** — the first unresolved condition standing between the work and its destination. The flow is composable, not a fixed sequence, so it doesn't ask "which step comes after the last one" but "what is the earliest thing still unresolved". An idea that still has human decisions in it gates on grilling; an agreed destination with no durable spec gates on [to-spec](./to-spec.md); an unblocked ticket gates on [implement](./implement.md). Ranking follows from that: ready actions before blocked ones, the workstream you're already in before a cold one, and the action that clears the most downstream blockers before the rest.

Every recommendation is labelled **HITL** or **AFK-safe** — whether the next action needs your judgement, or is specified tightly enough to be left to run on its own. Blocked actions are still returned, but must name the condition that would make them ready.

## The runtime it sizes

A recommendation also names the **runtime** to run it on: `--model`, `--effort`, and `--context`, sized to the demand of the route it picked. Open judgement — grilling, wayfinding, spec writing, hard diagnosis — draws the strongest reasoning model at `xhigh`; ordinary build and review work draws a strong general model at `high`; mechanical, fully specified work draws a fast model at `medium`. An **AFK-safe** action gets one level more effort, because no human is mid-flight to catch a thin pass, and `long_context` is reserved for runs that must hold more at once than one default window holds. The flags come out verbatim, so [handoff](./handoff.md) can splice them straight into the background agent it launches.

When the route calls for a fresh session, the recommendation also comes with the whole thing already assembled: a `Command` block holding the prompt in a quoted heredoc and the sized flags spliced into a `copilot --yolo -n "..." --model ... --effort ... --context ... -p "$PROMPT"` invocation. Select it, paste it, and the next session starts — named, so `copilot --yolo --resume="<name>"` finds it again. It's the same detached launch [handoff](./handoff.md) performs for you in the background, offered here as one copyable selection instead.

## The chain

`next` may autonomously spawn exactly five routes: [`/implement`](./implement.md),
[`/code-review`](./code-review.md), [`/research`](./research.md), `/push`, and
[`/resolving-merge-conflicts`](./resolving-merge-conflicts.md). The allowlist is deliberately
small: these are delivery transitions with a concrete target and a custom in-session agent that
can report completion back to the parent session. A recommendation for any other route remains at
the checkpoint boundary for a person to run or hand off.

The spawn gate has two conditions. The phase-boundary procedure must select **Subagent**, which
means the route is **AFK-safe**: fully specified and requiring no further human judgement. Its
route must also be one of the five allowlisted routes. Both conditions are required; an
allowlisted route that is HITL is not launched merely because it is on the list.

Before launch, the chain records a reservation in its ledger, then binds the returned subagent
identity to that row. The ledger is the chain's durable state: it prevents collisions, associates
completion with the route and target that were launched, and records whether that completion has
been routed again. `subagentStop` closes the completed row; `agentStop` re-enters `/next` when an
unrouted completion needs its successor chosen.

The ledger also makes runaway stops explainable. A route may run at most **three** times for one
target, and a target lineage may contain at most **eight** hops. A proposed fourth repeat or ninth
hop is declined and returned to a human instead of being spawned.

## It's working if

- You get back exactly one action, with a live target — a linked issue, PR, spec, branch, or the current conversation — and never a menu of possibilities.
- A recommendation that opens a fresh session arrives as a runnable `copilot` command, not as flags you assemble yourself.
- An AFK-safe recommendation for one of the five allowlisted routes arrives with its in-session
  subagent already running; other routes remain a prompt or a copyable fresh-session command.
- The recommendation names whether to continue in this context, start a fresh session, or run as a
  subagent, matching the flow's own rules: grill → spec → tickets stays in one context, while the
  chain starts only approved delivery work.
- In a repo missing either its tracker configuration or
  `.github/hooks/git-loopy-chain.json`, it routes to
  [setup-git-loopy-skills](./setup-git-loopy-skills.md) and nothing else.
- When the work is genuinely finished, it says so instead of inventing a next step.

## Where it fits

`next` is the **router** — the standalone map that sits over the whole set. It points into every
flow and carries the bounded chain when its gate approves. From here you'll most often land on
[grill-with-docs](./grill-with-docs.md), the head of the main flow, or [triage](./triage.md), the
on-ramp for work you didn't create. Its one hard prerequisite is
[setup-git-loopy-skills](./setup-git-loopy-skills.md), because the tracker config and chain hook
that skill writes are the state `next` reads. When even the router's own picture is stale, its
[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next) is the map of
record.
