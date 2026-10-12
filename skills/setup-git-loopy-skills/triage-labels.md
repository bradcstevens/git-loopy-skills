# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in git-loopy/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.

## Parallel execution label

`parallel-safe` is **not** one of the five canonical triage roles. It is an additional, opt-in eligibility label a human applies **alongside** `ready-for-agent`. It asserts the issue is independent and well-scoped enough to be worked concurrently, in its own worktree. The runner never infers it: an issue that lacks it runs serially even in parallel mode. Because it is not a triage role it is not in the table above and is not renameable; the runner reads that exact string.

## Priority label

Eligible issues are worked **oldest first**, by creation date. A newly filed issue joins the back of the queue; it does not jump ahead just by being new.

`priority` is the human assertion that changes that order. Like `parallel-safe` it is not one of the five canonical triage roles, is not in the table above, and is **not renameable**; the runner reads that exact string at selection. It is never inferred.

What it does is **reorder**, and only reorder. An issue carrying `priority` is selected ahead of older ones, and two `priority` issues order oldest-first against each other. What it does **not** do is change eligibility: a `priority` issue still needs `ready-for-agent` to enter the pool, still has to pass the AFK-ready body discriminator (`## What to build` plus `## Acceptance criteria`), and still needs `parallel-safe` to be worked concurrently.

## Idea label

`idea` is the human assertion that an issue is an anchor created from a concluded grilling session. Like `parallel-safe` and `priority` it is not one of the five canonical triage roles, is not in the table above, and is **not renameable**; the tracker readers use that exact string. No skill ever applies it or infers that an issue is an idea.

What it does is **keep the anchor out of the triage and `ready-for-agent` queues**, and only those queues. It marks concluded thinking rather than work waiting to be picked up; it does not itself create a spec or otherwise advance the workflow.

## Task-type labels

`task-type:` labels are **not** triage roles either. Each one asserts the dominant risk of a ticket, the dimension whose failure is most expensive, not the one touching the most files. `git-loopy` reads it to pick the model and reasoning effort that carry the run. The taxonomy is **closed at seven**, matching the keys in `git-loopy config routing list`:

| Label | For work whose dominant risk is |
| --- | --- |
| `task-type:planning` | Deciding what to build |
| `task-type:review` | Judging work that already exists |
| `task-type:implementation` | Building behaviour |
| `task-type:test` | Verifying behaviour |
| `task-type:docs` | Explaining something accurately |
| `task-type:chore` | A mechanical change |
| `task-type:bugfix` | Diagnosing and correcting a defect |

Three hazards, all of which fail silently:

- **Exactly one per issue.** The router selects the first match from an unordered list, so a second label makes routing arbitrary.
- **Never invent an eighth.** An out-of-taxonomy `task-type:` label still looks labelled, so the classifier will not correct it and routing falls through.
- **A missing label falls back to the classifier**, which is a guess. Prefer to set it explicitly.

## Creating the labels

When setup's triage section runs on GitHub or GitLab, create **all configured labels that are missing**, not only the fixed assertions. Use the five actual strings from the mapping above, including user overrides, plus `parallel-safe`, `priority`, `idea`, and the seven task-type labels.

Build the approved list before running commands. This example uses the default role strings; replace only those five strings with the user's choices:

```bash
configured_labels=(
  needs-triage needs-info ready-for-agent ready-for-human wontfix
  parallel-safe priority idea
  task-type:planning task-type:review task-type:implementation task-type:test
  task-type:docs task-type:chore task-type:bugfix
)
```

For **GitHub**, list all existing names through the paginated REST endpoint, then create only missing ones:

```bash
set -euo pipefail
existing_labels="$(mktemp)"
gh api --paginate 'repos/{owner}/{repo}/labels?per_page=100' \
  --jq '.[].name' > "$existing_labels"
for label in "${configured_labels[@]}"; do
  if ! grep -qxF -- "$label" "$existing_labels"; then
    gh label create "$label" --color cfd3d7
  fi
done
rm -- "$existing_labels"
```

For **GitLab**, use the corresponding project endpoint and label command:

```bash
set -euo pipefail
existing_labels="$(mktemp)"
glab api --paginate 'projects/:id/labels?per_page=100' |
  jq -r '.[].name' > "$existing_labels"
for label in "${configured_labels[@]}"; do
  if ! grep -qxF -- "$label" "$existing_labels"; then
    glab label create --name "$label" --color '#cfd3d7'
  fi
done
rm -- "$existing_labels"
```

Do not use create-or-update flags: setup must leave existing colors and descriptions untouched. If listing or creation fails, stop and report the error; do not treat a failed list as an empty tracker. A concurrent creator can make a create fail, so re-list to verify rather than suppressing the error. Creating a label does not apply it to an issue.

`git-loopy init` also creates missing triage, `parallel-safe`, and `priority` labels, but it does not replace this check of the full configured vocabulary. For local markdown, only record the vocabulary. For other trackers, follow the confirmed workflow.
