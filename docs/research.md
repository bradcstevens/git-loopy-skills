Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=research
```

```bash
npx skills update research
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/research)

## What it does

`research` answers a question by reading the sources that own the answer, then leaves a cited Markdown file in the repo. It works only from **[primary sources](https://www.aihero.dev/ai-coding-dictionary/primary-source)**: official docs, source code, specs, first-party APIs. It follows every claim back to the source that owns it, so it will not repeat a blog post's account of an API when the API's own docs are reachable.

It does not answer you in the conversation. The output is a file, written where the repo already keeps such notes, with a link on each claim. You get a document you can react to, hand to another agent, or throw away, rather than an answer that is gone when the [session](https://www.aihero.dev/ai-coding-dictionary/session) ends.

## When to reach for it

Type `/research`, or the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) reaches for it automatically when a task turns into reading legwork.

Reach for it when the next step is *finding something out* from outside the working directory (how a third-party API behaves, what a spec says, whether a version claim holds), and you'd rather not stall your own thread doing the reading. What you need decides which skill:

| What you need | Reach for |
| --- | --- |
| An external fact a decision is waiting on | `research` |
| A decision made *with* you, by interview | [grilling](./grilling.md) |
| A durable architecture decision, written into `GLOSSARY.md` and ADRs | [grill-with-docs](./grill-with-docs.md) |
| To find out whether an approach works in your codebase | [prototype](./prototype.md) |
| A plan too big to hold in one session | [wayfinder](./wayfinder.md) |

The line between `research` and `grill-with-docs` is the **shelf life of what comes back**. Research produces short-lived facts, such as what this library's auth mechanism does as of this week. An ADR records a decision you keep. If what you are producing is a decision rather than a fact, you are [grilling](https://www.aihero.dev/ai-coding-dictionary/grilling), not researching.

## Delegated legwork

The reading runs as a **background agent**. You keep working while it follows each claim to its primary source, writes one Markdown file, and reports back. Research is legwork you delegate, not thinking you outsource. You get a document to grill, plan, or design against, and you still make the decision.

Nothing stops the background agent from spawning another background agent of its own. This is the skill's best-documented problem.

The repo decides where the file goes, not the skill. It follows whatever convention already exists for notes. If there is none, it picks a sensible place and tells you where. It writes one file per run.

For Microsoft technologies such as Azure or Copilot Studio, call the Skill tool with
"microsoft-docs". That [Microsoft documentation lookup](../skills/microsoft-docs/SKILL.md) runs inside
the research, and its primary-source citations belong in the same findings file.

## Owning the transition, or not

Nested research returns the findings path, commit SHA and branch to the skill that
asked; it records no separate transition. When research was invoked directly on its
own tracker ticket, commit the findings, post the answer and close the ticket only
when its question is answered. Partial findings leave the ticket open with an evidence
comment so the next session starts from what was learnt.

For directly owned tickets, a settled answer routes to [to-spec](./to-spec.md) if a spec
is needed, or [implement](./implement.md) if settled work is ready to build. Otherwise,
leave the question open for another research session.

## Common questions

**It spawned a second research agent. Is that meant to happen?**

No. This is an open upstream bug, [mattpocock/skills#530](https://github.com/mattpocock/skills/issues/530). The skill tells its caller to spin up a background agent but does not restrict the agent type. A `general-purpose` agent with delegation tools and the same instructions can follow them again. One reporter measured a single research task costing roughly 450k [tokens](https://www.aihero.dev/ai-coding-dictionary/token) across three overlapping runs, and the duplicate finished half an hour later where the user could not see it. The failure is not specific to one harness; users also confirmed nesting in Codex with GPT-5.6-sol. The pinned upstream skill has no shipped fix. Users have patched their installed copy to tell an agent that is already a [subagent](https://www.aihero.dev/ai-coding-dictionary/subagent) to do the work itself. That helps, but it is only an instruction, not a structural fix. In Copilot CLI, respect the caller's delegation limits and watch the background task list.

The opposite failure also happens. If your own global instructions forbid an agent from re-delegating work, the background agent declines the task, and the skill does nothing without telling you.

**Where should the file live, and should I commit it?**

The skill puts the file where the repo already keeps notes. Upstream leaves retention to the caller, and its community favours keeping ADRs rather than stale research files. This fork's transition overlay needs durable evidence: directly owned tickets commit the findings, and nested research returns the commit and branch carrying them. Use the repo's convention or a throwaway research branch, not an uncommitted file that the next session cannot read. Keep the date and scope visible; facts can go stale even when their pointer remains valid.

**What counts as a "high-trust" primary source, and who decides?**

The [model](https://www.aihero.dev/ai-coding-dictionary/model) does. The skill names the *kinds* of source that qualify (official docs, source code, specs, first-party APIs), and there is no allowlist, no domain gate, and no verification pass. This was the loudest objection when the skill was first proposed, and nobody has answered it publicly: "Five research subagents pointed at junk just gives you five confident wrong answers faster. How are you gating what counts as high-trust sources?" Your only protection is the citation on each claim. Follow two or three of them. If they land on a summary of the thing rather than the thing, the run failed.

**Does a later session reuse what an earlier run found?**

Nothing loads a past research file automatically. This fork makes the pointer durable: a nested run hands it to the owning skill, and a directly owned [ticket](https://www.aihero.dev/ai-coding-dictionary/ticket) gets an answer or partial-findings comment. The next session still has to follow that pointer. Attach it to a spec or quote it into a grilling session instead of treating a write-once file as memory.

**Why not just ask the agent to go read the docs?**

You can, and a two-line prompt saying exactly that was the practice this skill replaced. The skill gives you two things the prompt does not. It runs in the background, so your session's [context](https://www.aihero.dev/ai-coding-dictionary/context) stays clean. And the primary-source constraint and the cited-file output are the same every time, rather than depending on how you phrased the prompt. Compared with a [harness](https://www.aihero.dev/ai-coding-dictionary/harness)'s own deep-research mode, the difference is the file and the primary-source rule, not the search. If a two-line prompt gets you what you need on a small question, use the two-line prompt.

**When does it stop reading?**

The skill has no stopping criterion. This shows up as two complaints that look opposite but have the same cause: agents that go far too deep, and agents that cover a topic broadly but miss the one detail that mattered. One practitioner put it as "deep-research skills are a bit too deep sometimes. And telling an agent to research usually results in missing crucial details." You have to set the scope. A narrow, answerable question (one API, one behaviour, one version claim) comes back far better than "research X".

**`/wayfinder` created research tickets. Do I resolve those myself?**

No, it now fires them for you. In the unreleased changes since v1.1, a charting session spawns one `/research` subagent per research ticket and runs them in parallel. Each one records its findings on a throwaway `research/<name>` branch, with a [context pointer](https://www.aihero.dev/ai-coding-dictionary/context-pointer) from the ticket. Research tickets are the one exception to wayfinder's one-ticket-per-session rule, because they are [AFK](https://www.aihero.dev/ai-coding-dictionary/afk): nothing waits on you. One known problem: deleting the branch later breaks the context pointers in the tickets.

## It's working if

- Your own session keeps going. If you are sitting watching it read, the delegation didn't happen.
- Exactly one new background task appears. A second one with a near-identical name is the nesting bug.
- One new Markdown file shows up, in the folder the repo already uses for notes, and the agent tells you the path.
- Every claim in it carries a link, and following two at random lands you on an official doc, a spec, or the source file itself, not on someone's write-up of it.
- You can make the decision you were stuck on from the file alone, without going back to the sources yourself.

## Where it fits

`research` is a reach-for-it-anytime standalone. It feeds the thinking skills and is not a step in the build chain. You take its file *into* the flow. [grilling](./grilling.md) and [grill-with-docs](./grill-with-docs.md) ask sharper questions when they already have the facts, and [to-spec](./to-spec.md) can synthesise against it. [wayfinder](./wayfinder.md) is the one skill that invokes it directly. It resolves each research ticket on its map with a `/research` subagent. For the whole map, see [next](./next.md).
