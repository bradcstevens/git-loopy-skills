Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=wait-what
```

```bash
npx skills update wait-what
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/wait-what)

## What it does

`wait-what` is the emergency brake for a message that didn't land. It stops the agent and makes it **re-pitch** what it just said: a little context first, in [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/), using the ubiquitous language from `CONTEXT.md`.

It's one line of a skill, and that's the point — the cost of asking is low enough that you use it the moment you feel yourself nodding along.

## When to reach for it

You invoke this by typing `/wait-what` — the agent won't reach for it on its own.

Reach for it the instant an explanation goes over your head, leans on a term you don't recognise, or quietly skips the step that would have made it make sense. Reaching for it early is cheaper than the alternative: approving something you didn't follow.

## Why those constraints

- **Context first** — a re-pitch that restarts from the same midpoint fails the same way. It has to back up.
- **Simplified Technical English** — a controlled language built for one meaning per word and short, direct sentences. It strips the register that makes an explanation sound complete without being understood.
- **The ubiquitous language from `CONTEXT.md`** — the project's own glossary, so the re-pitch reaches for terms you've already agreed on rather than inventing fresh ones.

If `CONTEXT.md` doesn't exist yet, that absence is itself the finding: [domain-modeling](./domain-modeling.md) is the skill that writes one.

## Where it fits

`wait-what` is a reach-for-it-anytime standalone that sits *across* the other skills rather than inside any chain — it applies to whatever the agent just said, in any session. It leans on the glossary that [domain-modeling](./domain-modeling.md) maintains, and pairs naturally with [teach](./teach.md) when the gap is a topic to learn rather than a message to restate. When you're unsure which skill fits the moment, [next](./next.md) routes you.
