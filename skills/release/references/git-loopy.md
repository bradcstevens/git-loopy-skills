# The git-loopy Release-line branch

Use this branch only for a target that declares git-loopy's Release-line policy.
Running git-loopy in another project does not give that project this policy.

## Read the authority in the target checkout

Read `docs/releases/README.md` and the release ADRs it links, then inspect the
version writer and Promotion/publication workflows they name. Those files own the
current commands, distribution promise and gates; this reference is not a cached
command line. If this policy has changed, follow the current authority or ask
about a conflict.

## Match the selected version to a release path

Under this convention, completed issues already ratchet one Release target by
**Bump class**, and `dev.N` counts advances. Apply the version selection in
step 3 of the skill before choosing Promotion. The automated target is evidence
of the project's release line, not an override of the selected version.

When the selected version matches that target, use its stable **Promotion**,
including all unreleased completed issues since the previous stable release.
Development fragments remain part of that batch; reuse the target without
another bump. When the selected version belongs to an older stable line, locate
the documented maintenance branch, integrated patch batch and publication path.
If that path is absent, ask for a maintenance-release decision before writes.
Relabeling the development tree would not establish a patch release.

A `vX.Y.Z` milestone is a Promotion trigger, not a version selector. List the
repository's existing milestones, including closed ones, with pagination. Verify
that the target's matching milestone exists and is the documented trigger before
closing it. Invocation authorizes that closure when its release conditions hold.
An absent milestone is a blocker: ask for the maintainer's intended trigger rather
than manufacturing a milestone, choosing a nearby version or relabeling issues.

A major Bump class may already have produced a stable candidate without a
milestone. Reconcile its existing Promotion run, tag and Release first. A closed
milestone with failed publication calls for the documented retry, not reopening
and reclosing it or starting a second version.

**Done:** the selected version has a supported release path and its exact trigger
covers the batch. Check whether the workflow sweeps other untagged stable
candidates too; resolve that scope before triggering it.

## Keep proof ahead of publication

Use the project's native version writer and composed Promotion path. The final
stable tree, its notes and synchronized version fixtures must be what the release
gates prove. Honor every prerequisite the current policy requires, including
rehearsal and real-host smoke where prescribed; missing implementation of a
required gate is a blocker, not an exemption.

Check that the trigger has the required publication authority. In this project,
tags pushed with the default workflow token do not start the downstream tag
workflow; the configured publication credential is therefore part of the release
path, not something to discover after making a stable commit.

Read the explicit distribution policy: **source-only** promises source archives
and notes; **artifact-bearing** also owes its declared builds, trust evidence and
channels. Missing artifacts or credentials never silently change the promise.

Watch both Promotion and downstream publication, and read back the release at the
proved tag. A library-only publisher or rehearsal utility is not an alternative
entry point unless the repository documents it as one.
