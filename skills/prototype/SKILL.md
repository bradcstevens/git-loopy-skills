---
name: prototype
description: Build a throwaway prototype to answer a design question. Use when the user wants to sanity-check whether a state model or logic feels right, or explore what a UI should look like.
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch

Identify which question is being answered — from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build a single shareable HTML file — free-play buttons plus tabbed guided walkthroughs — that pushes the state machine through cases that are hard to reason about on paper, and that a non-developer can drive.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious — but name it so a casual reader can see it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure.
2. **Trivial to run.** A UI prototype starts from one command in the project's task runner — `pnpm <name>`, `python <path>`, `bun <path>`, etc. A logic demo is a single HTML file the user double-clicks. Either way, no thinking required to start it.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is _checking_, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype _runnable_, no abstractions. The point is to learn something fast.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Capture it when done.** Fold any validated decision into the real code, then capture the prototype itself as a **primary source**: commit it to a throwaway branch, out of main, and leave a context pointer to that branch on the implementation issue. Capture the answer too — the verdict and the question it settled — in the issue or a commit. The main branch keeps only the validated decision.

## Owning the transition, or not

Most prototypes are **nested**: another skill — `/wayfinder`, `/grill-with-docs`, a tracer bullet
under `/implement` — needed something concrete before it could decide. A nested prototype records
nothing of its own; it hands its durable pointers back to the skill that asked: the throwaway
branch name and head SHA, and the comment recording the verdict. That skill records once, for the
transition it owns.

A prototype owns this record **only** when it was invoked directly on its own tracker ticket — a
`wayfinder:prototype` ticket, say — and durably resolves it. Then, and only then:

1. Push the throwaway branch and note its head SHA.
2. Post the verdict as a resolution comment on the ticket and **close the ticket**. That comment
   is the durable record of what the prototype found.

### When the question survives the session

Not every directly-owned ticket gets settled. If the prototype ran and the branch is pushed but the
question is still open — the experiment was inconclusive, or it answered a smaller question than
the ticket asked — leave the ticket open and post the inconclusive result as a comment anyway,
naming the branch, so the next session starts from that run rather than from scratch.

At the conclusion of a `/prototype` session invoked directly on a ticket, run `/to-spec` if the
verdict settles what to build, or leave the ticket open for a follow-up `/prototype` session.
