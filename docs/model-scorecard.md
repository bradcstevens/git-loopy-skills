Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=model-scorecard
```

```text
/model-scorecard
```

[Skill source](../skills/model-scorecard/SKILL.md)

## What it does

`model-scorecard` rebuilds the generated
[scorecard](../skills/model-scorecard/references/scorecard.md) from the live
Artificial Analysis leaderboard, authenticated Copilot model listings, and local
run logs. It recommends a selectable model ID, reasoning effort, context size,
and 1-100 role-fit score for each of seven Copilot built-in subagents and seven
git-loopy task types. Common SDLC tasks map onto those roles.

It **reports recommendations**, not configuration changes. The output includes
ranked alternatives, current settings, per-role evidence, and coverage gaps so
the user can see what changed and what the recommendations do not establish.

## When to reach for it

Type `/model-scorecard` when you want a fresh, source-grounded comparison of the
models available to your account, or want to revisit role-fit recommendations
after the leaderboard, harness capabilities, or working sets have changed.
The skill is explicitly user-invoked.

Use [set-task-models](./set-task-models.md) when you want the deeper
multi-source calibration and application of enforced settings. Use
[sync-model-roster](./sync-model-roster.md) for the narrower repair of
SDK-pinned roster and Config drift, rather than general model ranking.

## Inputs and build

The skill first loads `jev-ultrafast` and completes its preparation: an absolute
`JEV_ULTRAFAST_HOME` that imports `jev_ultrafast.Agent` and working provider
credentials. It also resolves the git-loopy checkout, defaulting to
`~/code/github/bradcstevens/git-loopy` and asking for a path if absent. That
checkout's `git-loopy/python/.venv` supplies the Copilot SDK; its Run logs and
configuration feed the comparison.

The [build script](../skills/model-scorecard/scripts/build.sh) runs four stages
fail-fast. Jev opens the live leaderboard and verifies its embedded dataset
against visible rows. The SDK lists the models available through the installed
Copilot CLI for subagents and git-loopy's pinned CLI for task types. Local
Copilot sessions and git-loopy Runs supply each role's p95 working set. Finally,
the scorer ranks selectable model-and-effort combinations and rewrites the
scorecard. `--no-headless` lets the user watch Jev.

The [profiles](../skills/model-scorecard/profiles.json) are the tuning surface:
they define Intelligence Index bands, relevant benchmarks, working-set
estimates, role constraints, and the ranked fields that determine score weights.
The scorecard is generated output; retune the profiles and rebuild instead of
editing its recommendations by hand.

## Common questions

**Is the score a universal model-quality ranking?** No. It measures fit for a
particular role using its band, benchmarks, constraints, and weighted success,
speed, token appetite, consistency, and throughput fields. Different jobs can
therefore prefer different models.

**Where does the context recommendation come from?** Subagents retain the default
tier unless the p95 working set passes the harness's compaction trigger, then use
`long_context`. When local runs do not supply a working set, the report identifies
the profile estimate. git-loopy task rows currently use default-tier context;
they do not establish per-task context configuration support.

**What if a model or stage is missing?** Coverage gaps remain visible, including
selectable models absent from the current leaderboard. A failed Jev, browser,
SDK, or sign-in stage is reported as an error, not replaced with a success-shaped
scorecard. Completion requires at least five matched visible rows, no conflicts,
and `jev_status` equal to `done`.

**Does it commit the result or enforce the picks?** No. It reads and diffs the
regenerated scorecard, reports the changes, and leaves the user to commit it or
apply settings with [set-task-models](./set-task-models.md). That skill refreshes
evidence and checks runtime contracts; it is not a blind copy of this table.

## It's working if

- The build exits successfully with the required Jev verification.
- Every role has a model, effort, context, and score in the regenerated reference.
- The report shows the subagent and git-loopy tables and changes from the prior
  scorecard.
- `outside band`, `II estimated`, coverage gaps, and estimated working sets are
  explicitly reported rather than hidden.

## Where it fits

`model-scorecard` is a calibration aid alongside the engineering workflow, not a
build or publication step. It supplies a readable recommendation artifact;
[set-task-models](./set-task-models.md) owns the evidence-to-configuration
transition. Keeping those separate lets you inspect a ranking without changing
the agents that perform implementation, research, and review.
