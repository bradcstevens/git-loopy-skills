Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=sync-branch
```

```text
/sync-branch
```

[Skill source](../skills/sync-branch/SKILL.md)

## What it does

`sync-branch` brings the current branch and its upstream to the same commit. It
reads the worktree and branch state, fetches, reconciles any divergence, pushes
local commits with a plain fast-forward push, and verifies that the worktree is
clean and `HEAD` matches the upstream.

Every local change and commit survives. The skill records the starting `HEAD` as
a recovery point before it moves anything, and reports it at the end.

## When to reach for it

Type `/sync-branch` when a branch has fallen behind, has unpushed commits, or has
diverged from its upstream. It is user-invoked only; no other skill reaches it.

## Where it stops to ask

- Uncommitted changes, staged, unstaged, or untracked: commit them first with
  [push](./push.md), stash them for the sync, or stop.
- A detached `HEAD` or a branch with no upstream.
- An in-progress merge, rebase, cherry-pick, or revert, or a conflict during the
  sync: resolve with [implement](./implement.md)
  or abort back to the recovery point.
- A push to the default or a protected branch, a repeated push rejection, or a
  missing permission.

## Common questions

**Rebase or merge?** A diverged branch follows the repository's `pull.rebase`
setting: rebase when it is `true` or unset, merge when it is `false`.

**Will it force-push?** No. The remote's history is only ever extended.

**How do I undo it?** `git reset --keep <recovery-point>` returns the branch to
where it started.

## It's working if

- `git status --porcelain` is empty, apart from any stash you chose to restore.
- `git rev-parse HEAD` equals `git rev-parse @{u}`.
- Every local commit from before the sync is still on the branch.

## Where it fits

[push](./push.md) publishes new work; `sync-branch` reconciles a branch that
already exists on both sides.
