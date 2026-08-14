# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Parallel execution label

`parallel-safe` is **not** one of the five canonical triage roles — it is an additional, opt-in eligibility label a human applies **alongside** `ready-for-agent`. It asserts the issue is independent and well-scoped enough to be worked concurrently, in its own worktree. The runner never infers it: an issue that lacks it runs serially even in parallel mode. Because it is not a triage role it is not in the table above and is not renameable — the runner reads that exact string.

## Priority label

Eligible issues are worked **oldest first**, by creation date. A newly filed issue joins the back of the queue; it does not jump ahead just by being new.

`priority` is the human assertion that changes that order. Like `parallel-safe` it is not one of the five canonical triage roles, is not in the table above, and is **not renameable** — the runner reads that exact string at selection. It is never inferred.

What it does is **reorder**, and only reorder. An issue carrying `priority` is selected ahead of older ones, and two `priority` issues order oldest-first against each other. What it does **not** do is change eligibility: a `priority` issue still needs `ready-for-agent` to enter the pool, still has to pass the AFK-ready body discriminator (`## What to build` plus `## Acceptance criteria`), and still needs `parallel-safe` to be worked concurrently.

## Creating the labels

`git-loopy init`, run inside the repository, creates whichever triage, `parallel-safe`, and `priority` labels are absent and leaves the ones that already exist untouched. Re-running it creates nothing.

Without `git-loopy`, create the two assertions by hand — `--force` makes this a create-or-update, so it is safe to re-run:

```bash
gh label create priority --force --color b60205 \
  --description "Human assertion: worked ahead of older issues. git-loopy never infers it. Eligibility unchanged."
gh label create parallel-safe --force --color 5319e7 \
  --description "Human assertion alongside ready-for-agent: safe in its own Lane. git-loopy never infers it."
```
