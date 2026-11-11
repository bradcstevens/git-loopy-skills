---
name: sync-branches
description: "Two-way sync every local branch with its GitHub upstream: fast-forward, push, rebase clean divergence, and prune merged branches."
model: gpt-6.1-terra
effort: low
context: 272K
disable-model-invocation: true
---

# Sync Every Branch With GitHub

Invocation authorizes one **sync** of every local branch that has an upstream:
bring remote commits down, push local commits up, rebase clean divergence, and
prune merged branches whose upstream is gone. A sync moves committed history
only. Working-tree edits stay exactly where they are; committing and publishing
new work is `/push`.

## 1. Take the inventory

From the repository root:

```bash
git fetch --all --prune
git worktree list --porcelain
git for-each-ref --format='%(refname:short)|%(upstream)|%(upstream:track)|%(worktreepath)' refs/heads
```

`--prune` marks an upstream deleted on GitHub as `[gone]`. Resolve each remote's
default branch with `git symbolic-ref refs/remotes/<remote>/HEAD`. Mark every
worktree clean, dirty (`git -C <path> status --porcelain` prints anything), or
mid-operation (`git -C <path> status` reports a rebase, merge, cherry-pick,
revert, or bisect in progress).

Give each branch exactly one state:

| State | `%(upstream:track)` | Action in step 2 |
| --- | --- | --- |
| local-only | no upstream | none; publish it with `/push` |
| in sync | empty | none |
| behind | `[behind N]` | fast-forward |
| ahead | `[ahead N]` | push |
| diverged | `[ahead N, behind M]` | rebase, then push |
| gone | `[gone]` | prune when merged |

**Done:** every local branch has one state, and every worktree is marked clean,
dirty, or mid-operation.

## 2. Sync each branch

A branch checked out in a dirty or mid-operation worktree is **held**: skip every
action that rewrites its working tree (fast-forward, rebase, prune) and carry it
to the report. Pushing leaves working trees untouched, so a held branch that is
ahead still pushes.

- **behind**: in its clean worktree, `git -C <path> merge --ff-only @{u}`. When it
  is checked out nowhere, `git fetch . <upstream-ref>:refs/heads/<branch>`, which
  accepts only a fast-forward.
- **ahead**: `git push <remote> refs/heads/<branch>:refs/heads/<upstream-name>`,
  naming the upstream explicitly because it may differ from the local name.
  Pushing a remote's default branch integrates unreviewed commits: list them and
  get the user's yes before that push.
- **diverged**: rebase the local commits onto the upstream, then push as
  **ahead**. Rebase in the branch's clean worktree or, when it is checked out
  nowhere, in a throwaway `git worktree add <tmp> <branch>` removed afterward, so
  the invoking checkout never moves. Rebase only clean divergence: when the local
  commits (`git log <upstream>..<branch>`) include a merge commit, or the rebase
  stops on a conflict, run `git rebase --abort` and hand the branch to
  `/implement` in the report, naming both heads. Mark every rebased head
  unvalidated: no one has tested that combination yet.
- **gone**: prune with `git branch -D <branch>` only when it is **merged**: its tip
  is an ancestor of the default branch
  (`git merge-base --is-ancestor <branch> <remote>/<default>`), or a merged pull
  request's head is exactly the tip
  (`gh pr list --head <branch> --state merged --json headRefOid`). The pull-request
  test catches squash and rebase merges, whose commits never become ancestors;
  match the SHA, because branch names get reused. Keep an unmerged gone branch and
  report its unmerged commits.

Every push is a plain fast-forward push. A rejection means the upstream moved:
fetch and resync that branch once, then report it. A force push needs the user's
explicit approval for that branch. Branch protection, a 403, or a login prompt is
an authority boundary: report it and continue with the other branches. When git
authenticates through `gh`, a parallel session may have switched gh's active
account; `gh api user --jq .login` shows who is pushing.

**Done:** every branch has its action applied, or a recorded reason it was held,
rejected, or handed off.

## 3. Verify and report

Run `git fetch --all --prune` and the `for-each-ref` inventory again. Every branch
fast-forwarded, pushed, or rebased in step 2 now shows an empty track.

For each pushed branch other than a default branch, check
`gh pr list --head <branch> --state open`. List the ones without a pull request;
opening one is `/push`.

Report one table (branch, state before, action, resulting SHA or reason), then:

- held branches and their dirty or mid-operation worktree paths
- local-only branches
- pushed branches with no open pull request
- rebased heads, marked unvalidated
- branches handed to `/implement`, with both heads
- pruned branches, with the SHA each pointed at so it can be restored

**Done:** the re-run inventory matches the report: every branch is in sync or
appears in the report with its reason.
