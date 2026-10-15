---
name: implement-spec
description: "Implement the result of /to-spec and /to-tickets in code."
model: gpt-6-astra
effort: medium
context: 272K
disable-model-invocation: true
---

You have been provided a spec. This spec should have tickets associated with it, describing how to implement the spec.

The issue tracker should have been provided to you. If not, tell the user to run `/setup-git-loopy-skills`.

The goal is the entire spec implemented on a single **integration branch**, with every ticket resolved the way the issue tracker closes work.

The tickets are not a list of steps. They are a **task graph** with blocking relationships between them. This means there is always a **frontier** of tickets which are ready to be grabbed.

Communication to and from subagents should be sparse. Communicate primarily through **context pointers**: to the spec, tickets, research notes, and previous commits. Don't duplicate information already available via pointers.

**Implementer subagents** should be run in the background where possible for maximum concurrency.

## Copilot execution

Implementer, merger and exploration subagents use the Copilot CLI `task` tool
with `mode: "background"`. Choose an agent type that can write files (including
exploration notes), not a read-only explorer. Pass each agent its role, context
pointers, exact worktree path and branch, and a bounded completion condition.
Respect the harness's concurrency limit and keep at most ten subagents in flight,
including exploration and merger agents; queue the remaining ready tickets.
Wait for completion notifications and read the returned agent ID's result before
using its work. Do not mistake a successful launch for completed work.

Keep a run-owned inventory of every worktree and branch created, the starting
checkout and base commit, ticket assignments, and integration merge SHAs.
Create worktrees from the integration tip before launching writers. Where the
chain is installed, use its `chain.sh claim --worktree <path> --create-branch
<branch> --owner-pid <owning-session-pid>` so each worktree has a worktree marker.
Run ticket and review-fix claims from the integration worktree, since `claim`
bases a new branch on the calling checkout's `HEAD`.
Never borrow another session's worktree or reset its branch.

Only dispatch unassigned tickets on the ready frontier. Compute readiness from
the starting task graph and tickets successfully merged into the integration branch,
not the tracker's open blocked-by count while a draft PR is still open. External
blockers still need resolution. A failed ticket does not unblock its dependents;
report a cycle or unresolved blocker instead of spinning when no work can start.

## Steps

1. Read the spec and tickets to understand the task graph.

2. (optional) Use an **exploration subagent** to conduct any exploration required by the tickets - relevant codebase files or external documentation. Ensure the exploration subagent can save files - it should save its markdown notes in a directory outside the repo, accessible by all future subagents. This lets **implementer subagents** focus on implementation rather than exploration.

3. Create the integration branch in its own run-owned worktree. If the issue tracker closes work through PRs, or the user asks for one, open a draft PR after the first merge in step 5 (a branch with no commits ahead of main can't open one), marked as closing the spec and tickets.

4. Use **implementer subagents** to implement each ticket, each in its own worktree on its own branch. Each implementer subagent:
   - confirms its worktree is based on the integration branch before starting. Do not reset a branch containing work; reconcile it without discarding changes or report the blocker;
   - calls the Skill tool with `tdd` to build the ticket at the seams agreed in the spec or ticket;
   - merges the integration branch tip into its own branch before reporting done

5. Once an **implementer subagent** completes, merge its work to the integration branch with a **merger subagent**. Run at most one merger at a time in the integration worktree. Use `git merge --no-ff` to give each ticket an attributable merge commit, then run the declared feedback loops on the merged tree. Record the merge SHA and only then mark the ticket integrated. A failed merge or check stops dispatch until repaired; never report it as success.

6. If this changes the **frontier** of available tickets, kick off more **implementer subagents** to work on the new tickets. This allows for maximum concurrency.

7. Once all tickets are complete, call the Skill tool with `code-review` on the integration branch. Fix all issues raised by the code review in a single **implementer subagent**. Supply the starting base commit, exact integration head and spec, and request a read-only review that returns findings to this orchestrator without posting or invoking successors. Merge fixes through the merger and run focused checks for the findings plus the declared feedback loops. Do not start another broad review inside this run or review individual tickets against the whole spec. If fixes move the head, record the new head as not yet reviewed; never carry a clean review forward to it.

8. If a draft PR exists, mark it ready for review once checks pass and findings are addressed. Otherwise, resolve each ticket the way the issue tracker closes work, and report the integration branch. Post the per-ticket evidence before resolving tickets; a draft PR's closing references leave them open until it merges. Unresolved findings or failed checks keep the draft open and the affected tickets unresolved.

9. Clean up all **implementer subagent** worktrees and all other run-owned worktrees and branches as described below, publish the spec evidence, then route through `/next`.

## Evidence and cleanup

Before resolving a ticket, post a per-ticket evidence comment naming
`/implement-spec`, the full integration merge commit SHA, the integration branch
or draft PR, and the checks and outcome. Use the configured tracker commands
(`gh issue comment <ticket> --body-file <evidence>` for GitHub). Publish integration
commits before linking them on a remote tracker. For a local markdown tracker,
append the same evidence to the ticket. Failed checks are evidence of a blocker,
not resolution.

The run must remove every worktree and branch it created once their work is
preserved. This includes integration, merger, exploration and review-fix worktrees,
not just ticket worktrees. On success, failure or cancellation, first wait for or
stop all owned agents and processes, then reconcile the run-owned inventory.
Restore the starting checkout before removing worktrees with `git worktree remove`;
remove their local branches only after checking their commits are preserved on
the integration branch. Never force-remove dirty worktrees or delete the
sole copy of the work. Do not remove pre-existing worktrees or branches.

Preserve the integration result before deleting its local branch: for a remote
tracker, push it and verify the remote head matches, leaving that published branch
or PR as the deliverable. For a local-only tracker, retain the integration branch
as the deliverable until the user integrates it; do not destroy offline output to
satisfy cleanup. A dirty, unmerged or unremovable artifact is a retained worktree
or branch: name its exact path/ref, reason and recovery action, and report cleanup
incomplete rather than forcing deletion.

After cleanup, post one evidence comment on the spec naming `/implement-spec`,
the integration branch (or draft PR), final head SHA, reviewed head SHA and base,
the separate Standards and Spec review outcomes, any fix commit and focused-check
results, ticket merge SHAs, and cleanup results or retained artifacts. On a partial
run, name blocked tickets and say explicitly if review was not run. Do not claim
the final head is review-clean if remediation changed it.

Call the Skill tool with `next`, passing the spec and evidence pointer. This
orchestrator owns the transition; its subagents must return results without
closing tickets or invoking `/next` themselves. `/next` decides the next gate;
this skill never merges the integration branch into the default branch.
