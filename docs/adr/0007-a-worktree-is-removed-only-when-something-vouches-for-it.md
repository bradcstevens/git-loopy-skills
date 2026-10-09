---
status: proposed
---

# A worktree is removed only when something vouches for it

`/sweep-worktrees` reclaims working directories that are finished or abandoned. It removes a
worktree only when a **worktree marker** inside it names the process that owns it and that process
is gone. A worktree with no marker is reported, never removed on sight — but it is not immune
forever: a directory observed unchanged and unheld across two or more **sweeps** earns a marker from
the sweeper's own observations and becomes removable on the same terms as a marked one.

Uncommitted changes refuse removal in every case, marked or corroborated, live or dead. Untracked
files count as uncommitted: the sweeper cannot tell a scratch file from an unsaved source file, and
the removal it would otherwise perform is `git worktree remove --force`. A marker and a departed
owner say the directory is finished with; neither says the work inside it exists anywhere
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

## Considered options

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

A **completed chain reservation** releases its slot inside `chain.sh complete`'s ledger lock.
`complete` removes the worktree in that same step when it is clean; any other worktree becomes a
**retained worktree** (see Amendments) rather than risk deleting work that exists nowhere else.
That cannot move. Deferring slot release to a skill run would leave slots held between the run
finishing and the next sweep, starving the chain — a regression wearing the clothes of a decoupling.

An **orphaned reservation** is a ledger row, and `CONTEXT.md` names it. `chain.sh recover` reuses the
existing stale-lock recovery machinery to verify the reserving parent's process identity. It
reclaims an unbound reservation when its parent is gone, with age as a backstop, and reclaims a
bound **abandoned run** only when its parent is proven gone. The sweeper calls `recover`; it does not
reimplement it.

That leaves the sweeper the worktrees **no ledger tracks**: those the `git-loopy --parallel` runner
creates, and those an agent creates itself because a `/next` prompt told it to. This is where the
clutter actually is, and it is the only region with no owner at all.

A fifth kind nearly existed and is designed out rather than owned. `reserve` and `plan` validate a
target before writing a row or creating a worktree, so a target that does not resolve cannot claim a
slot. `complete` still resolves the target over the network: if the tracker cannot answer, it
closes the row as `tracker-failed` rather than treating the failure as `no-evidence`, and removes a
clean worktree or retains one that is not.
Issue #63 implements both boundaries, so a failed lookup no longer leaves an open row.

## Consequences

- **Producers must mark what they create, and the marker carries enough to attribute.** It records
  the owning process and its start time, which is what removal turns on, and the route and target
  that process bound, which is what attribution turns on. `chain.sh reserve` already holds all four
  and writes a ledger row in the same lock, so the marker costs it nothing. `/next`'s
  worktree-creating prompt convention gains a second command alongside its `git worktree add`.
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
- **A branch is a sweepable object in its own right.** The worktree-then-branch rule above reaches
  only a branch a sweep can still see holding a worktree, and on the chain's mainline `/implement` →
  `/code-review` → `/push` → `/merge` path no such sweep ever happens. Every reservation is given a
  branch of its own — `chain.sh` names it `git-loopy/reservation-<pid>-<random>` as it creates the
  worktree — `complete` removes that worktree when it is clean and retains it otherwise. No
  `git branch -d` appears anywhere in `chain.sh`.
  A retained worktree keeps its branch visible to a sweep; once a clean worktree is removed, its
  branch has no worktree and is no longer visible that way. So a sweep classifies a branch with no
  worktree too, and what vouches for one is the answer ADR-0006 already forces: ancestry proves
  nothing under squash, so the sweeper asks GitHub whether that branch's pull request merged. A
  merged branch is removable; an unmerged or never-pushed one is reported and never removed,
  because it may be the only copy. #65 implements it.
- **The marker narrows #47 rather than closing it.** `/next` step 1 attributes an in-flight worktree
  through `.git-loopy/logs/`, a path that does not exist. Three producers need three different
  answers. Worktrees the chain created are already attributable and always were — `chain.sh reserve`
  writes route, target and worktree into the ledger row, so the record step 1 wants is the spawn
  ledger and its premise was pointed at the wrong file. Worktrees an agent created for itself have
  no ledger row, and they are what the marker's route and target serve. Worktrees the `git-loopy
  --parallel` runner created stay unattributable whatever is decided here, because that runner lives
  in another repository and observation yields removability after two sweeps and never attribution.
  #47 therefore shrinks to that last producer instead of closing.

## Amendments

Issue #63 (PR #79) amended this record while it was still proposed. The edits above change what
was originally stated, so they are listed here rather than left to be found by diff:

- **The liveness check and fail-safe obligations are partly discharged, not dropped.** The record
  said #64 owed `recover` a process-liveness check before the sweeper could lean on it, and #63
  owed `reserve`, `plan` and `complete` the validate-and-fail-safe pair. The pair is implemented.
  `recover` now reuses `claim-recovery.py owner-gone` for bound rows, so a bound run is reclaimed
  only when its parent is proven gone; the unbound age backstop below remains, so #64 is not closed
  by this amendment. The "owes" wording is replaced by a statement of what the code does.
- **Age remains a backstop only for unbound reservations, and clean-only removal bounds its cost
  without closing its risk.** The rejected threshold option is not reopened. `complete` and
  `recover` never force-remove a worktree, so the backstop can no longer delete unsaved work. It can
  still remove the clean directory of a live agent whose `bind` was late or lost, which the argument
  above shows is indistinguishable from an abandoned one; that residual risk is the existing
  backstop's (#28), and this amendment does not claim to close it.
- **A population exists that the taxonomy does not name: the retained worktree.** When `complete` or
  `recover` leaves a **retained worktree** (`CONTEXT.md`), the row still closes and the slot is
  released, so it is no longer a reservation. It holds no open row, so the sweeper meets it as an
  unmarked worktree: reported, never removed on sight, and removable only once it is clean and has
  earned a marker through corroboration. Until `chain.sh reserve` writes a marker itself (#51),
  nothing else vouches for it. ADR-0002's first Consequence is revised to match.
- **The branch-visibility consequence changes with it.** It said a reservation's branch outlives
  the only thing that would have made it visible to a sweep, "by construction", because `complete`
  always removed the worktree. A retained worktree now keeps its branch visible; a branch whose
  worktree was cleanly removed is still the branch-with-no-worktree case #65 implements.
