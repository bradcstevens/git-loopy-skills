# Two hook events carry the chain: `subagentStop` closes, `agentStop` re-enters

The chain needs two different things to happen when a spawned run finishes: its ledger row must be
closed, and the parent session must run `/next` again. These are separate jobs on separate
subjects, and no single event does both.

`subagentStop` fires when the spawned run ends and carries its identity and response, so it closes
the row. But blocking it only makes **that subagent** take another turn — it cannot wake the parent,
and the parent is where `/next` runs. `agentStop` fires when the parent finishes a turn and is the
only event that can force the parent to continue, so it carries re-entry: when the ledger holds a
completed run that has not yet been routed, the hook returns a block decision and the parent takes
another turn to run `/next`.

This supersedes the mechanism originally stated in
[ADR-0001](./0001-in-session-subagents-for-the-next-loop.md), which claimed `subagentStop` blocking
was what re-entered `/next`. That ADR's decision — in-session subagents over detached processes —
still stands and was re-examined before this was written. Only its stated mechanism was wrong.

## Verified before adoption

Written after a spike (#22) fired the event rather than before, because the error this corrects came
from trusting documented behaviour that nobody had exercised:

- Returning a block decision from a repo-scoped `agentStop` hook does stop the parent exiting; it
  takes another turn with the hook's reason injected as context.
- The payload carries `sessionId`, `timestamp`, `cwd`, `transcriptPath`, `stopReason`, and
  `stop_hook_active`. This is what one spike saw, not a guarantee — see
  [ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md) for why the hooks
  validate only the fields they read.
- `stop_hook_active` is present — `false` on a natural stop, `true` on a turn that a block forced.
  It is the loop-breaker, and the chain must consult it rather than blocking unconditionally.
- The runtime permits **8 consecutive blocks** before it stops re-prompting and exits cleanly. The
  chain's own guards must therefore halt well inside that ceiling, or the runtime will halt it
  first and the reason will be invisible.

## Consequences

- **Two hooks, not one.** `subagentStop` and `agentStop` are separate files with separate jobs, and
  neither should be asked to do the other's work.
- **`agentStop` fires on every parent turn**, including turns with nothing to do with the chain, so
  it must read the ledger and block only when a completed run is genuinely unrouted. Anything else
  would hold the session open for unrelated work.
- **The payload identifies no subagent.** `agentStop` carries no `agentId`, because the parent is
  what stopped. Correlation therefore lives entirely in the ledger, which is why a run must be
  reserved and bound rather than reconstructed from the event.
- **Blocking is bounded twice over.** The runtime's ceiling of 8 is the outer limit; the chain's
  repetition and depth guards are the inner one and should trip first so the halt is explained.

## Considered options

**Keep everything on `subagentStop` and make `complete` emit the block shape.** Rejected because it
prolongs the subagent rather than re-entering `/next`, which is the wrong subject entirely.

**Drop the hard guarantee and rely on the parent's completion notification prompting the model.**
Rejected because it fails the requirement that the next `/next` runs whether or not the model
remembers — the whole reason a hook was chosen over an instruction.
