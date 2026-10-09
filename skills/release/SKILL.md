---
name: release
description: Release completed work at the next patch version, or the version you specify.
disable-model-invocation: true
---

# Release the Completed Batch

Invocation authorizes one release of the target project's completed work, including
its prescribed release preparation and publication. One completed issue makes a
one-issue **batch**; several make one combined release. This is a release operation,
not permission to finish issues, merge pending work, or change release policy.

## 1. Bind the project and its release contract

Use the repository where git-loopy did the work: the invocation's Git checkout,
unless the user names another checkout or GitHub repository. Resolve its root,
remotes and GitHub `owner/repo`; cross-check them against the Run's repository
identity. Worktree Runs belong to their shared repository. The skills installation
directory and git-loopy's own source repository are not implicit destinations.
Ask if the evidence identifies several repositories or disagrees.

Read the target's `AGENTS.md`, pointed-at release docs, version/changelog
configuration, release workflows and recent release history. Establish the release
branch, channel, version authority, tag format, publication trigger and required
gates/artifacts. Use `gh` with the explicit repository on every GitHub operation.
Inspect the actual scripts and workflow triggers rather than inventing commands.
Capture any version supplied in the invocation as the requested version; otherwise
use the automatic selection in step 3.

**Release-line policy:** when the target uses git-loopy's Bump class / `dev.N` /
Promotion convention, read [the Promotion branch](references/git-loopy.md) now.

**Done:** one repository and one documented release path are identified. Missing or
conflicting policy, including a first release with no version convention, needs a
user decision before writes.

## 2. Freeze the batch

Fetch the selected remote branch and tags without replacing existing tags. Pin the
remote source commit and the preceding published release for this branch, channel
and release line. Resolve tags to commits and verify ancestry; the most recently
created Release object is not necessarily this branch's predecessor. A stable
release's boundary is its previous stable release, not an intervening prerelease.
For an established first-release policy, the boundary is the start of the line.

Inventory **all** unreleased git-loopy completions through that source commit,
across Runs, using Run/Integration records, linked PRs or commits, GitHub completion
events, and existing release notes. Follow pagination to exhaustion. Closure time
alone proves neither integration nor release coverage; an arbitrary commit message
mention is not a closing relationship.

Build an evidence table: issue URL, completion evidence, landed commit/PR, and
whether a published release already contains that work. Require completed rather
than duplicate/not-planned closures, and prove each landed change is reachable from
the candidate branch. Reopened, reverted or already-released work is excluded with
its reason; a newly completed follow-up on a reopened issue needs fresh evidence.
Use the landed range and notes together, not issue numbers alone.

**Done:** every discovered completion is accounted for and the unreleased batch is
fixed. An empty batch is a no-op: return the existing release if it already covers
the work. Unreadable history, uncertain coverage or completed-but-unintegrated work
is a named blocker, not permission to silently release a smaller batch.

## 3. Resolve one version and prepare its notes

**Patch by default.** For a non-empty batch, automatically select the next smallest
stable version after the latest published stable release on the selected line.
For SemVer, increment only the patch component: `v0.10.0` becomes `v0.10.1`;
`v1.2.9` becomes `v1.2.10`. Preserve the project's tag prefix. A development
target such as `v0.11.0-dev.5` neither changes that baseline nor requests
Promotion. Select once for the whole batch, without asking the user to choose
the default version.

**Explicit version.** When the invocation supplies an exact version, select that
version instead, including its prerelease suffix if present. An ambiguous request
such as "a minor release" needs clarification. For a non-SemVer project, use its
documented smallest increment; a first release needs its documented initial
version or a user-supplied one.

**Compatibility.** Check the selected version against the batch's bump evidence
and the project's release path. Reuse an already-prepared matching candidate.
If the batch requires a larger bump, an automated target differs, or a patch
requires an unavailable maintenance/backport path, report the mismatch and ask
for a version or release-policy decision before writes. Keep the selected version
visible rather than silently substituting a larger target or shrinking the batch.
An explicit version selects an identity, not an exemption from release gates.
Reconcile an existing tag, Release or in-flight publication before preparing
anything; a retry resumes the same candidate rather than allocating another patch.

Read the full landed change range. Write the project's release notes with every
batch issue linked, its user-visible changes, and any required migration warnings.
Include other changes that the chosen commit also ships; a batch is an accounting
boundary, not a claim that unrelated commits disappear from the artifact.
Preserve authored notes and use the native version writer for synchronized copies.

**Done:** one version/tag and one set of notes cover every batch issue, with the
derivation traceable to the default increment or explicit request and compatible
with project policy. The planned trigger publishes that one release; a trigger
that would also publish other pending versions needs a bounded
project-supported path before proceeding.

## 4. Prove the candidate

Preserve the caller's edits and active Runs. Prepare any required release-only
changes in an isolated worktree from the pinned source commit; stage explicit
paths, follow commit conventions and leave unrelated work untouched. Honor release
PRs and approval gates rather than pushing around them.

Run the project's required release gates on the **final candidate**, including
version/notes consistency, artifact identity, signing and rehearsal where required.
Keep the host's package-feed configuration when isolating validation. Where the
release workflow creates the candidate itself, its candidate-bound gates must
succeed before publication; an earlier green development commit is not proof.

Immediately before remote mutation, re-read the release branch, planned tag,
Release object and relevant workflow runs. If the source advanced, re-plan and
re-prove rather than silently including new issues. Reconcile an existing matching
release or in-flight publication instead of starting a duplicate.

**Done:** the candidate, batch and gates agree, and the authorized publication path
still refers to that candidate. Missing credentials, protected-branch authority,
required approval or failed gates are blockers, not bypass opportunities.

## 5. Publish, reconcile and report

Use the project's existing release trigger and observe the exact workflow run
through publication. Dispatch acceptance, a pushed tag and a draft are not a
published release. If the project documents direct publication instead, publish
the proved commit through its normal branch/tag process, then use
`gh release create <tag> --repo <owner/repo> --verify-tag` with the authored notes and
the project's title, channel and latest-release settings. The tag must already
resolve remotely to the proved commit; let no convenience command create it at a
moving default-branch head.

On a retry or lost response, read back the remote before writing again. Reuse a
matching tag and finish only the missing publication step through the supported
path. A public tag stays immutable; a conflicting commit, version, channel, notes
or artifact set is a refusal requiring a new version or human resolution, never
a force-push or an overwritten Release.

**Done:** the non-draft GitHub Release exists in the bound repository; its tag
resolves to the proved candidate; its notes account for the complete batch; and
every promised artifact/channel step succeeded. Record release evidence on the
issues if the project requires it. Report version, URL and included issues.
If publication is partial, report the actual remote state, failed gate and safe
resume point instead of claiming completion.
