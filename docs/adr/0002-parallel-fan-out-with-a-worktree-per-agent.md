# The `/next` loop fans out in parallel, one worktree per agent

The loop may hold up to ten subagents in flight at once rather than running one at a time. Serial
execution would have been far less machinery, but it cannot build eight unblocked tickets
concurrently, which is the case fan-out exists to serve. The ceiling is ten because unbounded
spawning against a large ticket graph would consume credits faster than any guard could react.

## Consequences

- **Worktrees stop being advisory.** Ten agents cannot share one working directory. Every spawn past
  the first lands in its own `git worktree`, created before the spawn and removed after it when
  clean; a worktree that is not clean is retained and reported
  ([ADR-0007](./0007-a-worktree-is-removed-only-when-something-vouches-for-it.md)). The spawn
  ledger's `worktree` field is the lock that prevents two agents from being routed at the same
  directory. This is the largest piece of new machinery in the design and the most likely to break.
- **`/next` keeps its one-action contract.** `docs/next.md` promises exactly one recommendation and
  never a menu. Fan-out is achieved by the script asking repeatedly — one spawn per pass until the
  ceiling is reached, no ready action remains, or every remaining candidate collides on a held
  worktree. The router was not changed to return a list.
- **Chain depth is counted per target.** With one straight line, depth was hops since a human last
  spoke. Across ten branches that number is meaningless, so depth travels with a `(route, target)`
  lineage instead. A ticket that keeps bouncing between review and implementation halts on its own
  without nine unrelated agents inflating its count.
- **Guards halt one target, not the loop.** A stuck ticket should not stop the other nine.
- **Pending worktrees survive interruptions.** Whoever next takes the ledger lock finishes a
  pending worktree transaction or undoes it. A reservation finishes when its row reaches the ledger;
  a claimed worktree, which has no row, finishes when its marker lands.
