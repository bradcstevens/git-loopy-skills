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

## Whose version convention

The **target project's**: its release docs, version tooling, bump rules, tag
format and release channel. `/release` combines the batch once; it preserves an
already-advanced version target and refuses to invent missing policy.

For git-loopy's own repository, the
[Release-line branch](../skills/release/references/git-loopy.md) promotes the
existing target through the existing Promotion workflow. It does not add another
bump for each issue or invent a release milestone. An ordinary project that
git-loopy worked in retains its own convention.

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
