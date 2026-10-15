Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=code-review
```

```bash
npx skills update code-review
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/code-review)

## What it does

`code-review` pins `reviewed_head` from `HEAD` (or the candidate you name) and reviews its diff against a fixed point you name (a commit, a branch, a tag, `main`, `HEAD~5`) along two axes. **Standards** asks whether the code follows how this repo writes code. **Spec** asks whether the code does what the originating issue or [spec](https://www.aihero.dev/ai-coding-dictionary/spec) asked for. Each axis runs in its own [sub-agent](https://www.aihero.dev/ai-coding-dictionary/subagent) so neither sees the other's reasoning. Both calls are issued together in the foreground, and their returned reports are aggregated.

The skill never merges or re-ranks the two axes. The report ends with a worst issue *per axis* and declines to name a single winner across them. A change can pass one axis and fail the other. Code that follows every convention but implements the wrong thing passes Standards and fails Spec. Code that does exactly what the [ticket](https://www.aihero.dev/ai-coding-dictionary/ticket) asked but breaks the repo's conventions does the reverse. A blended verdict lets the passing axis hide the failing one.

## When to reach for it

Type `/code-review`, or the agent reaches for it automatically when you ask to review a branch, a PR, work in progress, or anything "since X".

| Your situation | Reach for |
| --- | --- |
| A diff exists and you want to know if it is built right *and* is the right thing | `code-review` |
| You want bugs hunted in the diff: null paths, races, off-by-one | Copilot CLI's built-in `/review`, rather than this standards-and-spec skill |
| Nothing is written yet and you want it written test-first | [tdd](./tdd.md) |
| A whole spec needs building, review included | [implement](./implement.md), which calls this skill itself |
| The whole codebase has drifted, not one diff | [improve-codebase-architecture](./improve-codebase-architecture.md) |
| Something is broken and you do not know why | [diagnosing-bugs](./diagnosing-bugs.md) |

You must supply the fixed point. If you do not, the skill asks for one rather than guessing. Before it spawns anything, it checks that the ref resolves and that the diff is not empty, so a mistyped branch name fails in front of you instead of inside two sub-agents.

## Prerequisites

The Standards axis needs no setup. It searches the repo for every file documenting how code should be written; when `CODING_STANDARDS.md` or `CONTRIBUTING.md` exists, it must be on the list. It falls back on a built-in baseline when the repo documents nothing.

The Spec axis needs a spec to exist and be findable. It looks in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, a GitLab `!67`), fetched through the tracker doc.
2. A path you pass in as an argument.
3. A spec file under `docs/`, `specs/`, or `.scratch/` matching the branch or feature name.
4. Asking you.

Step 1 depends on the tracker doc, which [setup-git-loopy-skills](./setup-git-loopy-skills.md) writes. Without it the axis still works if you hand it a path. With no spec at all, the skill skips the Spec sub-agent and the report says "no spec available" rather than inventing requirements.

For Microsoft technologies, call the Skill tool with "microsoft-code-reference" for
[API usage](../skills/microsoft-code-reference/SKILL.md), then call it with "microsoft-docs" for
[documented behavior](../skills/microsoft-docs/SKILL.md).

## Record the review

Keep `reviewed_head` unchanged throughout the review. Diff and list commits against that
SHA, not a later `HEAD`. Before recording, verify that both the local head and durable PR
head still equal it, and resolve the candidate through GitHub. A mismatch makes the review
stale; remediation and conflict resolution always require a new review.

Record findings on the ticket. When there are no blocking defects, the evidence comment
includes the canonical output of `python3 scripts/review-clean-record.py emit "$reviewed_head"`:
`review-clean: head=<full-sha>`. The merge gate uses the same script to match the record.
A clean head routes to [push](./push.md); findings return to [implement](./implement.md).

A caller's read-only boundary applies to both sub-agents: inspect revisions without
changing files or refs, and return the exact head, fixed point, check results and separate
reports to the caller instead of posting or invoking a successor.

## The two axes

| | Standards | Spec |
| --- | --- | --- |
| Question | Is it built right? | Is it the right thing? |
| Reads | The repo's documented standards, plus the smell baseline | The originating issue or spec |
| Reports | Documented breaches (can be hard), and smells (always judgement calls) | Missing or partial requirements, scope creep, requirements implemented wrongly |
| Every finding cites | The standards file and the rule, or the named smell plus the hunk | The line of the spec |

This design exists to avoid a generic review skill that does not know your standards. Such a skill flags what is deliberate in your codebase and misses the invariants your codebase depends on. So the repo's own documentation is the [primary source](https://www.aihero.dev/ai-coding-dictionary/primary-source) on the Standards axis, and **the repo always overrides**.

The **smell baseline** sits under the repo's standards. It is twelve code smells from chapter 3 of Fowler's _Refactoring_: Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man, Refused Bequest. Each is a labelled heuristic ("possible Feature Envy"), never a hard violation. Each states what the smell is and how to fix it, so a finding comes with a fix attached rather than only a complaint. Both axes skip anything your linter already enforces.

## Common questions

**Is this Copilot CLI's built-in review?**

No. This installed `/code-review` skill checks spec compliance and repository standards.
Copilot CLI's built-in `/review` is a separate command for reviewing code changes.
Upstream documents a same-name collision in its original harness; do not apply that
harness's plugin prefixes or removal advice to Copilot CLI.

**Its sub-agents keep invoking `/code-review` again and spawn more agents.**

This is a known open bug. Several people have reproduced it, in more than one harness. The Standards and Spec prompts do not forbid delegation, so a sub-agent can find the skill again and fan out again. One report reached more than 50 agents. The fix people have applied on forks is one line appended to both sub-agent briefs: "Do not invoke `/code-review` or spawn additional agents: perform this review directly." Some prefer to handle it at the harness level so every skill inherits the guard. Neither is in the shipped skill yet. If you run this unattended, watch the agent count.

**Should I run it in the same [session](https://www.aihero.dev/ai-coding-dictionary/session) that wrote the code?**

Prefer a fresh one. As one reader put it: "Same context reviewing itself isn't review, it's confirmation bias with a slash command." An agent that reviews in the authoring session has every assumption that shaped the code in its context. An independent reviewer would not have that context. This is also why people ask for [implement](./implement.md) without its built-in review step, because that step runs the review inside the session that just wrote the diff. The independent version is to invoke `/code-review` yourself from a clean session.

**After every ticket, or once at the end?**

Both work, and the skill does not decide for you. Per-ticket keeps each diff small enough that the Spec axis has one clear spec to check against, which is the mode `implement` uses. Batching to the end of a branch catches interactions between tickets that the per-ticket passes each miss. If you are unsure, review per ticket and run one final pass against the branch point.

**Can I trust the findings?**

Not without checking. Sub-agent output is a hypothesis, not evidence. One team reported a dozen breaking changes that prose-based reviews had missed. The skill combines the two reports as they are, or lightly cleaned. It does not re-verify each claim against the files, so a finding can cite the wrong location or overstate an impact. Read the citation on each finding before you act on it. The skill requires every finding to carry a citation (a standards rule, a smell plus its hunk, or a spec line), and that is what makes the findings checkable.

**Why does it find new problems every single time I run it?**

Each fix adds new code to review, and the judgement-call half of the Standards axis gives different results from run to run. One reader described the loop: "/code-review and /improve-code-architecture always find new stuff every time. I implement fixes, rerun these skills, and again and again." There is no convergence guarantee. Treat a pass as a list of leads. Act on the ones with a cited rule behind them, then stop. Do not run it in a loop until it comes back clean, because it never will.

**Does it review my uncommitted work?**

No. It diffs `<fixed-point>..."$reviewed_head"`. The three-dot form measures from the merge-base and excludes staged and working-tree changes. This fork's `implement` commits and pushes before review. If you edit afterward, commit and push a new candidate, then review it afresh; the previous `review-clean` record cannot cover those edits.

## It's working if

- It refuses to start on a bad ref or an empty diff, before any sub-agent is spawned.
- It searches all standards sources and issues both review calls together in the foreground.
- Its durable evidence names the pinned candidate SHA, and a clean result carries the canonical `review-clean` line.
- The report arrives as two separate blocks under `## Standards` and `## Spec`, not one merged list.
- Every Standards finding names either a rule in one of your repo's files or one of the twelve smells, with the hunk quoted; every Spec finding quotes a line of the spec.
- The closing summary gives a worst issue per axis and declines to pick an overall winner.
- With no spec available, the Spec block says so instead of listing requirements it inferred from the code.

## Where it fits

`code-review` is the review step near the tail of the build chain: `grill-with-docs → to-spec → git-loopy plan → implement → code-review → push`. Outside git-loopy, [to-tickets](./to-tickets.md) supplies the decomposition fallback. Review also stands alone on any branch or PR you point it at.

- [implement](./implement.md) is the closest neighbour. It drives the build, commits and pushes, then calls this skill to review that exact candidate.
- [push](./push.md) publishes a clean reviewed head and opens its pull request. Upstream's `pr`, `retro` and `implement-spec` neighbours are not yet published in this catalog.
- [to-spec](./to-spec.md) and [to-tickets](./to-tickets.md) produce the document the Spec axis checks against, so a vague spec makes that axis vague.
- [improve-codebase-architecture](./improve-codebase-architecture.md) is the whole-codebase counterpart, because this skill only looks at one diff.

[next](./next.md) routes across the whole set when you are unsure which skill the situation wants.
