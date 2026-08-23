---
status: proposed
---

# A worktree is removed only when something vouches for it

`/sweep-worktrees` reclaims working directories that are finished or abandoned. It removes a
worktree only when a **worktree marker** inside it names the process that owns it and that process
is gone. A worktree with no marker is reported, never removed on sight — but it is not immune
forever: a directory observed unchanged and unheld across two or more **sweeps** earns a marker from
the sweeper's own observations and becomes removable on the same terms as a marked one.

Uncommitted changes refuse removal in every case, marked or corroborated, live or dead. A marker and
a departed owner say the directory is finished with; neither says the work inside it exists anywhere
else. This is the same rule
[ADR-0006](./0006-the-chain-may-merge-on-this-workflows-own-evidence.md) applies at the merge
boundary, and it is the sweeper's most protective invariant precisely because it is the one no
amount of evidence about ownership can override.

## Why liveness cannot be observed directly

The obvious rule — remove what nothing is using — does not work, and the reason is specific to how
agents hold worktrees.

An agent process does not sit in its worktree. It runs from the repository root and passes
`cd <worktree> && …` into each command, so the only processes with a working directory inside the
worktree are transient shells. Between two commands, while the model is thinking, **nothing holds
the directory at all**. Probed live, three worktrees belonging to three running agents were clean,
sat at the same commit as `main`, carried no identifying file, and were held by nothing — byte for
byte indistinguishable from three abandoned ones.

Corroboration across sweeps is what replaces the observation that cannot be made. A working agent
survives because the next sweep observes its worktree changed or held — evidence about that
directory — rather than because a timer happened to be generous.

It is stronger than a timer, not a proof. An agent that neither writes nor runs a command across two
whole sweeps is still clean and still unheld, and the sweeper will vouch for it wrongly. What that
costs is bounded by where corroboration is the only evidence available: the chain's own reservations
carry a marker from `chain.sh reserve`, and `/next`'s prompt convention marks what it creates, so
corroboration is the sole basis for removal only in worktrees the `git-loopy --parallel` runner
made. Requiring positive owner-termination evidence everywhere would close that hole and make those
worktrees permanently unsweepable, which is the trade weighed below. #66 records the residual risk
as its own question rather than leaving it implied here.

## Considered Options

- **Remove what nothing is using.** Rejected: as above, "nothing is using it" is the normal state
  of a live agent's worktree, so the rule deletes working directories mid-thought.
- **Remove anything older than a threshold.** The first answer, and the one most likely to be
  re-proposed. It converts "an agent thought for longer than I guessed" into deleted work that
  exists in no commit and no remote. The threshold is not tuning a false-positive rate; it is
  choosing how long a model may think before its directory is destroyed underneath it. Corroboration
  is strictly stronger at the same cost, because it reasons about the directory rather than the
  clock.
- **Require positive owner-termination evidence for every worktree.** The strictest rule, and the
  only one with no false removals. Rejected because nothing marks what the `git-loopy --parallel`
  runner creates, so the rule would make its worktrees permanently unsweepable — and that runner is
  the producer that makes the most of them, so the skill would be left sweeping almost nothing. The
  cost of rejecting it is the residual risk above, which #66 carries.
- **Record observations in `subagents.jsonl`.** Rejected: `chain.sh`'s lock is built for short
  critical sections, and a sweep walks directories and calls `gh`. Holding that lock across a
  network round trip would stall every `reserve`, `bind`, and `complete` behind it. The two files
  also record opposite things — runs the chain owns, against directories nobody claims.
- **Give the sweeper every worktree.** Rejected for the ownership reasons below: it would put a
  second implementation of `complete` and `recover` inside a skill, and starve the chain of slots
  between a run finishing and the next sweep.

## Why the sweeper does not own every worktree

Four kinds of worktree exist in this workflow, and the sweeper owns two of them.

A **completed chain reservation** is removed by `chain.sh complete`, inside the ledger lock, in the
same step that releases the concurrency slot. That cannot move. Deferring it to a skill run would
leave slots held between the run finishing and the next sweep, starving the chain — a regression
wearing the clothes of a decoupling.

