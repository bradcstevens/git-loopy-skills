Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=next
```

```bash
npx skills update next
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next)

## What it does

`next` is the router over the skills in this repo. It reads the live state of your work and returns a single recommendation: the one action to take now, the skill that performs it, the exact invocation to paste, and the runtime to run it on — the model, reasoning effort, and context window that skill's own header sets. For a narrowly defined set of **AFK-safe** delivery routes, it can also spawn that recommendation as an in-session subagent.

It also replaces `/skill-router`: ask `/next` which skill or flow fits the current
situation. Its co-installed `SKILL-SELECTION.md` covers interview wrappers, build
scope, and standalone requests such as release, human-only setup, learning, agent
writing, and model configuration. Those requests use the context their branch
needs rather than requiring an engineering tracker and chain hook.
Interview wrappers retain the project's domain language in `GLOSSARY.md`.

It does not itself grill, write a spec, or fix anything. It either orients at a checkpoint boundary or, when the chain gate approves, records and launches work owned by the spawned route. What separates it from a checklist is where it looks: not at what you told it in conversation, but at `docs/agents/issue-tracker.md`, the tracker itself, and your branch and diff. Concurrent sessions move that state underneath you, so the recommendation is drawn from live records rather than from a session summary.

## When to reach for it

Invoke `/next` directly when a workflow skill concludes or the next step is unclear. It is user-invoked rather than selected automatically by the agent.

Reach for it whenever you're unsure which skill or flow a situation calls for: a skill just finished and you don't know what follows, you have an idea and don't know where to start, or two skills look interchangeable and you can't tell them apart. If you already know the skill you want, skip the router and invoke it directly.

## The earliest unresolved gate

The idea `next` runs on is the **gate**, the first unresolved condition standing between the work and its destination. The flow is composable, not a fixed sequence, so it doesn't ask "which step comes after the last one" but "what is the earliest thing still unresolved". An idea that still has human decisions in it gates on grilling; an agreed build destination with no durable spec gates on [to-spec](./to-spec.md); an unblocked ticket gates on [implement](./implement.md). Ranking follows from that: ready actions before blocked ones, the workstream you're already in before a cold one, and the action that clears the most downstream blockers before the rest.

Every recommendation is labelled **HITL** or **AFK-safe** — whether the next action needs your judgement, or is specified tightly enough to be left to run on its own. Blocked actions are still returned, but must name the condition that would make them ready.

### Wayfinder destinations

[Wayfinder](./wayfinder.md) finishes a map when there is no open decision ticket and no fog
in **Not yet specified**, not merely when its ticket list is empty. It closes the map
with a closing summary comment. `next` reads that comment, the named destination,
and the recorded decisions before applying the generic spec gate.

| Map state | Route |
| --- | --- |
| Open frontier or remaining fog | Continue `/wayfinder` |
| Finished, specification destination | Continue from the spec through the usual gates; wayfinder already called `/to-spec` |
| Finished, decision destination | No next route: report completion unless the recorded decisions themselves call for follow-up work; route that work through its own gate |
| Finished, in-place change or proof of concept still to build | `/to-spec`, or `/implement` only when the effort proved genuinely small |

Do not synthesize an existing spec again. If the specification handoff has not
produced a durable spec, name that missing spec as the unresolved gate.
A finished decision destination does not need a spec or a build just to count as complete.

This is a kept git-loopy overlay over upstream `ask-matt` at pin
`49dd158d1076134a641b33efb035946536778336`: upstream merges every cleared map
at `/to-spec`; git-loopy routes by the destination instead.

### Decomposition

A spec without executable tickets routes to `git-loopy plan <spec>` when
`docs/agents/issue-tracker.md` and `.github/hooks/git-loopy-chain.json` exist and
`git-loopy` is on `PATH`. Otherwise the decomposition route remains `/to-tickets`
in the current conversation; missing repository configuration still gates on
setup first.

