Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=continuation
```

```bash
npx skills update continuation
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/continuation)

## What it does

`continuation` reports what git-loopy's **Workflow Continuation contract** already recorded as the next thing to do. Eleven skills in this repo publish a durable record when they finish a transition they own; this one binds a single request, runs `git-loopy continuation reconcile`, and presents exactly what came back.

It **derives nothing**. Trust, ordering, readiness, and the Waiting/guidance/Complete status are all computed by the command, from records the owners published — so the answer is the contract's, not a reconstruction of it. That is the whole point: a reconstruction can disagree with the record, and a session that acts on the disagreement acts on fiction.

It is also strictly read-only. It never publishes, never repairs the index, never closes an issue or edits a label. A question about what to do next may not change what is true.

## When to reach for it

This one is model-invoked — the agent can reach for it on its own. You can also invoke `/continuation` directly.

Reach for it when a run has published records and you want the contract's own answer: resuming a workstream another session left behind, or checking what a git-loopy run recorded before you pick the work back up.

It needs two things to be useful: a git-loopy distribution on `PATH`, and published records to read. Without the distribution, the command it calls does not exist. Without records, it honestly reports **Waiting**.

## Waiting is not Complete

The three statuses each have exactly one honest reading, and the easiest mistake is collapsing the first two:

- **Guidance** — a frontier exists; the Primary Action is the one to take.
- **Waiting** — nothing is currently derivable, and no workstream has a terminal outcome.
- **Complete** — every discovered workstream has an explicit destination-satisfied outcome.

An empty action list is **Waiting**, never Complete. Reconciliation only sees workstreams a transition owner has adopted, so unadopted work is invisible here — a reason to publish, not a reason to guess. A repository where nothing has ever published reports Waiting forever, and that is the contract being truthful rather than a fault.

## The Instruction

The payload is the **Instruction**: one line, rendered in its own fence so it can be copied in a single sweep. Its mode says where it goes — a `skill` instruction is a canonical skill invocation beginning with `/`, pasted back to an agent; a `command` instruction goes to a terminal; a `manual` instruction is work a human performs, with nothing to paste.

The producer authored that line. This skill presents the one it was handed and composes no invocation of its own.

## Where it fits

`continuation` is the reader at the end of the contract the publishing skills feed — [implement](./implement.md), [code-review](./code-review.md), [to-spec](./to-spec.md), [to-tickets](./to-tickets.md), [triage](./triage.md), and the rest record a transition as they finish it, and this skill is what reads them back.

Its neighbour is [next](./next.md), and the two answer the same question from opposite sources: `next` derives a recommendation from live project state, while `continuation` reports what was published. Prefer `continuation` when records cover the workstream; when it reports Waiting, `next` is the answer.
