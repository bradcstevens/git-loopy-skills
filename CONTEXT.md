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
`/code-review`, `/research`, `/push`, `/resolving-merge-conflicts`. Being allowlisted is necessary
but not sufficient — the route must also be AFK-safe.

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

**In flight**:
Describes a target currently held by a running agent. An in-flight target is spoken for: routing a
second agent at it would duplicate or corrupt the work.

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
