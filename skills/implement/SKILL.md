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

## Check the target's holders

From the target's checkout, right after fetching the ticket and before any write,
run the read-only command shipped in the installed `/next` skill:

```bash
python3 <installed next skill>/scripts/target-holders.py --target <ticket-or-PR>
```

It uses `plan`'s canonical target and reports closing pull requests, open bound
runs, and live owners of their head-branch worktrees. If `held: true`, stop
without writing and name every holder whose `own` is false: review or merge the
open pull request, wait for the bound session and agent, or coordinate with the
worktree's owning process. If the lookup fails, stop and report the blocker;
unreadable state is not a free target.

The command marks holders in this checkout or on its current branch `own: true`;
they remain in the report but do not block this caller. For an already assigned
branch remediation from a different checkout, pass `--caller-branch <that-branch>`.
Use only the branch this caller is remediating, not another holder's branch to
bypass the guard. Continue only when the command succeeds with `held: false`.

For a diverged branch or an in-progress merge, rebase, or cherry-pick, follow
[Conflict resolution](references/conflict-resolution.md) first. Finish the operation
and record the checked, committed, pushed resolution before the closing review.
The resolved head is a new candidate: review that head, not the pre-conflict one.

Call the Skill tool with "tdd" where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done and green, commit your work to the current branch and push it, then record the
implementation below. What follows routes that exact candidate to `/code-review`.
Review the head you committed, never an uncommitted worktree.

## Record the implementation

Producing a candidate is a durable workflow transition, and this skill owns it. Record it so
the next session, human or agent, reads the same answer you did. `/tdd`,
`/codebase-design`, `/domain-modeling` and any documentation lookup run *inside* this
transition: they hand their evidence back here and record nothing of their own.

**Only record once the candidate head is durable.** A head that exists in one worktree is
not something a later reviewer can read, so, in order:

1. Finish the implementation and run the project's automated validation: typecheck, the
   tests covering the change, and the full suite once. A red loop is not a candidate.
2. Commit the work, then push the branch so the exact head is durable
   (`git rev-parse HEAD` is the candidate head; `git push` makes it readable).
3. Post one short evidence comment on the ticket describing what this transition changed
   and which head it produced (`gh issue comment <ticket-issue> --body "..."`), naming the
   candidate head SHA explicitly.

The successor is a **review of that exact head**, never "review the branch": a remediated or
conflict-resolved head is always a new review, and cannot inherit an earlier review's result.

Never widen your own authority to finish a candidate. If the work needs a login, MFA, a
secret, a consent prompt, or any privilege you do not already hold, stop and say so.
Unattended execution never answers an authority prompt.

When the ticket carries an acceptance criterion a human has to judge, say so in the comment
and leave the ticket open: subjective acceptance is a human decision, never a promise folded
into unattended implementation.

At the conclusion of an `/implement` session, call the Skill tool with "code-review" on the head you just pushed.
