# Git Loopy Skills

A set of agent skills for the engineering workflow, from a rough idea through to published work.
This glossary pins the terms the skills use about each other and about the work they route.

## Language

### Routing

**Route**:
A skill named as the action to take now. `/next` returns one.
_Avoid_: Step, stage, phase

**Gate**:
The earliest unresolved condition standing between the work and its destination. `/next` picks the
route that clears it, rather than the next item on a checklist.
_Avoid_: Blocker (a blocker is recorded on a ticket; a gate is derived from live state)

**AFK-safe**:
A mark on a route whose target is fully specified and needs no further human judgment.
_Avoid_: Autonomous, unattended

**HITL**:
A mark on a route that still needs a human decision. The opposite of AFK-safe.
_Avoid_: Manual, interactive

**Allowlisted route**:
One of the five routes the chain is permitted to spawn without asking: `/implement`,
`/code-review`, `/research`, `/push`, `/resolving-merge-conflicts`, with `/merge` joining them when
#58 lands. Being allowlisted is necessary but not sufficient — the route must also be AFK-safe.

### The chain

**Chain**:
The self-driving succession of spawned runs, where each finished run triggers `/next` and `/next`
may spawn the run that follows. Distinct from a **loop**, which `/loop-me` defines as a recurring
pattern in a person's life.
_Avoid_: Loop, pipeline, autopilot

**Chain depth**:
How many hops a single target's lineage has taken since a human last spoke. Counted per target, not
per session, so one stuck target cannot be masked by unrelated activity.

**Checkpoint boundary**:
The point where the chain stops spawning and asks a human. Reached when a route is not allowlisted,
is marked HITL, or trips a guard. It is the **checkpoint** of `/loop-me`'s vocabulary, pushed as far
right as the work allows.

**Spawn ledger**:
The per-repository record of the chain's own state — what was spawned, against which target, in
which worktree, how it ended, and how deep its lineage runs. Holds what neither the issue tracker
nor the CLI's own session records capture.
_Avoid_: Log, history

**Reservation**:
A ledger row written before its run exists, claiming a concurrency slot and a worktree. It carries
the route and target but no agent identity yet, because the runtime assigns that only once the
agent starts.
_Avoid_: Placeholder, pending row

**Binding**:
Attaching the runtime-assigned agent identity to a reservation, which is what later lets a
completion payload find its row.

**Orphaned reservation**:
A reservation that never got bound, because the spawn failed or its parent died in between. It
holds a slot no agent will ever release, so it is reclaimed by checking whether the parent is still
alive, with a timeout as backstop — the intent of `chain.sh recover`, which is the timeout alone
until #64 adds the liveness check.
_Avoid_: Stale row, dangling row

**Completed chain reservation**:
A ledger row whose run has finished. `chain.sh complete` removes its worktree inside the ledger
lock, in the same step that releases its concurrency slot, so it is never a sweep's to reclaim.

**In flight**:
Describes a target currently held by a running agent. An in-flight target is spoken for: routing a
second agent at it would duplicate or corrupt the work.

### Worktrees and sweeping

**Stale worktree**:
A working directory whose work is finished or abandoned and which no live process holds. Distinct
from an **orphaned reservation**, which is a ledger row holding a concurrency slot: a stale worktree
is a directory, it may come from a producer no ledger tracks, and it holds nothing but disk.
_Avoid_: Dead worktree, leftover

**Worktree marker**:
The record inside a worktree naming the process that owns it and when that process started, together
with the route and target it bound. The first pair decides removal; the second attributes the
directory to a workstream. A worktree carrying none cannot be vouched for, so nothing removes it on
a single look.
_Avoid_: Lock file, sentinel

**Held**:
Said of a worktree a live process is using at the moment it is looked at. Weak evidence on its own,
because an agent's worktree is unheld between commands while the model thinks.
_Avoid_: Busy, locked, in use

**Marked**:
Said of a worktree carrying a worktree marker, whichever producer wrote it — the process that
created the directory, or the sweeper after corroboration.

**Vouched**:
Said of a worktree something answers for: it is marked and the process named is gone. Unvouched is
the absence of that, and earns a report rather than a removal.
_Avoid_: Verified, confirmed, approved

**Sweep**:
One pass over every worktree, classifying each as held, marked, or unvouched. Corroboration is
counted in sweeps rather than elapsed time, because a directory unchanged across two of them is
evidence about that directory, where an idle timer is only a guess about how long an agent thinks.
_Avoid_: Scan, cleanup run

**Observation ledger**:
The sweeper's own durable record of what each sweep saw in each unvouched directory. Separate from
the spawn ledger because it holds directories nobody claims, where that one holds runs the chain
owns.
_Avoid_: Sweep log, history

### The merge boundary

**Merge boundary**:
The point where a reviewed head enters the default branch. A human's by rule today;
[ADR-0006](./docs/adr/0006-the-chain-may-merge-on-this-workflows-own-evidence.md) moves it to
whatever the merge evidence says, which is why the chain may cross it and a bare `git merge` may
not.
_Avoid_: Ship, land

**Merge evidence**:
What makes an unattended merge legitimate: GitHub's own mergeable state, a matchable `review-clean`
record from `/code-review` that nothing emits yet, and every check green. It is this workflow's own
record rather than the remote's branch protection, because a repository may require nothing and
still be merged into.
_Avoid_: Approval, sign-off (an approval is one possible input, not the whole set)

### Connection kinds

The kinds of edge one skill can have to another. The first four are the vocabulary of
`docs/skill-connections.md`; the fifth was added when `/next` gained the ability to spawn.

**Routes to**:
One session ends and another begins.

**Runs inside**:
Nested in the caller's session, owning no transition and recording nothing of its own.

**Publishes to**:
Leaves a durable evidence comment that a later session reads back.

**Reads config from**:
Depends on files another skill wrote.

**Spawns**:
Starts a subagent that runs concurrently inside the caller's session, yet owns its transition and
publishes its own evidence. It is nested like **runs inside** but records like **routes to**, which
is why neither of those kinds describes it.

**Evidence comment**:
The durable comment a skill leaves on the ticket it acted on, gisting what it did and naming the
skill that succeeds it. It is how state crosses between runs, so a run that publishes none is
indistinguishable from one that failed.