The Planner recommendation is **HITL**, **Fresh session**, with **Runtime:
git-loopy planning Routing** and a shell command carrying the published spec
issue URL. This is the exception to the skill-runtime and paste-a-prompt format
below. Run it interactively from the repository; `/next` neither spawns it as a
chain subagent nor decomposes in the old context. Publish any decisions that
remain only in conversation before handing off.

### Whole-spec builds and retrospectives

Once a spec has executable tickets, [implement-spec](./implement-spec.md) is the
**HITL**, user-invoked alternative to driving [implement](./implement.md) per
ticket. It coordinates the ready frontier in parallel on one integration branch
and finishes with a review of that branch; it does not replace decomposition.

`next` offers [retro](./retro.md) after a build or a `/diagnosing-bugs` fix,
before considering [improve-codebase-architecture](./improve-codebase-architecture.md).
The retrospective improves the agent's environment, not the code. Run it in the
session it examines before clearing, or point it at that session's log afterward.
It is **HITL** and user-invoked: completed or declined retrospectives are not
offered again for the same work. Accepted improvements return through the relevant
idea, spec, or ticket gate. A diagnosis exposing a missing seam or structural cause
can then warrant an architecture survey.

Publication still routes to [push](./push.md). [pr](./pr.md) shapes the body
inside `/push`; it is not a direct route.

### Portable context and long-running goals

The co-installed `PHASE-BOUNDARIES.md` uses the upstream ordered tree: continue,
clear irrelevant context, make a portable file, delegate AFK work, then compact.
The first applicable choice wins; decide at a phase boundary, not mid-phase.
Portability routes to [to-handoff](./to-handoff.md) for a new harness (for example,
Copilot CLI to Codex), a new directory, a colleague, or a mid-phase side task.
A prototype detour uses it in both directions when context must travel.
The recommendation says **Continue here** to write the file; the user takes it
to the destination. It does not launch a session.

[handoff](./handoff.md) keeps its separate job: launching a `/next` recommendation
in the background on its resolved runtime. It is neither the portable-file writer
nor the chain's in-session launcher.

For a long-running goal held in one session, [chief-of-staff](./chief-of-staff.md)
coordinates subagents and recurring schedules while retaining strategic context.
Like `/implement-spec` and `/retro`, `/to-handoff` and `/chief-of-staff` are
**HITL**, user-invoked recommendations. This map does not enlarge the chain allowlist.

## The sessions it tracks

Before ranking anything, `next` runs `scripts/sessions.py scan` to see which GitHub Copilot CLI sessions are live in the repository. A session counts as live when its `~/.copilot/session-state/<id>/inuse.<pid>.lock` names a running `copilot` process. The session's `workspace.yaml` places it in the main checkout or in one of its worktrees. The scan reports each worktree with the sessions working in it, along with their names, branches, and any chain targets they hold. An action another session already holds is left to that session.

Each run appends its scan to the **session log**, `.git-loopy/next/sessions.jsonl` at the repository root. The `.git-loopy/` runtime directory is gitignored and shared by every worktree. Each line records when the scan ran, which session invoked `/next`, and the sessions it saw. The next scan compares against that line, so it reports each session as `new` or `continuing` and lists the ones that have `ended` since. Pass `--no-record` to look without logging.

## Worktree sweep

`skills/next/scripts/sweep.sh` reports every registered working tree. Without `--remove` it is read-only: it writes no markers, takes no ledger locks, recovers no reservations, prunes no Git metadata and removes nothing. Run it from any checkout, or specify a repository:

```bash
bash skills/next/scripts/sweep.sh --repo /path/to/repository
bash skills/next/scripts/sweep.sh --repo /path/to/repository --remove
```

It requires Git, Python 3.9 or newer, `lsof` and `pwd` on `PATH`. It makes no network requests unless `--remove` frees a branch, which needs `gh`. `CHAIN_PYTHON` selects the interpreter, as it does for `chain.sh`. It drops the repository variables `git rev-parse --local-env-vars` names, such as the `GIT_DIR` a git hook exports, while keeping `-c` configuration as git itself does, so it always sweeps the repository `--repo` names or the current directory. It prints one JSON object with `worktrees`, `counts` (held, marked and unvouched), and the resolved spawn `ledger` path. A bare repository entry is not a working tree and is excluded; with no working trees the array is empty and every count is zero. An all-unvouched result instead has entries and a positive unvouched count.

