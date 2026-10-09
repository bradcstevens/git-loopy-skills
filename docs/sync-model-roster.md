# Sync model roster

Use `/sync-model-roster` when the SDK-pinned Copilot model roster and one
git-loopy Config scope have drifted. It repairs the committed roster and its
Python restatements from authenticated harness evidence before changing
`config.toml`, so configuration never gets ahead of the capabilities it relies
on.

## When to reach for it

Use it when any of these are true:

- a model is missing from `git-loopy/conformance/model-roster.json`
- a model is selectable in Copilot but not present in the repo's recorded roster
- the user's `config.toml` still points to stale model, effort, or context values
- the user wants to align the repo and their active git-loopy config with the current Copilot account

## What it does

The skill:

- resolves one source checkout and one project or global Config scope
- captures `models.list()` from the CLI pinned by git-loopy's SDK
- updates `model-roster.json`, the Python capability maps, the CLI stamp, and
  provenance in lockstep
- preserves documented compatibility rows that the current account does not list
- validates the repaired roster before applying scoped Config changes
- reads the persisted and effective values back

## Guardrails

- use the SDK-pinned harness, not a PATH CLI or public catalogue
- keep fixture schema and Wrapper-contract versions unchanged unless their own
  shapes or contracts change
- preserve compatibility rows unless the user explicitly changes that policy
- never silently rewrite a different checkout or Config scope
- keep unrelated Config and source edits untouched
- stop when the pinned environment or authenticated listing cannot be verified

## Typical flow

1. Identify the git-loopy source checkout and exact Config scope.
2. Capture the pinned harness's authenticated model capabilities.
3. Classify observed, compatibility, changed, added, and removed rows.
4. Update and validate the roster's JSON, Python, stamp, and provenance.
5. Apply the requested defaults or task routes to the one Config scope.
6. Read back both the persisted file and effective merged values.

This is the narrow repair loop for roster drift, not a general model-research skill; `model-fit` remains the deeper research-and-routing calibration path.
