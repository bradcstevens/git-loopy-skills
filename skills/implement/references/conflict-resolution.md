# Conflict resolution

1. **Inspect the operation.** Check git status, history, and conflicting files.
   For a moved remote head, fetch and identify both sides of the divergence
   before reconciling the named branch; preserve unpublished work.
2. **Read the primary sources.** Read each side's commit messages, PRs, and
   originating tickets until the intent behind every conflict is understood.
3. **Resolve every hunk.** Preserve both intents where possible. Where they
   conflict, follow the stated merge goal and name the trade-off. Introduce no
   new behavior. Resolve the operation; never use `--abort` to escape it.
   Regenerate generated files on the reconciled tree instead of hand-merging them.
4. **Run the project's checks.** Discover the repository's automated checks and
   run the ones covering the resolution, fixing anything the reconciliation broke.
5. **Finish the operation.** Stage the resolution and commit a merge, or continue
   the rebase or cherry-pick until all commits are applied. Preserve unrelated
   edits. This step ends with no operation in progress and a committed head.
6. **Publish and record.** Push the checked resolution with a normal push, then
   post one short comment on the ticket naming the head SHA, both sides of the
   reconciliation, and any trade-offs. Record only the finished, checked,
   committed, pushed result, never an intended resolution.

A protected branch, a force push, or missing credentials require human authority.
Stop and name the missing authority rather than answering a prompt unattended or
aborting around it.

Return to `/implement` for its closing `/code-review` on this resolved head.
Pre-conflict review evidence does not cover the resolution.
