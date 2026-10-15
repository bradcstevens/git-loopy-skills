---
name: sync-branch
description: Synchronize the current branch with its upstream, keeping every local change and commit.
model: claude-sonnet-5.5
effort: low
context: 200K
disable-model-invocation: true
---

# Synchronize the Current Branch

Bring the current branch and its upstream to the same commit. Every local
change and commit survives the sync: work is moved, never dropped. Each
**checkpoint** below pauses for the user through `ask_user`; continue only on
their answer.

## 1. Read the starting state

Inspect:

- `git status --porcelain=v2 --branch`, including untracked files
- the current branch and its upstream (`git rev-parse --abbrev-ref @{u}`)
- any in-progress merge, rebase, cherry-pick, or revert
- `git stash list`

Record the starting `HEAD` SHA as the **recovery point** and show it to the user.

Checkpoints:

- A detached `HEAD`, or a branch with no upstream: ask which branch and
  upstream to sync.
- An in-progress operation or unmerged paths: report them and recommend
  `/implement`; sync only once it is finished.
- Uncommitted changes (staged, unstaged, or untracked): list them and ask
  whether to commit them first (`/push`), stash them for the duration of the
  sync (`git stash push --include-untracked`), or stop.

This step is complete when the branch, upstream, recovery point, and a clean or
user-approved worktree are known.

## 2. Fetch and measure the divergence

Run `git fetch <remote>` for the upstream's remote, then
`git rev-list --left-right --count HEAD...@{u}` to count local-only and
upstream-only commits. List both sets with `git log --oneline`.

This step is complete when the branch is classified as **in sync**, **behind**,
**ahead**, or **diverged**, with each commit on either side named.

## 3. Reconcile

- **In sync** or **ahead**: go to step 4.
- **Behind**: `git merge --ff-only @{u}`.
- **Diverged**: replay the local commits onto the upstream, following the
  repository's `pull.rebase` setting: `git rebase @{u}` when it is `true` or
  unset, `git merge @{u}` when it is `false`. Local commits that include merges
  use `git rebase --rebase-merges @{u}`.

Checkpoint: any conflict. Stop with the operation in progress, list the
conflicting paths, and ask whether to resolve them (`/implement`)
or abort back to the recovery point (`git rebase --abort` or `git merge --abort`).

This step is complete when `git merge-base --is-ancestor @{u} HEAD` succeeds and
`git range-diff @{u} <recovery-point> HEAD` shows every local commit from step 2
carried over.

## 4. Push the local commits

When `HEAD` is ahead of the upstream, publish with a plain fast-forward
`git push`. Rejections are answered by fetching and reconciling again; history
on the remote is only ever extended.

Checkpoints:

- The upstream is the remote default branch or a protected branch: confirm the
  push with the user first.
- The remote rejects the push: return to step 2 once; a second rejection goes to
  the user.
- An authentication, permission, or branch-protection refusal: report the
  missing authority and stop.

This step is complete when the remote branch resolves to the local `HEAD`, or
the user declined the push.

## 5. Verify

Restore any stash from step 1 with `git stash pop` (a stash conflict is a
checkpoint), fetch once more, then confirm:

- `git status --porcelain` lists only the restored stash changes, or nothing
- `git rev-parse HEAD` equals `git rev-parse @{u}`

This step is complete when both hold, or when the one that fails is reported
with its reason (for example, the user declined the push).

## 6. Report

Report the branch and upstream, the recovery point, the commits pulled in and
pushed out, the reconcile method, and the final shared SHA. When the sync
rewrote local commits, name the way back: `git reset --keep <recovery-point>`.
