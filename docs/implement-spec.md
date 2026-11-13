Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=implement-spec
```

```bash
npx skills update implement-spec
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/implement-spec)

## What it does

`implement-spec` takes a [spec](https://www.aihero.dev/ai-coding-dictionary/spec) and its [tickets](https://www.aihero.dev/ai-coding-dictionary/ticket) and lands the whole thing in one run. The orchestrating [agent](https://www.aihero.dev/ai-coding-dictionary/agent) hands each ticket to an implementer [subagent](https://www.aihero.dev/ai-coding-dictionary/subagent) working in its own git worktree, merges each finished branch into a single **integration branch**, runs [code-review](./code-review.md) over the result, and resolves the tickets.

It reads the tickets as a **task graph**, not a list. Blocking edges decide what can start, so at any moment there is a **frontier** of tickets whose blockers have all landed, and every ticket on the frontier can run at once. That is the difference from working the tickets one by one. The graph's shape sets the pace, not the tickets' order on the tracker.

Copilot execution respects the harness limit and caps the run at ten in-flight subagents, including exploration and mergers. Additional ready tickets wait for a slot.

Here, landing means integration, not merging to the default branch. Each ticket gets an evidence comment naming its merge commit. The spec gets one evidence comment with the integration branch or draft PR, review outcome and cleanup results, then the run routes through `/next`.

## When to reach for it

You invoke this by typing `/implement-spec`, and the agent won't reach for it on its own.

| Your situation | Reach for |
| --- | --- |
| A spec, split into tickets with blocking edges, that you want landed in one run | `/implement-spec` |
| One ticket at a time, in your own [context window](https://www.aihero.dev/ai-coding-dictionary/context-window), [clearing](https://www.aihero.dev/ai-coding-dictionary/clearing) between tickets | [implement](./implement.md) |
| A spec that isn't split into tickets yet | [to-spec](./to-spec.md)'s Planner handoff, or [to-tickets](./to-tickets.md) outside git-loopy |
| A small piece of work with no real graph to it | [implement](./implement.md) directly |

## Prerequisites

- **An issue tracker.** The skill reads the tickets from, and resolves them on, the tracker [setup-git-loopy-skills](./setup-git-loopy-skills.md) configured. If none has been configured, it stops and tells you to run that first rather than guessing.
- **Tickets with blocking edges**, as the git-loopy Planner or [to-tickets](./to-tickets.md) writes them. Without edges the graph is flat and every ticket can start at once.
- **A [harness](https://www.aihero.dev/ai-coding-dictionary/harness) that runs subagents in the background and gives each one a git worktree.** Here, implementer, merger and exploration roles use Copilot CLI background `task` agents with write access. The orchestrator creates their worktrees and tracks ownership; the tool does not provide isolation automatically.

## The integration branch

Everything lands on one branch. Each implementer:

1. confirms its worktree is based on the integration branch before it starts, without resetting away work,
2. builds its ticket with [tdd](./tdd.md), red-green one slice at a time,
3. merges the integration branch tip into its own branch before reporting done.

One merger at a time integrates finished tickets with `git merge --no-ff` and runs the declared feedback loops on the merged tree. Unlike upstream's fast-forwards, these merge commits give the evidence comments an exact per-ticket integration SHA. If the integration tip moved meanwhile, the merger reconciles it before declaring success. A failed merge or check stops dispatch until repaired.

The tracker decides whether a pull request exists at all. If your tracker closes work through PRs, or you ask for one, the skill opens a draft PR after the first merge and marks it ready at the end once checks pass and findings are addressed. Otherwise the run resolves each ticket the way your tracker closes work, which works fully offline against a local markdown tracker.

Implementers talk to the orchestrator through [context pointers](https://www.aihero.dev/ai-coding-dictionary/context-pointer) (the spec, the ticket, shared exploration notes, earlier commits) rather than pasted summaries. This keeps each subagent's prompt small and leaves room in the orchestrator's window for the graph.

## Common questions

**How is this different from running `/implement` on each ticket myself?**

This is the question the skill exists to answer. Before it shipped, people kept building their own versions, and one user described the need: they wanted "subagents implement the tickets" instead of having "to individually create new session and tell them to implement a ticket one by one, when a spec may contain over 5 tickets." With `implement` you are the dispatcher: one [session](https://www.aihero.dev/ai-coding-dictionary/session) per ticket, clearing in between, and keeping track yourself of which tickets are unblocked. `implement-spec` hands that job to one orchestrating session. The price is that you no longer read each ticket's work as it lands; you review the integration branch at the end. To start a run, clear the context and type `/implement-spec` with a pointer to the spec (an issue number or a file path). For a small change with no real graph, skip it and use `implement` directly.

**Does it need GitHub? I want it to stop at the branch.**

No, not any more. One user who liked the in-progress version had exactly this complaint: "it creates a PR at the end, which requires an online repository like GitHub. I wish it could do the same work offline and stop at the branch where all the work is merged." A PR opens only when the configured tracker closes work through PRs or you ask for one. On a local markdown tracker the run retains the integration branch as its deliverable and appends evidence to the tickets and spec. With a remote tracker it publishes and verifies the integration head before deleting its local branch; the published branch or PR remains the deliverable.

**Its review and fix loop ran for hours, or kept "fixing" tickets that hadn't been built yet.**

Both happen when `code-review` runs anywhere other than the one point the skill gives it. It compares the code against the whole spec, so it only makes sense once every ticket has landed. If it runs mid-run, every unbuilt ticket reads as a failure. The agent then builds that ticket, and that triggers another review. One user reported a five-ticket feature where "the review and fix loop took roughly four hours".

Here the run requests one read-only review of the integration head against the starting base, with findings returned to the orchestrator rather than a nested transition. It sends every finding to one fix subagent, merges the fixes, runs focused checks plus the declared feedback loops, and stops the broad review loop. If fixes changed the head, the spec evidence says that the new head has not yet been reviewed. `/next` decides the next gate; a clean review of the old head never authorizes the changed one.

**Does it drive tdd like implement does?**

It does now, though it didn't at first. Users running the in-progress version noticed that "the implementer subagents don't inherit the /tdd directive", so red-green stopped as soon as they scaled up from one ticket to a whole spec. Each implementer now builds its ticket with `tdd`. There is still no step where you agree seams interactively, as there is in an `implement` session, so name the seams in the spec or the tickets if you want them pinned.

**Two implementers running in parallel collided on the same file, or picked different names for the same thing.**

Worktrees don't remove collisions; they postpone them to merge time. A blocking edge written from ticket text is a guess about which files each ticket will touch, and two tickets on "different parts of the codebase" still share a message catalogue, a config registry, or a type. Each implementer sees only its own ticket and the shared notes, never the other's work in progress, so one user's web and mobile tickets added the same string as `blockedSince` and `blockedOn`. When two frontier tickets touch one shared file, either add a blocking edge between them so they run one after the other, or have the exploration notes fix the exact names each ticket adds.

**Blocked tickets never start, even after their blocker has merged.**

This is a known problem on GitHub. The tracker's blocked-by count only drops when a blocker *closes*, and tickets typically close when the PR merges, which is the end of the run. The tracker is the right source for the starting graph but a stale one mid-run. This adaptation tracks which tickets have merged and passed checks on the integration branch and computes the frontier from that. External blockers still need resolution; failed tickets do not unblock dependents.

**Does this replace Sandcastle or an AFK script?**

No. People ask because the skills now reach into implementation: "is Sandcastle still relevant? Your skills now seem to be able to handle implementation as well." `implement-spec` puts an agent in charge of orchestration inside one harness session, which needs no infrastructure and lets you watch and steer. For work that is truly [AFK](https://www.aihero.dev/ai-coding-dictionary/afk), a deterministic loop ([Sandcastle](https://github.com/mattpocock/sandcastle), git-loopy, a shell script, a CI job) is faster, cheaper, and more reliable, because no agent makes the orchestration decisions.

**A ticket's key test was skipped inside its worktree, and it reported green.**

A worktree holds only what git tracks. Tests that read gitignored fixtures, local databases, or credentials can silently skip there. For a ticket whose verification depends on untracked material, explicitly arrange that verification in a permitted checkout rather than treating a skipped test as green. Never borrow another session's worktree.

**What happens to the worktrees and branches?**

The orchestrator inventories everything it creates, including merger, exploration, integration and review-fix worktrees. On success, failure or cancellation it waits for or stops its agents, preserves their work, restores the starting checkout, removes every clean run-owned worktree, and deletes branches whose commits are preserved. It never force-removes dirty worktrees, deletes the sole copy of work, or removes pre-existing artifacts. A retained worktree or branch is reported with its path/ref, reason and recovery action; cleanup is explicitly incomplete. The integration deliverable remains available remotely or, for offline work, locally until the user integrates it.

## It's working if

- Several implementers are running at once whenever the graph allows, not one after another.
- A ticket starts as soon as its last blocker lands and passes checks on the integration branch, not when the whole run ends.
- Every ticket's trace shows `tdd` running, with a failing test before the code.
- Merges into the integration branch are serialized, checked, and recorded by SHA in per-ticket evidence comments.
- The run ends with one integration deliverable, one spec evidence comment and a route through `/next`; cleanup removes run-owned artifacts or explicitly reports what could not safely be removed.

## Where it fits

`implement-spec` is the build step of the main chain, as the parallel alternative to running [implement](./implement.md) once per ticket:

```txt
grill-with-docs → to-spec → Planner (or to-tickets) → implement-spec → next
```

Its neighbours are the git-loopy Planner and [to-tickets](./to-tickets.md), which declare the blocking edges it reads as a task graph, and [code-review](./code-review.md), which it runs over the integration branch before closing out. [next](./next.md) is the router over the whole set when you are not sure which flow you are in. Adding incoming routing from `/next` is separate work; this skill remains user-invoked.
