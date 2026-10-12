Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=set-task-models
```

```text
/set-task-models
```

To calibrate without changing configuration:

```text
/set-task-models research-only
```

[Skill source](../skills/set-task-models/SKILL.md)

## What it does

`set-task-models` inventories the signed-in account's actual Copilot capabilities,
refreshes model evidence, and creates one shared decision map for Copilot built-in
subagents and git-loopy task types. An ordinary invocation authorizes applying
that map to user settings, global routing, and actual git-loopy source defaults.
`research-only` saves and reports the decisions without touching those targets.

It sets `modelPolicy: "required"` for every discovered Copilot built-in, so a
subagent cannot substitute another model. It leaves custom agents, unrelated
settings, the main Copilot model, running processes, commits, and publication
alone. Installing the skill is not authorization to run it.

## When to reach for it

Invoke it explicitly when you want to recalibrate and enforce role-specific
model, effort, and context choices across both systems. Reach for
[model-scorecard](./model-scorecard.md) instead for a generated recommendation
report, or [sync-model-roster](./sync-model-roster.md) for scoped roster repair.

The default targets are `~/.copilot/settings.json`, respecting `COPILOT_HOME`;
`~/.config/git-loopy/config.toml`, respecting the configured config home; and the
git-loopy source checkout at `~/code/github/bradcstevens/git-loopy`. The skill
resolves real schemas, effective configuration, instructions, and existing edits
before ranking. A missing checkout or unverified account entitlement requires
input, not a guessed replacement.

## Evidence before settings

The skill attempts all five surfaces in its
[evidence plan](../skills/set-task-models/EVIDENCE.md): Artificial Analysis, its
Hugging Face wrapper, Arena, BenchLM, and LLM Stats. It records source dates,
harness and effort differences, uncertainty, conflicts, and blocked or partial
coverage. A mirror of the same evaluation is not independent corroboration;
at least two distinct usable evaluation lineages must inform the comparison.

The private, dated run directory under `~/.config/git-loopy/set-task-models/`
(or the configured equivalent) has mode `0700` and holds inventory, evidence,
`decision.json`, findings, and before/after records outside the source tree.
Every selectable candidate has evidence or an explicit gap. The manifest guard
checks the decision structure, supported settings, freshness, and shared-role
bindings; it cannot prove the research is true or the settings work at runtime.

Equivalent roles reference one profile: Copilot `general-purpose` and git-loopy
`implementation`; Copilot `code-review` and git-loopy `review`. The shared
profile must satisfy the stricter member's runtime and safety constraints.
Running tests as a bounded `task` agent is not the same job as authoring tests
under git-loopy's `test` role.

## Common questions

**Can it pick a model from a provider catalogue?** Not without current Copilot
entitlement evidence. Exact selectable IDs from an authenticated interface or
current picker capture are the allowlist. Provider availability, help output,
source rosters, and unverified aliases are insufficient; `auto` is a router,
not a fixed-model choice.

**What if git-loopy cannot express the selected context?** The
[application contract](../skills/set-task-models/APPLY.md) requires tracing the
actual reader and session creation/resume path. The skill stops before writing
targets when a requested context cannot be represented or equality cannot be
proved. It asks before adding a complete runtime feature; it does not invent
TOML keys or quietly substitute a run-wide tier.

**Will it replace my settings or local calibration?** No. It preflights every
target, backs up intended files, preserves unrelated edits and file semantics,
and stops on conflicting concurrent changes. Public benchmark research does
not overwrite measured routing or become "measured" local calibration.

**What does required enforcement guarantee?** It prevents model substitution,
not permission escalation or an assurance that all effort/context overrides are
impossible. A fixed rubber-duck pick also stops adapting automatically when the
parent model changes; that trade-off is reported.

**Does editing source defaults update my installed binary?** Not necessarily.
The skill reports a different installed checkout or artifact; updating or
installing it needs explicit authorization.

## It's working if

- Every in-scope role resolves to a supported, evidenced profile and the manifest
  guard passes; equivalent roles share the same profile.
- Proposed changes, citations, confidence, and limitations are reported.
- In apply mode, all authorized targets read back through their real readers and
  runtime paths as intended, with required model enforcement on built-ins.
- Relevant checks pass and a second projection comparison is a no-op.
- In research-only mode, no target changes; any blocked or partially applied
  state is reported plainly rather than called complete.

## Where it fits

This is a configuration calibration transition, not part of shipping a feature.
It can use prior [model-scorecard](./model-scorecard.md) findings as leads, but
refreshes perishable evidence before applying anything. The resulting shared map
keeps equivalent implementation and review jobs aligned across Copilot and
git-loopy without publishing private settings or restarting active work.
