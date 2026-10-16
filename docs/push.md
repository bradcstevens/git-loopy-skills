Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=push
```

```text
/push
```

[Skill source](../skills/push/SKILL.md)

## What it does

`push` publishes the work in scope from the current conversation: it checks the
publication state and validation, stages the intended paths, commits, pushes the
branch, and resolves the pull request. Invocation is approval to persist that
work, not permission to sweep unrelated edits into the commit.

It inspects staged and unstaged changes, the branch and upstream, remotes, the
remote default branch, and existing unpublished commits before acting. Successful
validation from this session can be reused if it still covers the exact diff;
otherwise the skill runs the smallest existing checks covering the change.
Repository-specific documentation checks still apply to documentation-only work.

## When to reach for it

Type `/push` when the current work is ready to publish. The skill is also
model-invocable, so a workflow can reach it without you: `/code-review` ends by
running it on a clean head. Either way, invocation is the approval to publish the
work in scope from the current conversation, never unrelated worktree changes.
Include any preferred commit message, remote, base branch, or PR instructions in
the request.

Use [implement](./implement.md) first for an active
merge, rebase, or cherry-pick conflict. A detached HEAD needs a user-selected
branch before publication.

## Publication, not integration

The skill stages explicit in-scope paths and inspects the resulting index. It
creates a commit only when there is a staged change; with an empty index, it can
still publish existing unpublished commits. With neither, it reports that there
is nothing to publish.

Pushing uses a normal fast-forward push, setting an upstream when necessary.
For a GitHub non-default branch, `push` finds an existing open PR or creates one
against the remote default branch. On both create and update it calls the Skill
tool with [pr](./pr.md) to write the body: Summary, Evidence, and Merge Danger.
`pr` runs inside `push` as a format reference, not a separate publication route.
A default-branch push or non-GitHub remote makes a PR inapplicable.

The body covers the full branch diff against the PR's base, not just the latest
commit. Summary retains a separate `Closes #<n>` for every issue the branch
resolves; merely mentioned or partially addressed issues are not marked closed.
Evidence includes the exact validation commands and outcomes for the published
head, plus concrete before-and-after evidence. Missing before evidence is stated,
never invented. Updates preserve relevant human-authored context and
repository-required information, and `push` reads the saved body back to verify
the closing references and validation results.

For ticketed non-default-branch work, it records the durable candidate SHA and
PR on the ticket only after publication succeeds, saying that the exact head is
ready for a human to review and merge. It does not merge unattended. A later
branch update requires fresh publication and a fresh evidence comment.

## Common questions

**Will it include all my local changes?** No. Only the intended work is staged;
unrelated changes remain untouched and are identified in the final report.
`git add -A` is appropriate only when every dirty path belongs to this work.

**What if the push is rejected?** The skill fetches and reports divergence while
preserving history, then routes reconciliation to
[implement](./implement.md), naming the branch and both heads. The resolved head
gets a fresh code review before returning to publication. It does not force-push
without separate, explicit approval.

**What if it needs a login or permission?** A protected branch, missing scope,
expired login, MFA challenge, missing secret, or consent prompt is an authority
boundary. The skill stops and records the missing authority on the ticket rather
than answering the prompt unattended.

**Does this make a release?** No. Publishing a branch and PR is different from
[release](./release.md), which publishes completed, integrated work through the
project's release gates. A default-branch publication is already integrated and
has no PR merge boundary to record.

## It's working if

- Current validation covers the exact work being published.
- The commit contains all and only the intended change.
- The remote branch resolves to the local candidate HEAD.
- An applicable PR exists, and the report names its URL, the commit SHA and
  subject, the remote branch, and any unrelated changes left behind.
- Ticket evidence names the published head, not an intention to publish it.

## Where it fits

`push` is the publication transition after implementation and review. It makes a
candidate durable and puts a non-default-branch result in front of a human; it is
not a substitute for [code-review](./code-review.md) or a merge decision.
At the conclusion of the session it runs [next](./next.md) to route from that
durable result.