Each entry includes `path`, `branch` (a full ref, or null when detached), `locked`, `classification`, `holder_pids`, `owner_alive`, `ledger_rows`, `exists`, `dirty` and `errors`. Classification follows this precedence:

- **Held:** `lsof` observes a process with its current directory or an open file in the worktree. The sweep, its `lsof` child and the helpers that `lsof` forks on Linux do not count. Nested paths belong to the innermost registered worktree. Paths are compared as `lsof` spells them under `LC_ALL=C`, where a control byte such as BEL prints as `^G` and byte 0xff prints as `\xff` or `^?` depending on the platform. A literal `^G` shares that spelling, so a name that could mean several worktrees holds all of them. Each worktree is also matched by the kernel's own spelling of its directory (`pwd -P`), which can differ from git's record in case or Unicode normalization. `lsof` may follow a name with an annotation such as ` (deleted)` or an NFS ` (host:/export)`, which is read as the end of the path. A nested worktree outranks its parent only when its directory exists, inspects cleanly and belongs to this repository, and the name continues its path with no caret or annotation in between; otherwise the outer worktree is held as well as the inner one. A vanished directory is spelled through its nearest surviving ancestor, and its holders are also matched ignoring ASCII case.
- **Marked:** a `.git-loopy/worktree-owner` marker exists. `chain.sh owner` supplies owner liveness, including its PID-reuse protection and conservative treatment of an unparseable start time. A live marker owner alone does not mean the directory is currently held.
- **Unvouched:** neither of those signals exists. A ledger-only worktree remains unvouched: `ledger_rows` separately counts all matching spawn-ledger rows, including closed ones; the sweep never manufactures a marker from a row.

The default ledger is the main repository's `.git-loopy/subagents.jsonl`, including when invoked from a linked checkout. `--ledger PATH` overrides `CHAIN_LEDGER` and the default. A separate-git-dir checkout uses the chain's existing root anchor; without that anchor, invoke the sweep from the main checkout so its location is known. The sweep never creates an anchor.

`dirty` includes staged, unstaged, untracked and submodule changes, excluding only `.git-loopy/worktree-owner`. A vanished directory still gets an entry with `exists: false` and `dirty: null`; only `--remove` prunes it. A directory the sweep cannot inspect gets `exists: null` and an error instead, so it is never mistaken for a vanished one. An unreadable or invalid marker leaves `owner_alive: null` and an error rather than claiming its owner is dead. An uninspectable checkout similarly leaves `dirty: null`; other worktrees are still reported. A row with errors is unreliable: its classification can be wrong, for example when the kernel's spelling of its directory or a marker behind an unsearchable directory cannot be read, so nothing should act on it. A warning from `git status`, such as an unreadable untracked directory, is such an error and leaves `dirty: null`.

Exit status is **0** for a complete report (including missing directories), **1** for inspection errors and **2** for invalid arguments or a missing interpreter or one older than Python 3.9. Per-worktree errors appear in the JSON entry; repository, ledger (including, under `--remove`, a malformed or unreadable pending worktree record, or a ledger `chain.sh recover` rejects) and process-enumeration failures emit an `error:` diagnostic on stderr and no success-shaped report. Any `lsof` diagnostic, non-zero exit or empty listing is such a failure, since `lsof` always lists at least itself. A failure after `chain.sh recover` ran also prints what recovery had already done. `lsof` visibility is limited to what the invoking account can inspect, and the report is a point-in-time observation, never proof that removal is safe. Two holders still escape it without an error: macOS `lsof` prints only the tail of a name longer than about 1 KB, and a process inside a deleted directory whose own name, as git recorded it, differs from the deleted name other than in ASCII case. Removal must not rest on `held` alone.

