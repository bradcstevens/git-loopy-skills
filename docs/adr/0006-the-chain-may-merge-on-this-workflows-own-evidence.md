# The chain may merge, on this workflow's own evidence

`/merge` integrates a reviewed head into the default branch, and it is allowlisted: the chain may
spawn it and carry a ticket to `main` with no human in the loop. It merges unattended only on
**merge evidence** — GitHub's mergeable state, the `review-clean` comment `/code-review` published,
and every check green.

Two skills previously stated the opposite as a rule. `/push` said "the successor is a human's:
merging is a judgement about whether this change should be in the default branch, and nothing here
makes that unattended." `/code-review` said "a review never merges anything." Both are now wrong,
and both change.

## Why the boundary moved

The rule described a judgement, but the judgement had already been made and recorded by the time
`/push` deferred it. `/code-review` publishes `review-clean` after checking the diff against the
repository's standards and against what the originating issue asked for. That comment is a durable
verdict on whether the change should exist. Asking a human to then read the same diff and press a
button is not a second judgement; it is a receipt for the first one.

What made the deferral look necessary was the absence of a gate, not the presence of a question.

## Why the gate is not GitHub's alone

The obvious gate — merge whatever GitHub says is mergeable — is a **null gate in this repository**.
`main` carries no branch protection, there are no rulesets, and every merged pull request reports an
empty `reviewDecision`. GitHub would say yes to anything, precisely where the risk is highest.

So the gate is this workflow's own evidence, with GitHub's answer as one input among three. A
repository that configures real protection gets both; a repository that configures none still gets a
gate. The `review-clean` comment is load-bearing here: it turns `/code-review`'s existing
`publishes to` edge into a precondition something actually reads, rather than a record nothing
consumes.

A hard approval floor was considered and rejected. Nobody approves pull requests in this repository,
so requiring one would leave the allowlist open and unusable — the decision would be inert on the
day it was made.

## Consequences

- **`/merge` is a GitHub skill, not a git skill.** It is PR-mediated always. A branch with no pull
  request is refused with a route to `/push`, which exists to create one. It is therefore useless
  offline and useless against a non-GitHub remote. A local `git merge` path was rejected because the
  evidence gate is pull-request-shaped: a branch-to-branch merge would route around it entirely, and
  restricting that path to attended use would rest on an unattended agent correctly deciding it was
  not allowed to take it.
- **A worktree path is an address, not a third kind of object.** `/merge` accepts a pull request
  number, a branch, or a worktree path, and a path resolves to the branch that worktree has checked
  out. A dirty worktree is refused rather than committed: `/push` owns the commit boundary, and a
  second skill on it would be the coupling this design exists to avoid.
- **Squash stays the default, and that costs the sweeper its cheapest check.** This repository has
  no merge commits at all across its whole history. Preserving that linear history means a merged
  branch is not an ancestor of `main`, so `git branch --merged` reports nothing and no local check
  can prove a branch was merged. Anything that wants to know must ask GitHub.
- **`/merge` stops at the remote.** It deletes the remote head branch, because `gh` does that in the
  same call that merges and no liveness question exists on the remote. It touches no local
  directory and no local branch. Removing a worktree would require the marker rules, the observation
  ledger, and the liveness reasoning of
  [ADR-0007](./0007-a-worktree-is-removed-only-when-something-vouches-for-it.md) — a second copy of
  the sweeper living inside `/merge`. Git enforces the seam anyway: a local branch checked out in a
  worktree cannot be deleted while that worktree exists.
- **The chain's guards do not bound this.** They count route repetitions per target, not blast
  radius, so they would halt a merge loop after three attempts having already put three merges into
  `main`. The evidence gate is the only real bound, which is why it is stated in terms of records
  that must exist rather than conditions that must not.
