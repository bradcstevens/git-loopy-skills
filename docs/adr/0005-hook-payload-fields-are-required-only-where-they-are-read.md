# A hook payload field is required only where the chain reads it

`complete` validates the six `subagentStop` fields it actually uses — `sessionId`, `agentId`,
`agentType` and `agentName` to find the ledger row, `cwd` to locate the repository, `timestamp` to
close the row. Every other field the runtime sends is optional and unvalidated, including ones no
release has sent yet.

It previously required ten, four of which it never read. Real payloads from built-in agent types
carry no `agentDisplayName`, so the hook exited 2 on genuine traffic: no completion closed its
ledger row, `agentStop` never saw an unrouted run, and the chain did nothing while reporting
nothing wrong (#41).

## Why the payload shape is not a contract

The extra fields came from the #3 spike, which read them off a payload it had observed. That
observation was of a **custom** agent the spike had written, and a custom agent carries a display
name. The list was accurate for what was tested and wrong as a general contract.

A payload shape taken from a single observation describes one sender, not the sender's guarantee.
The runtime decides per-agent what to include and may add fields in any release, so the set of keys
is not something this repository can pin. What it can pin is what its own code reads.

## Consequences

- **Validation is derived from use.** A field enters `required_fields` when `complete` reads it and
  leaves when it stops. A field that is validated but unread is a bug — it can only ever reject
  traffic the chain would have handled correctly.
- **Unknown fields pass through untouched.** A future runtime field cannot break the chain the way
  `agentDisplayName` did. This is deliberate: the narrow fix of making that one field optional
  would have left the next conditional field to fail identically.
- **Genuine absences still fail loudly.** A payload missing a field the chain reads is rejected with
  a message naming it, because the chain cannot correlate or close a row without it. Optional means
  unread, not unimportant.
- **This applies to `agentStop` too.**
  [ADR-0004](./0004-two-hook-events-carry-the-chain.md) lists the fields its spike saw on the
  `agentStop` payload. That is a record of one observation, not a shape to validate against; the
  helper reads `cwd`, `timestamp` and `stop_hook_active` and tolerates the rest.

## Considered options

**Validate the full observed payload and update the list when it changes.** Rejected: the list can
only be updated after a live payload has already been rejected, and this failure mode is silent —
the cost is paid before the signal arrives.

**Validate nothing and let missing fields surface as errors downstream.** Rejected because the
resulting failure is a `KeyError` inside a hook, at a point where the ledger may be half-written. A
named rejection before any state changes is worth the six-line check.
