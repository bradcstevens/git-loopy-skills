# A route is confirmed by the next `stop_hook_active` turn, not by the block that asked for it

`agentStop` writes `route_requested_at` and an attempt count when it blocks, and writes `routed`
only when a later payload arrives with `stop_hook_active` true. Those are two different facts: the
first says the chain asked for a hop, the second says the parent actually took the turn that hop
needs.

The helper previously wrote `routed` at the moment it blocked. That records an intent as a
completed fact, and the intent is not reliable. The CLI presents a block reason to the parent as a
**dismissible queued prompt** — the queue manager offers `x` to remove the item — so the forced
turn is skipped whenever the operator removes the prompt or presses `esc`, the session exits
first, or the runtime reaches its ceiling of consecutive blocks. In each case the row read `routed:
true` forever, the next `agentStop` reported `no-unrouted-completion`, and the hop was gone. Nobody
was told — the silent-stall class of #41, and a defeat of the reason
[ADR-0004](./0004-two-hook-events-carry-the-chain.md) chose a hook over an instruction: that the
next `/next` runs whether or not the model remembers.

## Why `stop_hook_active` is the evidence

It is the only signal the runtime gives that a block landed. ADR-0004 established it as the
loop-breaker — `false` on a natural stop, `true` on a turn a block forced — and a forced turn is
exactly the thing a route request is waiting on.

It is also indirect, so the request records the session it was asked in and is confirmed only by a
turn from that session. Confirming whichever request came first instead would let two sessions
routing one repository credit each other's hops — one target marked routed on a turn forced for
another, and the miscredited hop never asked for again.

That makes `sessionId` a field this path reads, so a block requires one. **This extends
[ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md)**, which lists
`agentStop` as reading `cwd`, `timestamp` and `stop_hook_active` and tolerating the rest — the same
rule, applied to a field that has since become read. A payload without one stands aside under
`missing-session-id` naming the target, because recording a request nothing could confirm is the
worse failure: it would force a turn no confirmation could credit, re-block to the cap, and abandon
a hop that had in fact landed.

What that leaves is a session's own hooks. `stop_hook_active` says a turn was forced, not that
`/next` ran inside it, so a turn some other stop hook forced in the same session can still
over-confirm a request the operator had dismissed. The chain accepts that: closing it would mean
reading the transcript, a much larger dependency for a much smaller gain, and the confirmation names
its target in the decision it emits, so the log shows the hop and the turn credited with it —
whereas the pre-emptive write it replaces named nothing at all.

## Consequences

- **`routed` means routed.** The "already routed" test is satisfied only by a confirmed route, so a
  dismissed prompt, an interrupted turn, or an exited session leaves the row owed and a later
  `agentStop` blocks again for the same target.
- **The attempt count is the request, not the request time.** `route_attempts` is written by the
  helper itself, so it is on the row whatever the payload carried, whereas `route_requested_at`
  comes from `timestamp`, which ADR-0005 leaves optional. Gating confirmation on the time would
  make an absent one produce a request nothing could confirm.
- **Re-blocking is capped at three attempts per row**, and giving up is a decision the log can see.
  ADR-0004 requires the chain's own guard to trip inside the runtime's ceiling of 8, so the halt is
  explained rather than the runtime halting it first with no visible reason; three matches the
  repetition guard `/next` already applies per target. Tripping it stands aside under
  `route-abandoned` naming the target, so the hook invocation log (#27) shows which hop was dropped.
- **A request names every session owed a forced turn for it.** `route_requested_by` collects them
  rather than keeping only the latest, because each one is holding a turn that will arrive: the
  first to arrive confirms the hop, instead of finding the request taken over and having to ask
  again. It is written through the same atomic replace as the rest of the row, so an interrupted
  helper leaves the previous ledger whole.
- **`stop_hook_active` still never starts a route.** It may only promote a request that already
  exists, so a ledger that is missing, unreadable, or locked simply means there is nothing to
  confirm, and the hook stands aside under `stop-hook-active` as before.

## Considered options

**Keep writing `routed` on the block and add a sweeper that reopens rows nothing followed up on.**
Rejected: it needs a second clock to decide what "nothing followed up" means, and can only run in a
session that may never come.

**Treat the block as authoritative and ask the runtime for a non-dismissible prompt.** Rejected: the
dismissible queue is the runtime's behaviour, not a setting this repository controls, and a chain
that depends on an operator never pressing `x` is not a chain.
