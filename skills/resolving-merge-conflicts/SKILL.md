---
name: resolving-merge-conflicts
description: "Use when you need to resolve an in-progress git merge/rebase conflict."
---

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Always resolve; never `--abort`.

4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage everything and commit. If rebasing, continue the rebase process until all commits are rebased.

6. **Record the resolution.** Resolving a conflict is a durable workflow transition, and this
   skill owns it. Push the resolved head, then post one short comment on the ticket naming
   both sides of the reconciliation and the trade-offs made (`gh issue comment <ticket-issue>
   --body "..."`). Only do this once the resolved head is durable: the merge or rebase is
   finished, the project's checks pass, and the head is committed and pushed
   (`git rev-parse HEAD` resolves it, `git push` makes it readable).

A resolved head is a head **nobody has reviewed**: the resolution chose between two intents,
and that choice is exactly what review exists to check. So run `/code-review` on the resolved
head next — never reuse the review the pre-conflict head already passed.

If the resolution needs authority you do not hold — a protected branch, a force push, a
credential — stop and say so. Never answer an authority prompt unattended, and never
`--abort` around one.

At the conclusion of a `/resolving-merge-conflicts` session, run `/code-review` on the
resolved head you just pushed.