### Removal

With `--remove`, the sweep first hands the spawn ledger to `chain.sh recover --ledger <ledger>`, with the `CHAIN_RESERVATION_STALE_SECONDS` threshold `chain.sh plan` passes (300 seconds when unset or empty). Recovery owns orphaned reservations and abandoned runs: its own parent-liveness check and age backstop decide which to reclaim, and it rolls back any interrupted `reserve` or `claim`. It removes a reclaimed worktree only when its status is clean and `sweep.sh --judge` finds nothing in it that exists nowhere else, and retains the rest. The sweep reports recovery's result unchanged as `recovered`, passes its warnings through on stderr, and contains no second copy of its rules. It then lists the worktrees again and acts on what it classifies. It removes a worktree only when the worktree is marked, its owner is proven gone (`owner_alive: false`), it is clean, and no other reason refuses it. It prunes a vanished worktree's registration only when nothing refuses that either. Every entry gains `outcome` (`removed`, `pruned` or `declined`), `reasons`, `branch_outcome` and `branch_reasons`, and `counts` gains `removed`, `pruned` and `declined`. A declined entry lists every reason that applies:

- `main-worktree`: the main checkout is never removed.
- `inspection-errors`: the entry has errors, so its classification is unreliable. A directory or marker the sweep cannot inspect lists no reason it could only guess.
- `held`: a process holds it, either in the classifying look or in another `lsof` look taken just before its own removal.
- `locked`: `git worktree lock` protects it.
- `ledger-owned`: an open spawn-ledger row, or the pending worktree record (`<ledger>.pending`) of a `reserve` or `claim` interrupted before it finished, names it. `chain.sh complete`, `recover` or the next rollback owns it, as ADR-0007 assigns. Only `--remove` reads the pending record.
- `contains-worktree`: another registered worktree lies inside it, compared by filesystem identity rather than spelling, and removing it would delete that worktree's files too.
- `contains-repository`: the repository's own git directory lies inside it.
- `uncommitted-changes`: it is dirty, or, once its directory has vanished, its index still holds a staged change. This refuses removal whatever else is true, because that work exists nowhere else.
- `operation-in-progress`: git's record of it holds an unfinished rebase, merge (including its autostash), cherry-pick, revert, sequence, bisect or notes merge.
- `unreferenced-head`: it is detached at a commit no ref contains, so its commits may exist nowhere else.
- `contains-submodule`: it contains a checked-out submodule, which git refuses to remove; a submodule directory in it holds files, which `git status` never looks at; or git's record of it keeps a submodule's repository, which removal would delete.
- `worktree-refs`: git's record of it holds refs under `refs/worktree/`, `refs/bisect/` or `refs/rewritten/`, which exist only there.
- `unvouched`: it has no marker, so it is reported and never removed.
- `owner-alive` or `owner-liveness-unknown`: the marker's owner is alive, or its liveness could not be read.
- `not-prunable`: its directory vanished, but git does not report the registration as prunable.
- `marker-changed`: the marker's bytes changed after the worktree was judged, or a new marker appeared while git was removing it, so someone may have claimed it. A marker the sweep set aside is never restored over a new one.
- `head-moved` or `registration-changed`: its HEAD, its branch or its registration changed after it was judged.
- `reappeared`: a vanished directory exists again.
- `removal-failed`: git refused or failed the removal, and the error is in `errors`. When git refused because work appeared after the last check, the entry also says `uncommitted-changes`.
- `registration-lost`: git deleted the registration before failing, so the directory left behind is no longer a worktree any later sweep can see.

