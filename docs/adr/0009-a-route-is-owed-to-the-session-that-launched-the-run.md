# A route is owed to the session that launched the run

`agentStop` fires on every session's stop in the repository, not only on the routing session's.
That includes each spawned subagent (whose own `agentStop` names its own id as `sessionId`, with
no `agentId`), each parallel routing session, and any unrelated session in the same checkout. The
helper read the shared ledger and blocked whenever **any** completed run was unrouted, so every one
of those stops was told to run `/next` for runs it had not launched and could not fill:

- a subagent, whose prompt forbids `/next`, was held open for its parent's work;
- a parallel routing session was pulled into another session's fill;
- every foreign block spent one of the owner's three route attempts, so the owner's rows reached
  `route-abandoned` before the owner's own turn arrived;
- a foreign stop that blocked was recorded in `route_requested_by`, so that session's forced turn
  could then confirm the row as `routed` even though the owner never ran `/next` for it.

The last case was observed: one routing session's forced turn confirmed another session's row.

## Decision

A row's `session_id` is the routing session that reserved and bound the run. It is the same
session `subagentStop` reports the run under, which is why `/next` binds with that session's own id
rather than the agent's. Only that session's `agentStop` may do any of these for the row:

- block for it;
- record a request on it;
- confirm it on a forced turn.

Every other stop stands aside under `owed-to-another-session` and leaves the ledger byte-for-byte
unchanged.

[ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md) keeps `sessionId`
optional, and an older row may have no `session_id`. When either is missing, ownership cannot be
told apart, so the row stays routable and confirmable by any session, as it was under
[ADR-0008](./0008-a-route-is-confirmed-not-assumed.md). A possibly misdirected block is preferred to
a stranded completion.

## Consequences

- **Subagents are no longer blocked.** A subagent's `agentStop` names its own id, which owns no row.
  This corrects [ADR-0004](./0004-two-hook-events-carry-the-chain.md)'s assumption that `agentStop`
  fires only for the parent.
- **Parallel routing sessions each route only their own completions.** One session's fill never
  spends another's attempts, so `route-abandoned` once again means the owner itself let three
  requests go unanswered.
- **Confirmation is scoped the same way.** A forced turn confirms only requests owed to its own
  session, so another session's forced turn can no longer mark this session's request `routed`.
- **An ended session's completions stay unrouted in the ledger.** No other session's hook adopts
  them. Nothing durable is lost: the run's outcome is on the tracker and the session log records the
  ended session, so the next `/next` in any session picks the successor up from durable state. The
  hook exists to keep the launching session's fill going, not to transfer fills between sessions.

## Considered options

**Keep blocking every stop and let the model ignore requests it does not own.** Rejected: each
block still costs a turn in the wrong session and an attempt on the owner's row, and an ignored
request can still be confirmed by the wrong session's forced turn.

**Let a live session adopt the completions of an ended one, judged by the reservation's parent
process.** Deferred: the helper has no process-identity check of its own, and adoption would
recreate the cross-session pull this decision removes. Revisit only if ended sessions' completions
prove to need a hook-driven route rather than the next `/next` reading the tracker.

**Match on `agentId` or `transcriptPath` instead.** Rejected: `agentStop` carries no `agentId`, and
`session_id` is the field the bind contract already records for exactly this correlation.
