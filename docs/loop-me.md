Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=loop-me
```

```bash
npx skills update loop-me
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/loop-me)

## What it does

`loop-me` runs a stateful [grilling](./grilling.md) session whose only output is **workflow specs**. Same discipline — relentless, a round of questions at a time, a recommended answer attached to each — pointed at one target: the recurring work in your life that is predictable enough to hand to something else.

It creates, edits, and deletes specs in `workflows/*.md` as the grilling resolves things, so the workspace is the running record rather than the transcript.

## When to reach for it

You invoke this by typing `/loop-me` — the agent won't reach for it on its own. Name a workflow to design, or pass nothing and let it go hunting for one.

Reach for it when you keep doing the same thing by hand and suspect you shouldn't be: the weekly report, the inbox pass, the release checklist. It is also the right entry point when you *can't* name the loop yet — the lens below is designed to surface ones you haven't noticed.

## The loop lens

A **loop** is a recurring pattern in your life: a career, a week, a morning, a single repeated activity. Picturing a life as loops within loops shows how predictable its activities really are — which is exactly what makes them worth **delegating**.

A **workflow** is the spec of one loop, made real. You run a workflow on a loop; the loop is its running instantiation.

## Vocabulary

Shared language, reached for only when a workflow calls for it — never a checklist. Nothing structural is mandated: a workflow needs no AI, no checkpoint, and no schedule unless the grilling shows it does.

- **Trigger** — what fires each run: an **event** (a new email, a new issue) or a **schedule** (every morning). Event-triggering is usually the more efficient.
- **Checkpoint** — a human-in-the-loop point where you are asked to verify or decide. Some workflows have none and run autonomously; some use no AI at all.
- **Push right** — defer the checkpoint as far as it will go. Do maximal work before involving the human, so they are asked once, late, with everything prepared.
- **Brief** — what a checkpoint presents: a tight, decision-ready summary — what was produced, why, and a link down to the asset itself — never the raw output. You read a brief, not a draft; speed of review is imperative.

## The workspace

- `workflows/*.md` — one spec per workflow, the source of truth.
- `NOTES.md` — raw notes on your world: the tools you use, the channels you process, and your own terminology for both. When it's empty or thin, expect to be interviewed about your world before anything gets specified.

A spec is done when an implementer agent could build it without asking a single question. The grilling continues until then — nothing is done while a question remains.

## Where it fits

`loop-me` is a standalone entry point that borrows the interview from [grilling](./grilling.md) and aims it at your life rather than a codebase — the same relationship [grill-with-docs](./grill-with-docs.md) has to a design. Its output is a spec an implementer can build, so it hands off naturally to [to-tickets](./to-tickets.md) and [implement](./implement.md) once a workflow is worth building. When you're unsure which skill fits the moment, [next](./next.md) routes you.
