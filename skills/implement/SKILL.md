---
name: implement
description: "Implement a spec or tickets, or reconcile a branch with a moved remote head and resolve merge, rebase, or cherry-pick conflicts."
model: gpt-6-astra
effort: medium
context: 1050K
disable-model-invocation: false
---

Implement the work described by the user in the spec or tickets.

If the user passes a ticket reference, fetch it from the issue tracker and state its title before starting. If the reference is ambiguous, ask.

For a diverged branch or an in-progress merge, rebase, or cherry-pick, follow
[Conflict resolution](references/conflict-resolution.md) first. Finish the operation
and record the checked, committed, pushed resolution before the closing review.
The resolved head is a new candidate: review that head, not the pre-conflict one.

Call the Skill tool with "tdd" where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, call the Skill tool with "code-review" to review the work.

Commit your work to the current branch.

At the conclusion of a `/implement` session, run the `/next` skill.
