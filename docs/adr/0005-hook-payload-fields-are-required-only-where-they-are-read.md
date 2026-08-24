# A hook payload field is required only where the chain reads it

`complete` validates the `subagentStop` fields it actually reads — and which ones it reads depends
on the payload in front of it. `sessionId`, `cwd` and `timestamp` are read on every path: the
session scopes the match, `cwd` locates the repository and the worktree, `timestamp` closes the row.
`agentId` and `agentType` are read only when the payload carries them, and `agentName` only when it
does not. Every other field the runtime sends is optional and unvalidated, including ones no release
has sent yet.

It previously required ten, four of which it never read. Real payloads from built-in agent types
carry no `agentDisplayName`, so the hook exited 2 on genuine traffic: no completion closed its
ledger row, `agentStop` never saw an unrouted run, and the chain did nothing while reporting
nothing wrong (#41).

`agentName` was the sixth until #67. It found the ledger row until the runtime was observed to set
it to the agent *type* rather than to the descriptive name a caller binds, at which point matching
on it could only ever decline a correctly bound row. It left the match, and this rule then required
it to leave `required_fields` too.

`agentId` and `agentType` were the last two, until #70. Re-measured on the machine that produced
these fixtures, **502 of 824** recorded `subagentStop` invocations carried neither, and the two
fields are perfectly correlated: a payload has both or neither, with no mixed shape observed and no
session among the 130 emitting both. It is not one agent type misbehaving — the shape covers
`code-review`, `task`, `general-purpose`, `explore`, `security-review` and `research`, and those
same built-in types also appear on payloads that *do* carry identity, so which shape a run produces
follows the session it was launched from rather than the agent it ran. Nor is it rare: it is 61% of
all traffic and effectively all recent traffic. Requiring identity rejected those completions at
exit 2 before any match ran, which is #41 again, one field further along.

## Identity is conditional, so the predicate is tiered

Dropping `agentId` and `agentType` from `required_fields` is necessary and not sufficient. The
payloads that omit `agentType` omit `agentId` too, so once identity is optional the match has
nothing left to read: the same completion is then declined instead of rejected, and the row still
never closes. Something else has to find the row.

So `complete` matches in two tiers, on the strongest evidence the payload actually carries:

- **The payload names the run.** `sessionId` + `agentId` + `agentType`, unchanged. `agentId`
  identifies the run on its own, and the other two keep payloads from another session or another
  agent type — which legitimately reach the same hook — from closing this row.
- **The payload names no run.** `sessionId` + the worktree, compared as real paths against the
  payload `cwd` + the agent type, which the runtime sends as `agentName` (#67). Session and agent
  type do the same work they do above. The worktree is what makes at most one row plausible: a
  session runs several agents of one type, but the chain gives each of them its own directory.

The tiers are not collapsible into one flat predicate. The captured with-identity payload reports
the launching session's own directory rather than the reserved worktree the run worked in, so a
single directory-based predicate would decline precisely the runs that name themselves. Tiering
keeps the stronger evidence wherever the runtime supplies it, and weakens the predicate only where
it supplies nothing else.

What the weaker tier can act on is bounded by what the payload reports: it closes a row when the run
reported the directory that row reserved, and declines when it did not. That bound is deliberate,
and the floor underneath it is the point — a payload carrying no identity is now answered at exit 0
with a named reason instead of aborting the hook at exit 2, so `agentStop` and every gate that reads
open rows keep working either way.

## Why the payload shape is not a contract

The extra fields came from the #3 spike, which read them off a payload it had observed. That
observation was of a **custom** agent the spike had written, and a custom agent carries a display
name. The list was accurate for what was tested and wrong as a general contract.

A payload shape taken from a single observation describes one sender, not the sender's guarantee.
The runtime decides per-agent what to include and may add fields in any release, so the set of keys
is not something this repository can pin. What it can pin is what its own code reads.

## Consequences

- **Validation is derived from use, and use is conditional.** A field enters `required_fields` when
  `complete` reads it and leaves when it stops — and when it is read on only one path, it is
  required on only that path. `agentName` is required again for exactly this reason, having left in
  #67: the fallback tier reads it, so a payload that reaches that tier without it is rejected, while
  one that never reaches it is not.
- **Unknown fields pass through untouched.** A future runtime field cannot break the chain the way
  `agentDisplayName` did. This is deliberate: the narrow fix of making that one field optional
  would have left the next conditional field to fail identically.
- **Genuine absences still fail loudly.** A payload missing a field the chain reads on the path it
  took is rejected with a message naming it, because the chain cannot correlate or close a row
  without it. Optional means unread, not unimportant. A payload carrying half an identity — one of
  `agentId` and `agentType` and not the other — is a shape no runtime has been seen to send, and is
  rejected naming the missing half rather than quietly demoted to the weaker tier.
- **A weaker predicate still never guesses.** The fallback correlates by circumstance rather than by
  identity, so it declines as `ambiguous-payload` whenever more than one open row fits, exactly as
  the identity tier does. Leaving a row open is recoverable; closing the wrong one routes the wrong
  work onward.
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

**Make `agentType` optional and drop it from the match, leaving `agentId` to identify the run.**
Rejected by replay, not by argument: a captured no-identity payload replayed against a ledger
holding a matching bound row still failed with `subagent-stop payload is missing agentId`, and the
row stayed open. The two fields are absent together, so relaxing one of them moves the rejection
without closing anything.

**Fall back on `sessionId` and the agent type alone, without the worktree.** Rejected because a
session routinely runs several agents of one type, so the fallback would be ambiguous whenever the
chain was doing more than one thing — and declining every such payload as ambiguous is the same
leaked row by another name. The worktree is what makes the correlation specific enough to act on.
