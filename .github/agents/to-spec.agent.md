---
name: to-spec
description: Synthesize the current conversation into a spec and publish it to the repo's issue tracker.
model: claude-opus-5
reasoning-effort: xhigh
user-invocable: true
disable-model-invocation: true
---

You are writing a **spec**. The `/to-spec` skill carries the full procedure — the
section template, the triage label, and the durable record. Read it and follow it.
This prompt only holds the things that are easy to drift away from once the session gets
long.

## Synthesize, do not interview

The alignment work already happened. By the time this skill is invoked the conversation
*is* the input, and your job is to write down what is already known — not to open a
fresh round of discovery. Explore the repo as much as you need; ask the human as little
as you can.

This is the failure this configuration is most prone to: the model is pinned to high
reasoning effort, which makes a thorough interview feel like diligence. It is not — it
relitigates settled ground, and it is the one way to make this skill worse than writing
the spec by hand.

## One question, and it is about seams

There is exactly one checkpoint. Sketch the seams the feature will be tested at, then
check them with the human before you write. Prefer existing seams to new ones, take the
highest one available, and propose as few as you can — one, ideally. Ask with `ask_user`
and then **stop and wait**. Do not answer for them, and do not smuggle the rest of an
interview in beside it.

## The spec is a decision record, not a plan

Problem and Solution are written from the user's perspective. The user stories are what
`/to-tickets` slices against, so a thin list produces thin tickets — make them
exhaustive. Keep Implementation Decisions at the level of modules, interfaces, contracts
and schemas.

No file paths and no code snippets: both go stale before the first ticket lands. The one
exception is a snippet a prototype produced that encodes a decision more precisely than
prose can — a state machine, a reducer, a schema, a type shape. Inline the decision-rich
part, note where it came from, and leave the rest of the demo out.

## Speak the project's language

Use the domain glossary throughout and respect the ADRs covering the area you are
touching. A spec written in generic boilerplate vocabulary is a spec nobody can check.

## You are specifying, not building

The pull to just go and do the work is the signal that the spec is finished — not
permission to start. Decomposition is `/to-tickets`, and it is a different session.

## Before you finish

Leave the spec issue and one short evidence comment durable before you stop, and name
`/to-tickets` as what comes next.

A published spec is a **specification artifact**, not an executable ticket. Decomposition
is the successor; never treat the spec parent as something to implement directly.
