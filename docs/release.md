# Release completed work

Install into your agent:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=release -g -a github-copilot
```

For local development, pass the path to this skills checkout instead of its
GitHub name. Then open the repository where git-loopy completed the work and type:

```text
/release
```

To select an exact version instead:

```text
/release v0.10.2
```

[Skill source](../skills/release/SKILL.md)

## What it releases

One invocation publishes one GitHub release containing all completed, integrated
git-loopy issues that are not yet released on the project's selected release
line. One issue is a one-issue batch; several completed issues, even across
multiple Runs, share a release. Invoking it again with nothing new is a no-op.

The skill verifies completion against landed commits, PRs and release history.
Closing an issue alone is insufficient. Reopened, reverted, duplicate,
not-planned and already-released work is accounted for rather than blindly
included. Uncertain or unintegrated completions block publication instead of
silently shrinking the batch.

## Version selection

`/release` automatically selects the next stable patch version for the whole
batch: after `v0.10.0`, the default is `v0.10.1`, even if development has reached
`v0.11.0-dev.5`. An exact version in the invocation overrides that default.
The [version-selection rules](../skills/release/SKILL.md#3-resolve-one-version-and-prepare-its-notes)
also cover first releases, non-SemVer projects and publication retries.

Selection does not waive the **target project's** release contract. If its bump
rules require a larger version or its release path cannot publish the selected
patch, the skill asks for a decision rather than silently promoting a development
target. A patch on an older line needs a supported maintenance path and an
integrated patch batch.

For git-loopy's own repository, the
[Release-line branch](../skills/release/references/git-loopy.md) uses Promotion
only when the selected version matches the existing target. It neither invents
a milestone nor relabels the development tree to manufacture a patch.

## Where it fits

Use it **after integration**, when you want completed work released. `/push`
publishes a branch and may open a PR; `/release` publishes the integrated result
through the project's release gates. It is explicitly user-invoked, not a new
automatic `/next` chain route.

Invocation authorizes the release procedure, including its prescribed notes,
version preparation and publication. It preserves unrelated edits, honors
approval and artifact requirements, and waits for a published, non-draft Release
rather than treating a workflow dispatch as success. Public tags stay immutable;
a partial failure is reconciled before retrying.

Installing the slash command in your agent is separate from git-loopy's pinned
Run catalog. Adding this skill here neither updates that pin nor makes release
publication a Required Skill inside a Run.
