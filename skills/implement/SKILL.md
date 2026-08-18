---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done and green, commit your work to the current branch and push it, then record the
implementation below. What follows routes that exact candidate to `/code-review` — review
the head you committed, never an uncommitted worktree.

## Record the implementation

Producing a candidate is a durable workflow transition, and this skill owns it. Record it so
the next session — human or agent — reads the same answer you did. `/tdd`,
`/codebase-design`, `/domain-modeling` and any documentation lookup run *inside* this
transition: they hand their evidence back here and record nothing of their own.

**Only record once the candidate head is durable.** A head that exists in one worktree is
not something a later reviewer can read, so, in order:

1. Finish the implementation and run the project's automated validation — typecheck, the
   tests covering the change, and the full suite once. A red loop is not a candidate.
2. Commit the work, then push the branch so the exact head is durable
   (`git rev-parse HEAD` is the candidate head; `git push` makes it readable).
3. Post one short evidence comment on the ticket — what this transition changed
   and which head it produced (`gh issue comment <ticket-issue> --body "..."`), naming the
   candidate head SHA explicitly.

The successor is a **review of that exact head**, never "review the branch": a remediated or
conflict-resolved head is always a new review, and cannot inherit an earlier review's result.

Never widen your own authority to finish a candidate. If the work needs a login, MFA, a
secret, a consent prompt, or any privilege you do not already hold, stop and say so —
unattended execution never answers an authority prompt.

When the ticket carries an acceptance criterion a human has to judge, say so in the comment
and leave the ticket open: subjective acceptance is a human decision, never a promise folded
into unattended implementation.

At the conclusion of an `/implement` session, run `/code-review` on the head you just pushed.
