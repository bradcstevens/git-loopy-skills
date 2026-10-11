---
name: upstream-sync
description: "Carry out one action of the upstream-sync control loop (plan a mattpocock/skills release, implement or fix a sync ticket's pull request, iterate on reviewer feedback, or move git-loopy's skill pin) when the agent-upstream-sync workflow hands over a Selected work block. Use the pinned upstream revision and references/sync-rules.md, never upstream main or memory of upstream."
---

# Upstream Sync

Use this skill when the `Agent: upstream sync` workflow, or a maintainer running its pieces by hand
(`docs/upstream-sync-loop.md`), hands you a **Selected work** block naming one action.

The goal is that git-loopy-skills carries every in-scope change up to the latest mattpocock/skills
release, with only the named overlays left as differences, and that git-loopy pins a proved
git-loopy-skills revision containing it.

## Core requirements

- The Selected work block is the whole assignment: one action, on one ticket, pull request or
  release, in one repository. Do not pick up other work, however related it looks.
- Upstream content comes from mattpocock/skills at the pinned revision the spec or Selected work
  names: `gh api "repos/mattpocock/skills/contents/<path>?ref=<sha>"`, or a clone checked out at that
  sha. Never upstream `main`, and never your memory of upstream.
- [`references/sync-rules.md`](references/sync-rules.md) is the only source for what a synced file
  keeps and what it takes from upstream. Apply it to every file you sync.
- Stay ticket-bounded. Change only what the ticket names. In git-loopy, change only the skill pin
  and the consumers git-loopy's `docs/skill-catalog-source.md` lists.
- Load the workflow skills through the skill tool: `implement`, `code-review`, `to-spec`,
  `to-tickets`. A built-in reviewer, or a sub-agent you prompt yourself, is not `/code-review`, and
  its verdict records nothing the merge gate can read.
- Stay on the branch you were given. Never `git checkout`, `git switch` or `git reset` away from it,
  and tell every review sub-agent the same: read other revisions with `git show` and `git diff`.
- Never force-push, push to a default branch, merge, or close a pull request. The workflow merges
  through `chain.sh gate`, and only on its evidence.
- Never answer an authority prompt (login, MFA, secret, consent). Stop and say what was missing.
- You run unattended. Do not ask anyone anything.

## Workflow

### 1. Read the selected work

Read the Selected work block and the Agent memory after it. For a ticket, read it and its parent
spec with `gh issue view <n> --repo <repo> --comments`, and state the ticket's title before you
start. For a pull request, read its body, comments and the ticket's review records.

Completion criterion: you can name the action, the repository, the ticket, pull request or
release, and the upstream pin.

### 2. Carry out the action

#### `implement` in git-loopy-skills

1. Call the skill tool with "implement" for the ticket. Apply `references/sync-rules.md` to every
   synced file, and verify each synced skill by diffing it against upstream at the pin: every
   remaining hunk must be a named overlay, and the evidence comment names each one.
2. Once the work is committed and pushed, open the pull request exactly as Selected work says
   (its body is `Closes #<ticket>`), before the review.
3. Call the skill tool with "code-review" for the pushed head against the default branch. It posts
   the findings, or the `review-clean: head=<sha>` record, on the ticket.
4. If the review found blocking defects, remediate them through "implement", push, and review the
   new head. Stop after two rounds and report what is left.

Completion criterion: the branch is pushed, the pull request is open, and the ticket carries a
review record for the pull request's current head.

#### `implement` in git-loopy (moving the skill pin)

Follow git-loopy's `docs/skill-catalog-source.md`, section *Refreshing the catalog*, and its
ADR-0064, in their order: publish, prove, pin last. Publishing is done: the publish revision in
Selected work is on git-loopy-skills' default branch, checked out detached beside your working tree.

1. **Prove.** Run
   `uv run --project git-loopy/python python -m git_loopy.skill_candidate <skills checkout>`
   against that checkout. Note every contract it reports broken.
2. **Adapt the runner.** Make the ticket's changes: both `PROMPT.md` copies, the Required Skills,
   the offline revision and Skill-name snapshot in `tests/test_prompt.py`, the README catalog table,
   and the *Upgrading existing policies* notes. Re-run the proof until it passes.
3. **Pin last.** Set `skill_source.json`'s revision to the publish revision. The commit message
   names that revision and the skill changes it carries.
4. Run the Python suite row of git-loopy's `AGENTS.md`.
5. Commit, push, open the pull request as Selected work says, then call the skill tool with
   "code-review". The record script lives in the skills checkout:
   `python3 <skills checkout>/scripts/review-clean-record.py emit <head>`.