Just before each removal, the sweep reads the worktree list, its lock, the spawn ledger, the worktree's status and git's record of it again, and declines with whatever changed or now refuses it, including a worktree registered inside it since. It then sets the marker aside and runs `git worktree remove` without `--force`, under `status.showUntrackedFiles=all`, so git itself refuses work that appeared after that last check, whatever the repository configures. If the worktree stays on disk, its marker is restored byte for byte. Ignored files are deleted with the worktree, as they are when `chain.sh complete` removes one, and so is any unregistered repository nested inside an ignored directory. _Narrower than ADR-0007's "untracked files count as uncommitted", because nearly every worktree holds ignored build output or dependencies, and counting them would make every worktree unremovable._ A vanished worktree is `pruned` only when git's record of it, found through its `gitdir` file, holds nothing that exists nowhere else: no unfinished operation, no submodule repository, no per-worktree ref, no detached commit outside every ref and no staged change. Only that one registration is removed, never through `git worktree prune`, so no other worktree is touched, and its branch is left alone. _Contradicts ADR-0007's rule that a worktree with no marker is never removed on sight, but only for a registration whose directory is already gone and whose record holds nothing unique, because #54 asks for a vanished worktree to be reconciled._ A directory moved without `git worktree move` reads as vanished, so pruning it leaves the moved files no longer a worktree; run `git worktree repair` on a moved worktree before sweeping.

Branches are decided only after every removal is done, so a worktree that stays keeps its branch untouched and no GitHub lookup delays a removal. A detached worktree has no branch, and neither does one on a branch with no commits yet, such as an orphan's; their `branch_outcome` is null. Otherwise the branch is `deleted` only when no worktree has it checked out, is rebasing or bisecting it, or lists it for `rebase --update-refs`, as `git branch -D` would check, and `gh pr list --head <branch> --state merged`, run from the repository root, shows a merged pull request from this repository whose head commit is the branch's local tip. The deletion is `git update-ref -d` against that tip, so a branch that moved since is kept, and the branch's configuration is removed with it. A branch stays as `twin-not-removed` while another worktree on it was pruned or could not be removed in this sweep, because that worktree's entry reports the branch left alone; worktrees removed together share one decision. Merge status comes from GitHub and never from local ancestry, because a squash merge leaves a merged branch outside the default branch's ancestry. Any other branch is `kept` with one reason: `in-another-worktree`, `twin-not-removed`, `branch-check-failed` (the branch or a worktree that might use it could not be read, and the error is in `errors`), `not-merged`, `merged-at-another-commit`, `branch-moved`, `merge-status-unknown` (the lookup failed, and the error is in `errors`) or `deletion-failed`. A removal or branch failure is an error, so the sweep exits **1** after reporting it. Two kinds of work still escape every check: a commit only the worktree's HEAD reflog remembers, and an edit to a file marked `--assume-unchanged` or `--skip-worktree`, which `git status` does not report. Deleting a branch also discards its reflog, as `git branch -D` does.

`sweep.sh --judge PATH` prints, as a JSON list, what removing that one worktree would destroy that exists nowhere else: `contains-worktree`, `contains-repository`, `uncommitted-changes` and the reasons git's record of it gives (`operation-in-progress`, `contains-submodule`, `worktree-refs`, `unreferenced-head`, or a vanished worktree's staged change). An empty list means removal would destroy nothing, the main worktree is always `main-worktree`, and a path that does not exist and names no registration has nothing to judge. An existing directory is found by filesystem identity, so git's record may spell it differently, for example in another Unicode normalization; one that is not this repository's worktree, or that cannot be inspected, exits **1** rather than being judged harmless. `--judge` and `--remove` are mutually exclusive. It is how `chain.sh recover` shares the sweep's rule rather than keeping a second copy.

The offline CLI suite is `bash scripts/test-sweep.sh`, also run by `scripts/validate-skills.sh`. It uses temporary repositories, real holders and a stubbed `gh`, never the repository's own worktree registry or the network.

## The runtime it names

A recommendation also names the **runtime** to run it on, and `next` reads that runtime rather than sizing one. A skill's `SKILL.md` header sets the GitHub Copilot `model`, reasoning `effort`, and `context` window to choose in `/model` before running it. `next` reads the header of the skill it routes to with `scripts/runtime.py`, so a route to a skill whose header sets `gpt-6.1-sol`, `medium`, and `272K` comes back as:

