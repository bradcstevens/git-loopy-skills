Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=to-tickets
```

```bash
npx skills update to-tickets
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/to-tickets)

## What it does

`to-tickets` takes a plan, a [spec](https://www.aihero.dev/ai-coding-dictionary/spec), or the conversation you are in, and breaks it into a set of **[tickets](https://www.aihero.dev/ai-coding-dictionary/ticket)** on your issue tracker. Each ticket declares its **blocking edges**: the other tickets that have to finish before it can start.

Every ticket is a **tracer bullet**: a narrow but complete path through every layer of the change (schema, API, UI, tests) that you can demo on its own as soon as it lands. This is what makes the skill different from the obvious way to split work, which is to cut one layer at a time and integrate at the end. It also sizes each ticket to fit in a single fresh [context window](https://www.aihero.dev/ai-coding-dictionary/context-window), because a [session](https://www.aihero.dev/ai-coding-dictionary/session) that has never seen your spec will pick the ticket up.

## When to reach for it

You can invoke the Skill with `/to-tickets`, or the workflow can call it through the Skill tool. Its former interactive persona and shell wrapper are retired. [to-spec](./to-spec.md) and [next](./next.md) instead hand configured repositories with `git-loopy` on `PATH` to `git-loopy plan <spec>`: a fresh interactive Planner session that uses this Skill and the published spec. The same-conversation Skill remains the non-git-loopy fallback.

| Where you are | What to run |
| --- | --- |
| You have a spec issue and the build spans several sessions | `/to-tickets`, or `/to-tickets #<spec_issue>` |
| The plan is only in the conversation, never written up | `/to-tickets` reads the thread directly, no spec needed |
| The whole change fits in one context window | [implement](./implement.md), skip the tickets |
| Nothing is decided yet | [grill-with-docs](./grill-with-docs.md), then [to-spec](./to-spec.md) |
| A [wayfinder](./wayfinder.md) map has cleared | [to-spec](./to-spec.md) first, to collapse the map, then `/to-tickets` |

Tickets that `to-tickets` produced are agent-ready by construction. Don't run [triage](./triage.md) over them. Triage is for work that arrived from someone else.

## Prerequisites

`to-tickets` publishes into a tracker, so [setup-git-loopy-skills](./setup-git-loopy-skills.md) must have configured one for this repo, along with the triage-label vocabulary. Either kind works: a real tracker like GitHub or Linear, or local markdown files under `.scratch/`, which work with no extra setup.

## Tracer bullets, not layers

A **horizontal** slice ships one layer of the change. Nothing works until every layer has landed, and each ticket's acceptance criteria have to reach into work that another ticket owns. A **vertical** slice (the tracer bullet) ships one thin path through all the layers at once, so it is verifiable alone and owns everything it grades.

This is the rule people break most often. One team ran a 26-ticket stack sliced by layer (corpus, producer, aggregator, selector) and got roughly twenty agent runs per closed ticket, about three quarters of them rework. Their own post-mortem traced every failure class back to the horizontal slicing rather than to the implementations.

Two things happen before anything is published. `to-tickets` looks for prefactoring (the principle "make the change easy, then make the easy change") and orders that work first. Then it presents the breakdown as a numbered list and quizzes you on it: is the granularity right, are the blocking edges real, should anything merge or split. Nothing reaches the tracker until you approve, and that quiz is the place to push back.

## Blocking edges

The edges are the point of the artifact. They work in two ways, depending on the tracker:

| Tracker | Where the edges live | How you work them |
| --- | --- | --- |
| Local markdown | Text in one file per ticket under `.scratch/<feature>/issues/<NN>-<slug>.md`, numbered blockers-first | Top to bottom, by hand |
| A real tracker (GitHub, Linear) | Native blocking links; a sub-issue link separately records parentage | Any ticket whose blockers are done is on the **frontier** and can be grabbed |

The edges live in the ticket either way. The tracker only decides whether anything can act on them in parallel. `to-tickets` produces the artifact; running it (one session at a time, or a fleet) is your job, not the skill's.

## Label each published ticket

Publication makes three separate decisions using the repository's configured label vocabulary: the `ready-for-agent` triage role unless instructed otherwise, exactly one `task-type:` label selected by dominant risk, and an independent `parallel-safe` decision. Agent-ready types are `implementation`, `test`, `docs`, `chore`, and `bugfix`; `planning` and `review` are human-only. Multiple or invented types can silently misroute work, and a missing parallel-safety assertion has no classifier fallback. Local tickets record the same decisions explicitly for later publication.

## Bound deliberate host load

Every acceptance criterion demanding deliberate host load must state the bounds in its own ticket, not rely on the parent spec: the macOS `utility` clamp (not `nice`), at most about 2x the logical CPUs including child workers, a per-invocation wall-clock cap (30 minutes unless the issue specifies one), inconclusive rather than pass on cutoff, no escalation or raised inherited priority, and owned-process cleanup after completion, failure, or interruption. Tighter bounds from the spec survive decomposition. Ordinary `AGENTS.md` feedback loops are exempt from those additional load limits, not from cleanup.

## Record the decomposition

Finish publishing and labeling the whole approved graph, then verify that its saved tickets and edges match the approved breakdown. Only then post one evidence comment on the spec parent naming the tickets, or record that evidence alongside the tickets if there is no source issue. A partial graph is not a completed decomposition. Do not close or edit the parent during this session; the evidence comment is the only exception. Closing a delivered parent is later bookkeeping.

## The wide-refactor exception

One shape breaks the tracer-bullet rule. A **wide refactor** is a single mechanical change (rename a column, retype a shared symbol) whose **blast radius** covers the whole codebase. One edit breaks thousands of call sites, so no vertical slice can land green.

`to-tickets` sequences that as **expand–contract** instead:

- **Expand**: add the new form beside the old, so nothing breaks.
- **Migrate**: move call sites over in batches sized by blast radius (per package, per directory), one ticket per batch, each blocked by the expand. CI stays green because the old form still exists.
- **Contract**: delete the old form once no caller remains, in a ticket blocked by every migrate batch.

Where even the batches can't stay green alone, they share an integration branch and all block a final integrate-and-verify ticket. CI only has to be green at that ticket.

## Common questions

**It produced twelve tickets for a three-line change.**
Over-decomposition is the most reported problem with this skill, and many users see it. The [model](https://www.aihero.dev/ai-coding-dictionary/model) defaults to atomic units and loses the grouping that would make them meaningful. The quiz step is where you fix this. Ask it to merge tickets, and it will. There is also a lower limit. If the whole change fits in one context window, you don't need this skill at all. Go straight to [implement](./implement.md).

**The tickets came out one per layer: all the schema in one, all the API in another.**
This is the failure the vertical-slice rule is written against, and the skill still produces it sometimes. Catch it at the quiz step by asking one question per ticket: what can I demo when this is done? A ticket with no answer is a horizontal slice. Some people add a "demo path" line to each ticket for this reason, and report that it pushes the model toward vertical slices.

**On GitHub the tickets weren't created as sub-issues of the spec issue.**
This was reported across a dozen runs and several models, [most fully in mattpocock/skills#554](https://github.com/mattpocock/skills/issues/554). Fixed: `to-tickets` now makes each ticket a sub-issue of its source issue. This repo carries the operation directly in the Skill: `gh api --method POST repos/<owner>/<repo>/issues/<spec>/sub_issues -F sub_issue_id=<child-db-id>`. The id is the child's numeric database id, not its issue number. Re-run [setup-git-loopy-skills](./setup-git-loopy-skills.md) to refresh an older `docs/agents/issue-tracker.md`.

**"Blocked by" was written into the issue body instead of a real blocking link.**
This is the same kind of problem, [reported in mattpocock/skills#513](https://github.com/mattpocock/skills/issues/513), where the agent even stated that GitHub has no native blocking relationship at all. It does: this repo uses `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. Fetch numeric database ids with `gh api repos/<owner>/<repo>/issues/<n> --jq .id`. Publishing blockers first makes them available when wiring each child. The body text is the fallback for trackers with no native edge, not the default. The ticket template omits `## Blocked by` when the edges are native.

**Where do the local tickets go? The v1.1 notes said a root-level `tickets.md`.**
They did, and that was a bug. A single shared file also caused race conditions when parallel agents wrote to it. Local mode now writes one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, in dependency order, matching the layout the local tracker template already described. The `NN` prefix is a real ticket ID, so `/implement 03` works instead of retyping a long title.

**It kept truncating when it tried to read my spec.**
A very large spec may need several tracker reads. The fresh Planner must read the durable spec in full; if it cannot, report the blocker rather than decomposing an incomplete input. The non-git-loopy fallback can use the existing conversation, but a failed Planner launch must not silently switch to that fallback.

**The acceptance criteria graded nothing: some passed before any work was done.**
The template asks for criteria and says nothing about whether they can fail, so this happens. Three shapes recur: a criterion already true at the base commit, a criterion that only work in another ticket can satisfy, and one that restates the request rather than deriving from the artifact. Vertical slicing prevents most of it, because a slice that delivers new behaviour fails at the base commit by construction. The check is still worth doing by hand. For each criterion, name the observation that would show it false, and confirm it fails at the commit the implementer starts from.

**The tickets are published. How do I actually run them?**
This repo's Skill records the graph, then calls [next](./next.md) to choose the next route. Decomposition itself does not implement tickets. The git-loopy runner can pick up executable tickets, or you can give [implement](./implement.md) one ticket per fresh session. Eligibility still depends on the saved blocking edges, not just a body label.

## It's working if

- Every ticket has an answer to "what can I demo when this is done?", and the answer is behaviour, not a layer.
- The list comes back to you numbered, with a "Blocked by" line on each, before anything is published.
- The ticket at the top has no blockers and can be started immediately.
- Nothing in a ticket body is a file path or a line number, except a snippet a prototype produced.
- Each ticket reads like something a fresh session could finish without you in the room.
- Prefactoring, where it found any, is at the front of the order rather than mixed into feature tickets.

## Where it fits

`to-tickets` is a step in the main build chain:

```txt
grill-with-docs → to-spec → to-tickets → implement → code-review → retro
```

Upstream is [to-spec](./to-spec.md), which hands it a settled spec to slice against through the fresh Planner or the same-conversation fallback. Downstream is [implement](./implement.md), which builds one ticket per fresh session, driving [tdd](./tdd.md) for the tests and closing with [code-review](./code-review.md). [implement-spec](./implement-spec.md) is the other way down. It reads the same blocking edges as a task graph and builds every ready ticket in parallel on one integration branch. When you're unsure which skill or flow fits, [next](./next.md) routes you.