Completion criterion: the proof passes against the publish revision, the pin names it, the suite
is green, and the ticket carries a review record for the pull request's head.

#### `fix`

The pull request lacks merge evidence; Selected work lists which.

- **`pull-request-mergeable`:** merge the default branch into the branch
  (`git fetch origin && git merge origin/<default>`) and resolve the conflicts. For `README.md`'s
  skill index, take either side and regenerate it with `node scripts/build-readme.mjs`; never
  hand-merge it.
- **`checks-green`:** read the failing log (`gh pr checks <n> --repo <repo>`, then
  `gh run view <run> --repo <repo> --log-failed`) and fix the cause, not the check.
- **`review-clean-evidence-comment`:** remediate the ticket's latest review findings. If no review
  exists for the current head, review it.

Then validate, push, and call the skill tool with "code-review" for the new head. A resolved or
remediated head is a new review, never a reused one.

Completion criterion: the branch is pushed, and the ticket carries a review record for the new head.

#### `iterate`

The maintainer's feedback in the Iteration context is the instruction. Update the pull request
branch. Distill guidance that should change future runs into `.github/agent-memory/upstream-sync.md`:
on this branch for a git-loopy-skills pull request; for a git-loopy pull request, quote the memory
entry in your reply instead. Then validate, push, and review the new head with "code-review".

Completion criterion: the feedback is addressed on the branch, and your reply says whether memory
changed.

#### `plan` (a new upstream release)

1. Read the release notes (`gh release view <tag> --repo mattpocock/skills`) and, for every
   in-scope row of Selected work's table, upstream's diff between the base and the release.
2. Call the skill tool with "to-spec" to publish a spec titled
   `Spec: Sync git-loopy-skills with mattpocock/skills <release>`. It states each change, what each
   counterpart here takes and keeps under `references/sync-rules.md`, the retirements and
   additions, and the impact on git-loopy. It pins the release's sha as **Upstream pin**, carries
   the label `upstream-sync`, and ends with the loop's marker:
   `<!-- upstream-sync:spec target=<sha> release=<tag> -->`.
3. Call the skill tool with "to-tickets" to slice the spec into tickets: native sub-issues with
   blocking edges, `ready-for-agent`, exactly one `task-type:` label, a `parallel-safe` decision,
   and the `## What to build` and `## Acceptance criteria` headings.
4. File the follow-up in git-loopy: one issue labelled `upstream-sync` and `needs-triage`, naming
   what the sync retires, renames or adds that git-loopy's runner prompt, Required Skills, README
   catalog or label vocabulary reads.

Out-of-scope rows (`misc/`, the rest of `in-progress/`) get one line each under the spec's
*Out of Scope*, never a ticket.

Completion criterion: an open spec carries the marker, and its tickets exist as sub-issues.

#### `downstream-plan` (git-loopy)

The last sync is complete in git-loopy-skills, but git-loopy's pin predates it. Run the
`skill_candidate` proof against the skills checkout to see which contracts the publish revision
breaks, and read the source issues. Then call the skill tool with "to-tickets" in git-loopy to
publish exactly one AFK-ready ticket for the pin move, labelled `upstream-sync`, `ready-for-agent`
and one `task-type:`, as a sub-issue of the source issue. Its acceptance criteria follow ADR-0064's
order and name every consumer to reconcile.

Completion criterion: git-loopy has one open, AFK-ready `upstream-sync` ticket for the pin move.

### 3. Validate

- git-loopy-skills: `scripts/validate-skills.sh` and `node scripts/build-readme.mjs --check`.
- git-loopy: the Python suite row of its `AGENTS.md`, and the `skill_candidate` proof.

A red loop is not a candidate. Fix it, or stop and name the blocker.

Completion criterion: every command above that covers your change passed, or your answer names the
exact blocker.

### 4. Answer

Format your final message by [`references/response-template.md`](references/response-template.md).
It becomes the pull request body, the pull request comment, or the run summary.

Completion criterion: the answer follows the template for your action.

## Review checklist

- The work stayed inside the Selected work block and the ticket's scope.
- Upstream content came from the pinned revision.
- Every remaining difference from upstream is a named overlay in `references/sync-rules.md`.
- `/code-review` ran through the skill tool and recorded on the ticket for the final head.
- Validation passed, or the blocker is named.
- Nothing was force-pushed, merged or closed by the agent.