```text
Runtime: model gpt-6.1-sol, effort medium, context 272K (default)
```

The tier in parentheses, `default` or `long_context`, is the one that window belongs to. Copilot CLI's `--context` flag and a subagent's context tier take the tier, not the window. `runtime.py` reads it from the model catalog `/model-scorecard` keeps in `references/skill-headers.json`: a window larger than the model's default one is `long_context`. Without that catalog, it falls back to `default`. A route that names no header, such as the built-in `/compact`, reads `Runtime: current session`.

`SKILL.md` is the authoritative source for a skill's `model`, `effort` and `context`. If those header settings are missing, incomplete, malformed or unreadable, `/next` resolves them from that skill's entry in `/model-scorecard`'s generated `references/skill-headers.json`. The resolver reports the selected source as `skill-header` or `model-scorecard`; if neither source has a complete valid runtime, it reads `Runtime: current session`.

There is no command to run. Pick the runtime in `/model` and paste the prompt into the session the recommendation names, or run [handoff](./handoff.md), which launches the prompt in the background on the same runtime.

## The chain it can spawn

The chain CLI requires Python 3.9 or newer, with no third-party Python dependencies.
`CHAIN_PYTHON` selects its interpreter (default: `python3`) for both the new Python entry and the
remaining bash-implemented commands. An older interpreter fails before changing chain state.
`chain.sh reenter` reads the `agentStop` payload on standard input: it requests a route, confirms it
only on a following `stop_hook_active` turn, and abandons an unconfirmed request after three attempts.
Its ledger lock uses the same UTC owner record and recovery guard as the other subcommands; after
about one second waiting for a live holder it returns `ledger-busy` without writing.

For an **AFK-safe** action, `next` may spawn exactly four routes. An ordinary `/next` invocation still returns exactly one recommendation. The chain is the separate
AFK-safe path: after the phase-boundary procedure selects a subagent, the spawn gate requires both an
AFK-safe target and one of its four allowlisted routes — `/implement`, `/code-review`, `/research`,
or `/push`. An in-progress merge, rebase, or cherry-pick conflict routes to `/implement`,
which resolves it and closes with `/code-review` on the new head. Planning declines a target the tracker confirms is
unresolvable, and reservation checks it again before writing the ledger row or creating the
worktree. A transient tracker failure is reported as tracker unavailability rather than as a
missing target. A bare number is first resolved to its canonical issue, a lookup bounded at 10
seconds; if it fails or a pull request does not close exactly one issue, `plan` declines with
`target-resolution-failed` and the cause, `reserve` refuses with both, and `complete` closes the row
as a transient `tracker-failed` rather than leaving it open. An older ledger row whose pull request
has no single closing issue keeps its own spelling and does not block unrelated targets; a row
whose number the tracker can no longer find still fails the lookup. A valid target
reserves a worktree and a concurrency slot in the spawn ledger
before starting the in-session subagent, then binds the run to that reservation.

