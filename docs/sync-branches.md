# Sync every branch with GitHub

Install into your agent:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=sync-branches -g -a github-copilot
```

Then, in any repository:

```text
/sync-branches
```

[Skill source](../skills/sync-branches/SKILL.md)

## What it does

One invocation reconciles every local branch that has an upstream with that
upstream, in both directions:

| Branch state | Result |
| --- | --- |
| behind | fast-forwarded to the upstream |
| ahead | pushed with a plain fast-forward push |
| diverged | local commits rebased onto the upstream, then pushed |
| upstream gone | deleted when its work is merged; kept and reported otherwise |
| no upstream | reported; publish it with [push](./push.md) |

It covers every worktree. A branch whose worktree has uncommitted changes or an
operation in progress is _held_: the sync still pushes its existing commits, but it
never fast-forwards, rebases or deletes it, and it leaves the worktree's edits
alone.

## When to reach for it

Type `/sync-branches` when the local branches have drifted from GitHub, for example
after a few days away, after merging pull requests on github.com, or before you
switch machines. It is user-invoked only, so no other skill fires it.

Use [push](./push.md) instead to commit new work and open a pull request. A sync
moves only history that is already committed.

## Safety rails

- **Merged means merged.** A branch whose upstream is gone is deleted only when
  its tip is an ancestor of the default branch, or when it is exactly the head of a
  merged pull request. That second check catches squash and rebase merges. The
  report lists every deleted branch's SHA so you can restore it.
- **Rebase only when it's clean.** The sync aborts a rebase that conflicts or
  would flatten a merge commit, then hands the branch to
  [implement](./implement.md), naming both heads. Rebased heads are reported as
  unvalidated.
- **No forced pushes.** A force push needs your explicit approval for that branch.
  Pushing straight to a default branch asks first, because that integrates
  unreviewed commits.
- **No pull requests.** The sync reports pushed branches that have no open pull
  request, but it never opens one.
- **Authority boundaries stop the branch, not the sync.** Branch protection, a
  403, or a login prompt is reported, and the sync moves on to the remaining
  branches.

## It's working if

- After a fresh fetch, every branch shows no ahead/behind count, or it appears in
  the report with its reason.
- Every dirty worktree keeps its uncommitted edits exactly as they were.
