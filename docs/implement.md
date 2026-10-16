Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=implement
```

```bash
npx skills update implement
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/implement)

## What it does

`implement` builds work that has already been decided. You point it at a [ticket](https://www.aihero.dev/ai-coding-dictionary/ticket), a [spec](https://www.aihero.dev/ai-coding-dictionary/spec), or the plan you just agreed in the conversation, and it writes the code, drives [tdd](./tdd.md) at the seams, typechecks as it goes, commits and pushes to the current branch, then runs [code-review](./code-review.md) on that exact pushed head.

It does not reopen the plan or propose a different approach. It fetches a passed ticket reference from the tracker and states its title before starting; if the reference is ambiguous, it asks. Whatever was settled upstream is the input, and the skill's whole job is to turn that into a durable candidate. That is what separates it from typing "build this" at a fresh [agent](https://www.aihero.dev/ai-coding-dictionary/agent), which often redesigns the work while it builds it.

It also reconciles a branch with a moved remote head and resolves in-progress
merge, rebase, or cherry-pick conflicts. It reads both sides' primary sources,
preserves their intent, finishes the operation, and records the checked,
committed, pushed resolution on the ticket. The resolved head is a new candidate
and gets its own code review; a force push or missing authority stops for a human.

## When to reach for it

Type `/implement`, or let the agent reach it when a spec is ready or a branch needs reconciliation. This fork keeps `disable-model-invocation: false` so [next](./next.md) can route to it. [push](./push.md) also hands off here when the remote head has moved, naming the divergence.

Where the work currently lives decides whether this is the right skill:

| The work is... | Reach for |
| --- | --- |
| A ticket on the tracker | `/implement #42`, one ticket per [session](https://www.aihero.dev/ai-coding-dictionary/session), [clearing](https://www.aihero.dev/ai-coding-dictionary/clearing) context between tickets |
| A spec, not yet split up, and the build spans sessions | [to-spec](./to-spec.md)'s git-loopy Planner handoff, or [to-tickets](./to-tickets.md) outside git-loopy, then `/implement` per ticket |
| A spec, and the build is small | `/implement` directly against the spec |
| Only in the conversation you just had, and it's still small | `/implement` right there, in the same window |
| Not written down anywhere yet | [grill-with-docs](./grill-with-docs.md), or `grill-me` if there's no codebase |
| One concrete behaviour you want test-first, with no spec | [tdd](./tdd.md) directly |
| Already built, and you want it checked | [code-review](./code-review.md) directly |

The same-session case is worth naming because the skill's own first line doesn't cover it. `SKILL.md` says "the spec or tickets", which pushes the [model](https://www.aihero.dev/ai-coding-dictionary/model) to look for a file that doesn't exist. If the plan lives only in the thread, say so when you invoke it.

## Prerequisites

`implement` commits to the branch you are on. It does not create one, and it does not ask. Check you are on the branch you want the work on before you start.

If the tickets came from the git-loopy Planner or [to-tickets](./to-tickets.md), [setup-git-loopy-skills](./setup-git-loopy-skills.md) configured the tracker they live on. `code-review` reads the same configuration to find the originating spec at close-out.

## What one run does

A run has five steps, in order:

1. Fetch the ticket or read the spec, state the ticket's title, and work out the seams. Ask if the reference is ambiguous.
2. Drive [tdd](./tdd.md) at the pre-agreed seams, one red-green slice at a time.
3. Typecheck often, run single test files as it goes.
4. Run the full test suite once, at the end.
5. Commit to the current branch, push, record the candidate SHA on the ticket, then call the Skill tool with "code-review" to review that exact head.

One run covers one ticket. The tickets [to-tickets](./to-tickets.md) produces are tracer-bullet vertical slices sized to fit a single fresh [context window](https://www.aihero.dev/ai-coding-dictionary/context-window), so the intended rhythm is: clear context, implement one ticket, commit, clear again. Each ticket is self-contained, so you can discard the previous ticket's context.

## Record the implementation

The candidate is durable only after validation, commit and push. The evidence comment
names its exact SHA and what changed; the successor reviews that head, never an
uncommitted worktree or a later branch tip. Remediation or conflict resolution produces
a new candidate requiring a fresh review.

Never widen authority to finish: a login, MFA, secret, consent prompt, or missing privilege
stops the run. A criterion requiring human judgement is called out on the ticket and
leaves it open. Nested [tdd](./tdd.md), [codebase-design](./codebase-design.md),
[domain-modeling](./domain-modeling.md) and documentation lookups return evidence to
the implementation owner rather than recording a second transition.

## Pre-agreed seams

The skill's central idea is the **seam**, the public boundary you observe behaviour at without reaching inside. Tests live at seams. When the seam is agreed before any code exists, the tests last, and you can rewrite the implementation underneath without changing them.

The "pre-agreed" part matters, and it is also the skill's weakest point. Nothing inside `implement` agrees the seams. `tdd` is the skill that asks, and it refuses to write a test at an unconfirmed seam. So in practice the agreement happens either upstream in the spec, or in the first exchange of the run. If it happens nowhere, the run becomes "just write the code" and nothing warns you. Naming the seams in the spec is what stops that.

## Common questions

**It finished, but my ticket is still open and the acceptance criteria are still unchecked.**

Check its evidence comment. This fork records the pushed candidate and routes it to review, but a candidate is not a promise that subjective acceptance is satisfied. When a human must judge an acceptance criterion, the ticket deliberately stays open. Review findings return to `/implement` for remediation and a new review; ticket closure still follows the caller's tracker contract.

**Can I point it at all my tickets at once, or run several in parallel?**

Not with `/implement`: one invocation, one ticket. [implement-spec](./implement-spec.md) handles a whole spec on one integration branch. Running several `/implement` sessions side by side in one checkout is worse than unsupported. One field report describes a `git commit --amend` in one session landing on another session's commit, a stash vanishing from `refs/stash`, and commits landing on the wrong branch, all in a single afternoon across three issues. The sessions share one working directory, one index, and one HEAD. Users work around this with git worktrees, but `refs/stash` is shared across worktrees too, so worktrees alone do not fix the stash case.

**Can it open a pull request instead of committing?**

It still commits to the current branch and pushes the candidate before review. A clean review routes to [push](./push.md), which owns publishing the pull request. Choose the intended feature branch before starting; committing a candidate is not merging it into the default branch.

**`code-review` says it cannot see my changes.**

`code-review` reviews `git diff <fixed-point>..."$reviewed_head"`, which excludes staged and working-tree changes. This fork avoids upstream's ordering problem by committing and pushing first, then reviewing the pinned candidate against the point you branched from. Uncommitted follow-up edits are not part of that review.

Separately, some people do not want the review inside the run at all, because an agent reviewing the code it just wrote is biased toward its own solution. Running [code-review](./code-review.md) in a fresh session against a fixed point is a valid alternative. The same bias is why that skill runs its two axes in separate sub-agents.

**One ticket burned 150k tokens. Am I using it wrong?**

Probably not. The ticket is more likely too big. A run does codebase exploration, a red-green loop per seam, a full suite, and a review, so a non-trivial ticket exceeding 100k [tokens](https://www.aihero.dev/ai-coding-dictionary/token) is normal rather than a sign something broke. The fix is upstream. Right-size the tickets in [to-tickets](./to-tickets.md) so each fits one fresh window. If a single ticket keeps going over, split it rather than raising the [effort](https://www.aihero.dev/ai-coding-dictionary/effort) level.

**`/implement #2` in a fresh session worked on something completely unrelated.**

The agent resolved `#2` against another numbered list in context, such as a todo file or checklist, rather than the configured tracker. `implement` now fetches a passed reference from the issue tracker and states its title before starting, and asks when the reference is ambiguous. Check that title matches the ticket you meant; passing the issue URL or `owner/repo#2` removes the ambiguity entirely.

## It's working if

- The session opens by reading the ticket or spec and restating what it will build, rather than asking you what to build.
- You can see an actual `tdd` Skill tool call in the trace, not just tests appearing in the diff.
- Typechecks and single test files run repeatedly during the run, and the full suite runs once near the end.
- The run reaches a pushed commit on your current branch, records its SHA, then reviews that exact head without you prompting it to carry on.
- The diff is one ticket's worth of change: a vertical slice through every layer, not several tickets swept together.

## Where it fits

`implement` is the build step of the main chain:

```txt
grill-with-docs → to-spec → git-loopy plan → implement → code-review → push
```

Its neighbours are the git-loopy Planner (or [to-tickets](./to-tickets.md) outside git-loopy), which produces the tickets it consumes and declares the blocking edges that decide their order; [tdd](./tdd.md), which it drives internally at each seam; and [code-review](./code-review.md), which it runs after committing and pushing. It sits downstream of the planning skills and trusts them. It does not re-validate the shape of what it was handed, so a badly-structured map or a horizontally-layered ticket gets built as written.

That trust is why [wayfinder](./wayfinder.md) merges onto the chain at [to-spec](./to-spec.md) rather than looping its map straight into `implement`. Go straight to `implement` from a map only when the effort turned out small.

[next](./next.md) is the router over the whole set when you are not sure which flow you are in.