The ledger records each reservation, binding, worktree, completion, and per-target chain depth so the
chain neither duplicates in-flight work nor exceeds ten concurrent runs. Numeric issue targets and
their `issue-N` spelling share one identity; a pull request number uses the issue it closes, including
when older ledger rows retain a previous spelling. A reservation also names the process identity of
its reserving parent — the routing session itself, never the shell that runs the command, which exits
with it: recovery reclaims an unbound orphan immediately when that
parent is gone, or after `CHAIN_RESERVATION_STALE_SECONDS` (300 seconds by default), marking it
`reclaimed` rather than as a completed run. An abandoned run is reclaimed only when the same
liveness check proves its reserving parent is gone; age alone never reclaims an in-flight run. A bound
row whose parent identity cannot be evaluated (a missing, null or non-positive `parent_pid`, or an
empty `parent_start`) predates that identity and is reclaimed once it is older than the stale threshold.
Reclaiming releases the row's slot and applies the same worktree rule as completion, below. Every
`plan` runs recovery before checking capacity, so
reclaimed slots immediately become available to the next candidate. It stops at a checkpoint
boundary rather than spawning when the route is HITL or not allowlisted, a route would take its
fourth repeat for a target, or a target would take its ninth hop. `subagentStop` closes the completed
ledger row; if its tracker lookup fails, the row closes as `tracker-failed` and records whether the
failure was transient or permanent. A transient rate limit, server error, network failure,
30-second tracker timeout, or malformed tracker response leaves the target retryable. Only a tracker
error saying the target is missing or invalid is permanent: it halts the target instead of being
mistaken for `no-evidence`. Completion and recovery remove a clean worktree and report any other as
a retained worktree (`GLOSSARY.md`). Recovery also retains a reclaimed worktree in which
`sweep.sh --judge` finds work that exists nowhere else, such as a commit no ref contains, and a
reservation whose directory has vanished loses only its own registration, never another worktree's.
_Contradicts ADR-0010's frozen interface: recovery's `retained_worktrees` can now name more
worktrees, recovery exits non-zero when a vanished reservation's own registration cannot be
removed, and other registrations are no longer pruned. Both stop chain.sh destroying work that
exists nowhere else, so the Python port (#114) carries them._
`agentStop` re-enters `/next` in the launching session for its batch of completed, unrouted runs,
allowing one fill to replace every slot that batch freed. Other sessions' stops, subagents' included,
stand aside (ADR-0009).
AFK-safe and allowlisted are the two eligibility conditions for consulting `chain.sh plan`, not a
guarantee of a spawn. The planner is authoritative and may decline an otherwise eligible action when
its target or worktree is already in flight, the target is halted or failed, or the concurrency limit
is reached. A completed run without an issue comment timestamped between its spawn and completion
halts its target with `no-evidence`; the
repetition and depth guards likewise decline a fourth repeat for one route and target or a ninth
lineage hop. Every decline remains at the checkpoint boundary for a human rather than launching a
subagent.

## It's working if

- You get back exactly one action, with a live target — a linked issue, PR, spec, branch, or the current conversation — and never a menu of possibilities.
- Fan-out never turns that into a menu either: the chain reaches its ten concurrent worktrees by asking for one recommendation at a time, and names which of the three limits stopped it — the ceiling of ten, no ready action left, or every remaining candidate waiting on a worktree another agent holds.
- Once the ten are running, the chain keeps itself full: each finished run frees its slot, and the batch of runs that finished since the last turn comes back as one re-entry that refills every one of them while ready work remains.
- A skill recommendation names the model, effort, and context window its routed skill's header sets.
  The Planner route instead names git-loopy planning Routing and its shell command.
- An AFK-safe recommendation for one of the four allowlisted routes arrives with its in-session
  subagent already running only when `chain.sh plan` returns `spawn`; on `decline`, it remains at
  the checkpoint boundary as a prompt.
- The recommendation names whether to continue in this context, start a fresh session, or run as a
  subagent, matching the flow's own rules: grill → spec stays in one context,
  the Planner starts fresh, and only fallback `/to-tickets` stays in the spec context.
  The chain starts only approved delivery work.
- For engineering work in a repo missing either its tracker configuration or
  `.github/hooks/git-loopy-chain.json`, it routes to
  [setup-git-loopy-skills](./setup-git-loopy-skills.md) and nothing else.
- When the work is genuinely finished, it says so instead of inventing a next step.

## Where it fits

`next` is the **router** — the standalone map that sits over the whole set. It points into every
flow and carries the bounded chain when its gate approves. From here you'll most often land on
[grill-with-docs](./grill-with-docs.md), the head of the main flow, or [triage](./triage.md), the
on-ramp for work you didn't create. The engineering flow's prerequisite is
[setup-git-loopy-skills](./setup-git-loopy-skills.md), because the tracker config and chain hook
that skill writes are the state `next` reads. When even the router's own picture is stale, its
[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/next) is the map of
record.
