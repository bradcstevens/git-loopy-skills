# Ledger Audit

Read this reference only for the optional Continuation-ledger branch in `/loose-ends` audit
step 10. It adds a read-only reconciliation check to the tracker-only report.

## Native consumer

The native `git-loopy continuation capabilities` output owns supported operations, ledger
availability, and schema discovery. Its reconciliation request schema owns all Continuation
terms and request fields. Use those native sources rather than parsing ledger comments or
copying their contract.

1. Query native capabilities.
2. If they affirm that this repository has no Continuation records, omit this branch without
   a finding, warning, or report surface.
3. If they advertise `reconcile` and a machine-discoverable request schema, construct the
   request from that schema and obtain its machine-readable reconciliation projection using
   the configured trusted-producer policy.
4. For every explicit tracker-state claim in that projection, fetch its target from the live
   tracker and compare actual state with claimed state. A future objective is not a current
   state claim. When a claim differs from live state and the target lacks `intentional`,
   report `Ledger drift` immediately.

Preserve the native error when capabilities, reconciliation, or schema discovery are
unavailable or fail. Ledger availability is then incomplete rather than absent.

## Report

HTML-escape every Continuation-record field before interpolation.

- A native no-records result has no ledger report surface.
- An incomplete audit renders one compact amber `Ledger audit incomplete` status card below
  the header. State that tracker-only findings are complete, drift findings are omitted, and
  include the escaped native error. The card is not a finding, has no recommendation, and is
  excluded from the finding count and follow-up groups.
- A `Ledger drift` finding joins the **Reconcile Continuation ledger** follow-up group. Its
  evidence preserves the record carrier and claim beside the contradictory live tracker state.

Every Ledger drift card contains a complete **Recommendation**:

- **Follow-up:** Reconcile Continuation ledger.
- **Interaction:** `HITL` — inspect native reconciliation evidence and choose the repair; the
  audit does not change the record or tracker.
- **Target:** linked issue whose live state contradicts the linked record carrier.
- **State:** `Ledger claims <claimed-state>; tracker is <live-state>`.
- **Context:** Fresh session.
- **Runtime:** native Continuation command's configured trusted-producer policy.
- **Prompt:** derive the exact reconciliation invocation from the advertised native schema.
  Do not synthesize or cache a command contract.