An **orphaned reservation** is a ledger row, and `CONTEXT.md` already names it. `chain.sh recover` is
written for it and #28 owns wiring it up, with the explicit instruction to reuse the existing
stale-lock recovery rather than invent a second mechanism. The sweeper calls `recover`; it does not
reimplement it.

That delegation is to a mechanism which does not yet honour this record. `recover` as written closes
every open row older than its stale threshold and then force-removes the worktree, with no liveness
check anywhere in that path — the pid and start-time check lives only in stale-lock recovery and
never looks at ledger rows. It is exactly the timer rejected above. The objection does not stop
applying at a delegation boundary, so #64 owes `recover` that liveness check before the sweeper
leans on it; until then, a sweep that calls `recover` inherits the failure mode instead of escaping
it.

That leaves the sweeper the worktrees **no ledger tracks**: those the `git-loopy --parallel` runner
creates, and those an agent creates itself because a `/next` prompt told it to. This is where the
clutter actually is, and it is the only region with no owner at all.

A fifth kind nearly exists, and is designed out rather than owned. `reserve` accepts any `--target`
string, while `complete` resolves that target against the tracker and exits before closing the row
if it does not resolve. A row bound to a target that never existed therefore holds a slot and a
worktree it can never release, and it fits none of the four: it is bound, so it is not an orphaned
reservation, and it is ledger-tracked, so it is not the sweeper's. The answer is to stop creating it
— `reserve` and `plan` validate the target when the row is written, at the same boundary `complete`
already validates it — rather than to admit it as a fifth kind with an owner to match. Every open row
being closable is a property the four assume, and #63's validation is what makes it true.

## Consequences

- **Producers must mark what they create.** `chain.sh reserve` already knows the owning process and
  writes a ledger row in the same lock, so the marker costs it nothing. `/next`'s worktree-creating
  prompt convention gains a second command alongside its `git worktree add`.
- **One producer is out of reach, and the observation ledger is the answer.** The `git-loopy` runner
  lives in another repository; nothing decided here reaches it. Without corroborated observation its
  worktrees would be permanently unsweepable, which would hollow out the skill, since it is the
  producer that makes the most of them. Observation lets the sweeper earn the marker it was not
  handed, without weakening the rule that a single look removes nothing.
- **The sweeper carries durable state, and it lives apart.** Observations go in an **observation
  ledger** of their own, with its own lock, rather than into `subagents.jsonl`.
- **The sweeper is a route but never allowlisted.** Clutter is a genuine gate: `chain.sh` declines
  spawns with `worktree-in-flight`, and unreclaimed directories accumulate until the chain cannot
  spawn at all, so `/next` has reason to recommend a sweep. The chain still may not spawn one. Every
  other route targets a ticket; this one targets the fleet, and its subject matter is the working
  directories of up to nine concurrent agents. `/next` ranks by "an action another agent already
  holds is spoken for" — a rule the sweeper can never satisfy, because held directories are the
  thing it inspects.
- **The sweeper finishes what `/merge` starts, and only that half.** ADR-0006 leaves the local
  worktree and local branch alone after a merge. The sweeper removes the worktree and then the
  branch it freed, in that order, because git refuses to delete a branch checked out in a worktree.
  It cannot shortcut the decision by asking git whether the branch merged, for the ancestry reason
  ADR-0006 records.
- **Branches on the chain's own path are left unowned.** The rule above reaches only a branch a
  sweep can still see holding a worktree. The chain's reservations have their worktree removed by
  `chain.sh complete` long before any sweep runs, and nothing deletes the branch, so on the mainline
  `/implement` → `/code-review` → `/push` → `/merge` path the local branch outlives every mechanism
  here. This repository already shows the symptom. Nothing in this decision reclaims it; #65 decides
  what does.
- **The marker does not close #47 on its own.** `/next` step 1 attributes an in-flight worktree
  through `.git-loopy/logs/`, a path that does not exist. The marker supplies the missing record for
  the directories it covers, but it names the owning **process**, and step 1 needs the **target**
  that process bound in order to call a workstream in flight. It also reaches nothing the `git-loopy
  --parallel` runner creates, where observation yields removability after two sweeps and never
  attribution. Whether the marker carries the target too is left to whoever gives step 1 a record it
  can read; this decision only makes the marker available to carry it.
