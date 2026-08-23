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
was told. That is the silent-stall class of #41, which
[ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md) describes as "the
chain did nothing while reporting nothing wrong", and it defeats the reason
[ADR-0004](./0004-two-hook-events-carry-the-chain.md) chose a hook over an instruction: that the
next `/next` runs whether or not the model remembers.

## Why `stop_hook_active` is the evidence

It is the only signal the runtime gives that a block landed. ADR-0004 established it as the
loop-breaker — `false` on a natural stop, `true` on a turn a block forced — and a forced turn is
exactly the thing a route request is waiting on. Reading it as confirmation asks nothing new of the
runtime.

It is deliberately indirect, so the request records the session it was asked in and is confirmed
only by a turn from that session. `sessionId` is on every `agentStop` payload and ADR-0004 already
lists it, so this asks nothing new of the runtime either. Confirming whichever request came first
instead would let two sessions routing one repository credit each other's hops — one target marked
routed on a turn forced for another, and the miscredited hop never asked for again. A request that
named nobody stays confirmable by anyone, because its payload carried no `sessionId` to narrow on,
and a request nothing can confirm is worse than a loose one.

What that leaves is a session's own hooks. `stop_hook_active` says a turn was forced, not that
`/next` ran inside it, so a turn some other stop hook forced in the same session can still
over-confirm a request the operator had dismissed. The chain accepts that: closing it would mean
reading the transcript, a much larger dependency for a much smaller gain, and the confirmation names
its target in the decision it emits, so the hook invocation log (#27) shows the hop and the turn
credited with it — whereas the pre-emptive write it replaces named nothing at all.

## Consequences

- **`routed` means routed.** The "already routed" test is satisfied only by a confirmed route, so a
  dismissed prompt, an interrupted turn, or an exited session leaves the row owed and a later
  `agentStop` blocks again for the same target.
- **The attempt count is the request, not the request time.** `route_attempts` is written by the
  helper itself, so it is on the row whatever the payload carried. `route_requested_at` comes from
  `timestamp`, which [ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md)
  leaves optional because nothing read it; gating confirmation on it would make an absent
  `timestamp` produce a request that can never be confirmed, and so re-block to the cap and abandon
  a hop that had actually landed. The time stays as provenance and is omitted rather than stored
  null, so an absent one cannot claim the first-request slot.
- **Re-blocking is capped at three attempts per row.** ADR-0004 requires the chain's own guard to
  trip inside the runtime's ceiling of 8, so the halt is explained rather than the runtime halting
  it first with no visible reason. Three matches the repetition guard `/next` already applies per
  target.
- **Giving up is a decision the log can see.** Tripping the cap stands aside under
  `route-abandoned` naming the target, so the hook invocation log (#27) shows which hop was dropped
  and why. Standing aside quietly would reintroduce the silence this replaces.
- **The ledger carries the request.** `route_requested_at`, `route_requested_by`, `route_attempts`,
  `route_abandoned` and `route_abandoned_at` join `routed` and `routed_at` on the row. They are
  written through the same atomic replace, so an interrupted helper leaves the previous ledger
  whole.
- **A request names every session owed a forced turn for it.** `route_requested_by` collects them
  rather than keeping only the latest, because each one is holding a turn that will arrive: the
  first to arrive confirms the hop, instead of finding the request taken over and having to ask
  again.
- **`stop_hook_active` still never starts a route.** It may only promote a request that already
  exists. A ledger that is missing, unreadable, or locked simply means there is nothing to confirm,
  and the hook stands aside under `stop-hook-active` as before.

## Considered options

**Keep writing `routed` on the block and add a sweeper that reopens rows nothing followed up on.**
Rejected because it needs a second clock to decide what "nothing followed up" means, and it can
only run in a session that may never come.

**Treat the block as authoritative and ask the runtime for a non-dismissible prompt.** Rejected
because the dismissible queue is the runtime's behaviour, not a setting this repository controls,
and a chain that depends on an operator never pressing `x` is not a chain.

**Re-block until the runtime's ceiling of 8 stops it.** Rejected because the runtime exits cleanly
and says nothing, so the halt would be invisible at precisely the moment someone needs to know a
hop was abandoned.
