# A worktree is removed only when something vouches for it

`/sweep-worktrees` reclaims working directories that are finished or abandoned. It removes a
worktree only when a **worktree marker** inside it names the process that owns it and that process
is gone. A worktree with no marker is reported, never removed on sight — but it is not immune
forever: a directory observed unchanged and unheld across two or more **sweeps** earns a marker from
the sweeper's own observations, and becomes removable like any other.

## Why liveness cannot be observed directly

The obvious rule — remove what nothing is using — does not work, and the reason is specific to how
agents hold worktrees.

An agent process does not sit in its worktree. It runs from the repository root and passes
`cd <worktree> && …` into each command, so the only processes with a working directory inside the
worktree are transient shells. Between two commands, while the model is thinking, **nothing holds
the directory at all**. Probed live, three worktrees belonging to three running agents were clean,
sat at the same commit as `main`, carried no identifying file, and were held by nothing — byte for
byte indistinguishable from three abandoned ones.

An age threshold was the first answer and is not good enough. It converts "an agent thought for
longer than I guessed" into deleted work that exists in no commit and no remote. The threshold is
not tuning a false-positive rate; it is choosing how long a model is allowed to think before its
directory is destroyed underneath it.

Corroboration across sweeps is strictly stronger. A thinking agent survives because the next sweep
observes its worktree changed or held — evidence about that directory — rather than because a timer
happened to be generous.

## Why the sweeper does not own every worktree

Four kinds of worktree exist in this workflow, and the sweeper owns two of them.

A **completed chain reservation** is removed by `chain.sh complete`, inside the ledger lock, in the
same step that releases the concurrency slot. That cannot move. Deferring it to a skill run would
leave slots held between the run finishing and the next sweep, starving the chain — a regression
wearing the clothes of a decoupling.

An **orphaned reservation** is a ledger row, and `CONTEXT.md` already names it. `chain.sh recover`
is written for it and #28 owns wiring it up, with the explicit instruction to reuse the existing
stale-lock recovery rather than invent a second mechanism. The sweeper calls `recover`; it does not
reimplement it.

That leaves the sweeper the worktrees **no ledger tracks**: those the `git-loopy --parallel` runner
creates, and those an agent creates itself because a `/next` prompt told it to. This is where the
clutter actually is, and it is the only region with no owner at all.

## Consequences

- **Producers must mark what they create.** `chain.sh reserve` already knows the owning process and
  writes a ledger row in the same lock, so the marker costs it nothing. `/next`'s worktree-creating
  prompt convention gains a second command alongside its `git worktree add`.
- **One producer is out of reach, and the observation ledger is the answer.** The `git-loopy`
  runner lives in another repository; nothing decided here reaches it. Without corroborated
  observation its worktrees would be permanently unsweepable, which would hollow out the skill,
  since it is the producer that makes the most of them. Observation lets the sweeper earn the marker
  it was not handed, without weakening the rule that a single look removes nothing.
- **The sweeper carries durable state, and it lives apart.** Observations go in their own file with
  its own lock rather than into `subagents.jsonl`. `chain.sh`'s lock is built for short critical
  sections; a sweep walks directories and calls `gh`, and holding that lock across a network round
  trip would stall every `reserve`, `bind`, and `complete` behind it. The two files also record
  opposite things — runs the chain owns, against directories nobody claims.
- **The sweeper is a route but never allowlisted.** Clutter is a genuine gate: `chain.sh` declines
  spawns with `worktree-in-flight`, and leaked reservations accumulate until the chain cannot spawn
  at all, so `/next` has reason to recommend a sweep. The chain still may not spawn one. Every other
  route targets a ticket; this one targets the fleet, and its subject matter is the working
  directories of up to nine concurrent agents. `/next` ranks by "an action another agent already
  holds is spoken for" — a rule the sweeper can never satisfy, because held directories are the
  thing it inspects.
- **The sweeper finishes what `/merge` starts, and only that half.**
  [ADR-0006](./0006-the-chain-may-merge-on-this-workflows-own-evidence.md) leaves the local
  worktree and local branch alone after a merge. The sweeper removes the worktree and then the
  branch it freed, in that order, because git refuses to delete a branch checked out in a worktree.
  It cannot shortcut the decision by asking git whether the branch merged: squash-merging leaves the
  branch outside `main`'s ancestry, so a merged branch and an abandoned one look the same locally.
