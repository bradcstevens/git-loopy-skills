---
status: proposed
---

# The chain may merge, on this workflow's own evidence

`/merge` integrates a reviewed head into the default branch, and this decision allowlists it: the
chain may spawn it and carry a ticket to `main` with no human in the loop. It merges unattended only
on **merge evidence** — GitHub's mergeable state, a matchable `review-clean` record from
`/code-review`, and every check green.

`review-clean` is a requirement this decision imposes, not a record it inherits. `/code-review`
posts a free-text evidence comment today, and `chain.sh complete` matches any comment inside the
spawn-to-finish window rather than a marker, so nothing in the repository currently produces
something the gate could read. Whoever builds the gate fixes the record's shape and makes
`/code-review` emit it in the same change (#62). A gate whose only input has no producer fails
closed forever.

Two skills state the opposite of this decision as a rule. `/push` says "the successor is a human's:
merging is a judgement about whether this change should be in the default branch, and nothing here
makes that unattended." `/code-review` says "a review never merges anything." Both are wrong under
this decision, and #58 changes them alongside the allowlist so the router, the skills, and the
script never disagree about who merges.

## Why the boundary moved

The rule described a judgement, but the judgement had already been made and recorded by the time
`/push` deferred it. `/code-review` reads the diff against the repository's standards and against
what the originating issue asked for, then publishes the outcome. That verdict is a durable answer
to whether the change should exist. Asking a human to read the same diff and press a button is not a
second judgement; it is a receipt for the first one.

What made the deferral look necessary was the absence of a gate, not the presence of a question. The
gate needs the verdict in a form a script can read, which is the whole reason `review-clean` becomes
a marker instead of staying prose.

## Why the gate is not GitHub's alone

The obvious gate — merge whatever GitHub says is mergeable — is a **null gate in this repository**.
`main` carries no branch protection, there are no rulesets, and every merged pull request reports an
empty `reviewDecision`. GitHub would say yes to anything, precisely where the risk is highest.

So the gate is this workflow's own evidence, with GitHub's answer as one input among three. A
repository that configures real protection gets both; a repository that configures none still gets a
gate. The `review-clean` record is load-bearing here: it turns `/code-review`'s existing `publishes
to` edge into a precondition something reads, rather than a record nothing consumes.

## Considered Options

Each of these will look reasonable again to someone who has forgotten why it lost.

- **Merge whatever GitHub reports as mergeable.** Rejected because it is a null gate here, for the
  reasons above. It stays available as one of the three inputs rather than as the whole test.
- **Require an approving review as a hard floor.** Nobody approves pull requests in this repository,
  so requiring one would leave the allowlist open and unusable — the decision would be inert on the
  day it was made. An approval is a welcome input where the practice exists, never the gate itself.
- **Merge locally with `git merge` and push the result.** Rejected because the evidence gate is
  pull-request-shaped: a branch-to-branch merge routes around it entirely, and restricting that path
  to attended use would rest on an unattended agent correctly deciding it was not allowed to take
  it. The cost is real — `/merge` is useless offline and against a non-GitHub remote.

## Consequences

- **`/merge` is a GitHub skill, not a git skill.** It is PR-mediated always. A branch with no pull
  request is refused with a route to `/push`, which exists to create one.
- **A worktree path is an address, not a third kind of object.** `/merge` accepts a pull request
  number, a branch, or a worktree path, and a path resolves to the branch that worktree has checked
  out. A dirty worktree is refused rather than committed: `/push` owns the commit boundary, and a
  second skill on it would be the coupling this design exists to avoid.
- **Squash stays the default, and that costs the sweeper its cheapest check.** This repository has no
  merge commits at all across its whole history. Preserving that linear history means a merged branch
  is not an ancestor of `main`, so `git branch --merged` reports nothing and no local check can prove
  a branch was merged. Anything that wants to know must ask GitHub — which is why
  [ADR-0007](./0007-a-worktree-is-removed-only-when-something-vouches-for-it.md) cannot decide a
  branch's fate from ancestry.
- **`/merge` stops at the remote.** It deletes the remote head branch, because `gh` does that in the
  same call that merges and no liveness question exists on the remote. It touches no local directory
  and no local branch. Removing a worktree would require the marker rules, the observation ledger,
  and the liveness reasoning of ADR-0007 — a second copy of the sweeper living inside `/merge`.
- **The chain's guards do not bound this.** They count route repetitions per target, not blast
  radius, so a merge loop halts only after three attempts. Here the second and third are caught by
  the remote refusing to merge an already-merged pull request, which is an accident of what `/merge`
  does rather than a property of the guard; a route whose repeats each landed would get all three.
  The evidence gate is the only bound that scales with consequence, which is why it is stated in
  terms of records that must exist rather than conditions that must not.
