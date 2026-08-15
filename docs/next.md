Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=next
```

```bash
npx skills update next
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next)

## What it does

`next` is the router over the skills in this repo. It reads the live state of your work and returns a single recommendation: the one action to take now, the skill that performs it, the exact invocation to paste, and the runtime to run it on — model, reasoning effort, and context tier.

It **does no work itself**. It doesn't grill, write a spec, or fix anything — it leaves the repository and the issue tracker exactly as it found them and only orients. What separates it from a checklist is where it looks: not at what you told it in conversation, but at `docs/agents/issue-tracker.md`, the tracker itself, and your branch and diff. Concurrent sessions move that state underneath you, so the recommendation is drawn from live records rather than from a session summary.

## When to reach for it

This one is model-invoked — the agent reaches for it on its own when a workflow skill concludes and the next step is unclear. You can also invoke `/next` directly.

Reach for it whenever you're unsure which skill or flow a situation calls for: a skill just finished and you don't know what follows, you have an idea and don't know where to start, or two skills look interchangeable and you can't tell them apart. If you already know the skill you want, skip the router and invoke it directly.

## The earliest unresolved gate

The idea `next` runs on is the **gate** — the first unresolved condition standing between the work and its destination. The flow is composable, not a fixed sequence, so it doesn't ask "which step comes after the last one" but "what is the earliest thing still unresolved". An idea that still has human decisions in it gates on grilling; an agreed destination with no durable spec gates on [to-spec](./to-spec.md); an unblocked ticket gates on [implement](./implement.md). Ranking follows from that: ready actions before blocked ones, the workstream you're already in before a cold one, and the action that clears the most downstream blockers before the rest.

Every recommendation is labelled **HITL** or **AFK-safe** — whether the next action needs your judgement, or is specified tightly enough to be left to run on its own. Blocked actions are still returned, but must name the condition that would make them ready.

## The runtime it sizes

A recommendation also names the **runtime** to run it on: `--model`, `--effort`, and `--context`, sized to the demand of the route it picked. Open judgement — grilling, wayfinding, spec writing, hard diagnosis — draws the strongest reasoning model at `xhigh`; ordinary build and review work draws a strong general model at `high`; mechanical, fully specified work draws a fast model at `medium`. An **AFK-safe** action gets one level more effort, because no human is mid-flight to catch a thin pass, and `long_context` is reserved for runs that must hold more at once than one default window holds. The flags come out verbatim, so [handoff](./handoff.md) can splice them straight into the background agent it launches.

## It's working if

- You get back exactly one action, with a live target — a linked issue, PR, spec, branch, or the current conversation — and never a menu of possibilities.
- The recommendation names whether to continue in this context or start a fresh session, matching the flow's own rules: grill → spec → tickets stays in one context, each `/implement` ticket starts in a new one.
- In a repo that was never configured, it routes to [setup-agent-skills](./setup-agent-skills.md) and nothing else.
- When the work is genuinely finished, it says so instead of inventing a next step.

## Where it fits

`next` is the **router** — the standalone map that sits over the whole set. It is the node every other docs page links back to, so it never sits *in* a chain; it points *into* every chain. From here you'll most often land on [grill-with-docs](./grill-with-docs.md), the head of the main flow, or [triage](./triage.md), the on-ramp for work you didn't create. Its one hard prerequisite is [setup-agent-skills](./setup-agent-skills.md), because the tracker config that skill writes is the state `next` reads. Its counterpart is [continuation](./continuation.md), which answers the same question from the opposite source — what git-loopy's runs published, rather than what `next` derives from live state. When even the router's own picture is stale, its [Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next) is the map of record.
