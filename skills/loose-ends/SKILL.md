---
name: loose-ends
description: Audit the issue tracker for structural, resolved-work, and ledger defects, then open a read-only HTML report.
disable-model-invocation: true
---

# Loose Ends

`/loose-ends [--grace-days <non-negative-integer>]`

`/loose-ends` audits tracker conditions that need follow-up. It is a user-invoked survey: it
reads the issue tracker, writes one static HTML report outside the repository, opens it,
prints its absolute path, and stops.

## Non-negotiable posture

- **Read-only:** use only read operations against the tracker. Never create, edit, label,
  comment on, assign, close, reopen, or otherwise mutate an issue or pull request.
- **No repository writes:** do not create files in the repository. The generated report is
  the sole local write and belongs in the OS temp directory.
- **User-invoked only:** `disable-model-invocation` is deliberate. Do not launch this
  whole-tracker sweep implicitly during another workflow.
- **Degrade cleanly:** no matching issues is a successful audit. Render the empty report
  and open it rather than treating an empty result as an error.

Resolve the tracker repository from the current checkout's `origin` remote.

## Terms and invocation

An issue is **workflow-bearing** when its open body is a durable artifact produced by a
workflow transition or is an anchor from which one should follow. Artifact body shape and
the native sub-issue graph are the source of truth; labels support workflow state but do
not identify an artifact class.

`Never decomposed` and `Completed spec still open` apply only to spec-shaped
workflow-bearing issues. A spec contains all four exact Markdown headings: `## Problem
Statement`, `## Solution`, `## User Stories`, and `## Implementation Decisions`. Tickets use
a distinct body shape. Never use `ready-for-agent` to distinguish the two: both specs and
tickets carry that label.

Wayfinder artifacts use their own label namespace, never a body fingerprint: a map carries the
exact `wayfinder:map` label and a map ticket carries one of `wayfinder:research`,
`wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`. An anchor carries the exact
`idea` label. Discover descendants only through native sub-issues, not a Markdown task list or
cross-reference. A descendant spec still uses the spec fingerprint above; a descendant map uses
`wayfinder:map`.

`--grace-days` defaults to `7`. It accepts a non-negative integer and overrides every
structural finding's grace period; it never delays defect findings. For example,
`/loose-ends --grace-days 0` exposes every eligible structural finding immediately. Reject any
other argument with the invocation syntax before starting the audit.

Anchors with no descendant deliberately have no current producer: the separate recording fix
will create `idea`-labelled anchors when a grilling session reaches its checkpoint. This rule is
implemented now so those anchors are detected when that input lands; finding none before then is
expected.

## Audit

1. List every open issue, including its number, title, URL, body, creation time, and label
   names. Fetch all result pages; do not assume a small tracker.
2. Identify spec-shaped issues strictly from every heading in the authoritative fingerprint
   above. Do not inspect their `ready-for-agent` label to make this decision.
3. Suppress an issue before any further inspection when its labels include the exact,
   human-applied `intentional` label. Keep the exclusion set for every class, including
   specs, maps, anchors, and claimed wayfinder tickets. The audit never adds, removes, or
   infers this label.
4. For each remaining spec-shaped issue, fetch all native GitHub sub-issues with the
   read-only `GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` endpoint,
   following pagination. A non-empty result suppresses only the `Never decomposed` finding:
   retain each child's current state for the completed-parent defect check.
5. For every remaining spec with one or more native sub-issues, report `Completed spec still
   open` immediately when every child is currently closed and the parent is currently open.
   Evidence must link the parent, enumerate every child with its live closed state, and give
   the child count. Do not apply a grace period or substitute timestamps for these states.
   Its follow-up action is **Close completed spec**.
6. For each remaining spec with zero native sub-issues and every issue that could support a
   grace-held map, anchor, or stale-claim finding, fetch every page of the issue timeline
   read-only. Determine activity from the newest of:
   - a comment event;
   - a label-added or label-removed event;
   - a linked pull-request event, including a cross-reference whose source is a pull
     request.

   Do not use the issue's general `updated_at` value: it does not express this audit's
   definition of activity. If none of those events exists, use `created_at` as the idle
   baseline.
7. Calculate both durations at report-generation time:
   - **Created age:** now minus `created_at`.
   - **Idle time:** now minus the most recent qualifying activity, or `created_at` when no
     qualifying activity exists.

   Hold the finding when idle time is less than the grace period. Report it once idle time
   reaches or exceeds the grace period.
8. For each eligible issue, create a `Never decomposed` finding. Its evidence must
   enumerate the four matching headings from the authoritative fingerprint and state that
   the native sub-issue query returned zero children. Keep the finding's raw evidence in
   the report so the user can judge the classification.
9. For each remaining open `wayfinder:map`, fetch every page of its native sub-issues, retain
   only its labelled wayfinder tickets, and fetch the full native descendant graph for the
   published-spec check. For every open ticket, fetch its live issue representation and use
   `issue_dependencies_summary.blocked_by` as the blocker count. That count is already limited
   to open native blockers: do not count closed blockers or parse a `Blocked by` body line.
   An open, unblocked, unassigned ticket is the map's frontier.

   - Report **Completed wayfinder map, no spec** when the map has at least one labelled
     wayfinder ticket, every such ticket is closed, and its native descendant graph contains no
     spec-shaped issue. Hold it until the map's idle time reaches the effective grace period.
     Its evidence must enumerate each closed ticket, state that the native descendant walk
     found no spec, and retain the raw labels and states.
   - Report **Wayfinder dependency deadlock** when the map has at least one open labelled
     wayfinder ticket and every open ticket has one or more open native blockers. Hold it until
     the map's idle time reaches the effective grace period. Its evidence must enumerate every
     ticket and its open-blocker count; a child that is merely assigned is not a dependency
     deadlock.
   - Report **Stale wayfinder claim** when the frontier is empty, one or more open unblocked
     wayfinder tickets are assigned, and every assigned unblocked ticket has been idle for at
     least the effective grace period. Hold this finding until each such claim reaches that
     idle threshold. Determine a claim's staleness from the ticket's latest qualifying activity
     under step 6, never from the assignment timestamp. Its evidence must enumerate all open
     tickets, distinguish native blockers from assigned unblocked tickets, and show the created
     age and idle time of each stale claim. A map with open dependencies and stale claims is a
     stale-claim finding when the claims, rather than the dependencies, close its frontier.

   Do not report either map finding when the map carries `intentional`; the label suppresses
   every finding whose target is that map.
10. For each remaining open `idea` anchor, fetch its complete native descendant graph. Report
    **Anchor with no descendant** when no descendant is spec-shaped and none carries
    `wayfinder:map`; hold it until the anchor's idle time reaches the effective grace period.
    Evidence must state that the graph walk found neither artifact, link every descendant when
    present, and identify the `idea` label. Do not report an anchor carrying `intentional`.
11. Independently enumerate every merged pull request in the repository through GitHub's
    read-only GraphQL API, following pagination for both pull requests and each pull
    request's `closingIssuesReferences`. Use that native closing-reference relationship; a
    generic mention or cross-reference is not evidence that the pull request resolved an
    issue. Group every referenced issue by issue number before reporting. For each group,
    read its current live state and labels. When it is currently open and does not carry
    `intentional`, report one `Merged work, open issue` finding immediately. Evidence must
    link every merged pull request in the group, include each merge timestamp, and link the
    live-open issue. Its follow-up action is **Close resolved issue**. A merge is evidence,
    never a substitute for querying the issue's live state.
12. After completing tracker-only steps 1-11, always read
    [`ledger-audit.md`](ledger-audit.md). It selects the optional ledger outcome and owns
    every native consumer operation, availability outcome, ledger-drift finding, and
    ledger-specific report surface.

## Report

Create one timestamped, static HTML file at
`$TMPDIR/loose-ends-<timestamp>.html`; if `$TMPDIR` is unset, use `/tmp` on Unix-like
systems or `%TEMP%` on Windows. Resolve it to an absolute path before writing. The HTML
must contain all finding data at generation time: it must not make tracker requests or
depend on application code after it is opened. HTML-escape every tracker-provided field
before interpolation. [`ledger-audit.md`](ledger-audit.md) owns escaping ledger fields.

Use the architecture survey's dark-only presentation scaffold locally so a single-skill
installation has every instruction it needs:

- Use Tailwind CDN, an optional Mermaid ESM import, the slate palette, generous spacing, a
  `max-w-5xl` main column, and a compact metadata header.
- Render an editorial survey, not an application dashboard. Cards use `bg-slate-900`,
  `border-slate-800`, `text-slate-100`, `text-slate-200`, and `text-slate-400`; use tinted
  emerald for actionable findings and amber only for held or cautionary context.
- Header metadata shows the repository, exact generation timestamp, the effective grace
  period, that defects are immediate, and the finding count. Do not add a generic
  introduction paragraph.
- Group findings by **follow-up action**, not finding class. This tracer renders
  **`/to-tickets` — decompose published specs**, **Close resolved issue**, and **Close
  completed spec** when their associated findings exist. It also renders **`/to-spec` —
  collect completed planning**, **Review wayfinder dependencies**, **Release stale
  wayfinder claims**, and **`/to-spec` — collect concluded anchors** when their associated
  findings exist. The optional ledger branch adds its own group or status card under
  [`ledger-audit.md`](ledger-audit.md).

Every finding is a complete card containing:

1. Issue number, HTML-escaped title, and link.
2. Finding-class badge and the evidence block.
3. A full **Recommendation** block:
   - **Follow-up:** `/to-tickets`
   - **Interaction:** `HITL` — the decomposition needs human approval.
   - **Target:** the linked spec issue.
   - **State:** `Open; no native sub-issues; <effective grace> grace elapsed`.
   - **Context:** `Fresh session`.
   - **Runtime:** read `git-loopy config list` when available and use its
     `task-type:planning` model and effort. When that route is unset, use the command's
     generic model and effort. Always include `--context long_context`; if `git-loopy` is
     unavailable, use `--model claude-opus-5 --effort xhigh --context long_context`.
   - **Prompt:** a separate code block containing exactly one physical ASCII line:
     `/to-tickets <issue-number>`

The prompt must not contain formatting, line breaks, shell quoting, or explanatory text.

Every structural finding shows the target's created age and idle time side by side; say
`No qualifying activity since creation` when that is the idle baseline. A stale-claim card
also shows those values for every claim holding the frontier closed.

For the immediate defect groups, replace the `Never decomposed` recommendation with the
matching complete recommendation. The shared close-issue fields below apply only to the next
two recommendations; each rendered card repeats them so it remains self-contained:

- **Interaction:** `HITL` — review the evidence before a human closes the issue.
- **Context:** Current session.
- **Runtime:** none.
- **Prompt:** a separate code block containing exactly one physical ASCII line:
  `gh issue close <issue-number> --repo <owner>/<repo>`

- **Merged work, open issue**
  - **Follow-up:** Close resolved issue.
  - **Evidence review:** the merged pull request and live-open issue.
  - **Target:** the linked open issue.
  - **State:** `Open; resolved by merged pull request(s) #<pull-request-number>`.
- **Completed spec still open**
  - **Follow-up:** Close completed spec.
  - **Evidence review:** the closed native sub-issues.
  - **Target:** the linked spec issue.
  - **State:** `Open; all <child-count> native sub-issues closed`.
- **Completed wayfinder map, no spec**
  - **Follow-up:** `/to-spec` — collect completed planning.
  - **Interaction:** `HITL` — confirm the completed map still describes the specification.
  - **Target:** the linked map issue.
  - **State:** `Open; all <ticket-count> labelled wayfinder tickets closed; no native
    descendant spec`.
  - **Context:** Fresh session.
  - **Runtime:** the `task-type:planning` model and effort, always with `--context long_context`.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `/to-spec <map-number>`
- **Wayfinder dependency deadlock**
  - **Follow-up:** Review wayfinder dependencies.
  - **Interaction:** `HITL` — a human must decide whether to resolve, remove, or rewire a
    native dependency.
  - **Target:** the linked map issue.
  - **State:** `Open; every open wayfinder ticket has an open native blocker`.
  - **Context:** Fresh session.
  - **Runtime:** none.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `/wayfinder <map-number>`
- **Stale wayfinder claim**
  - **Follow-up:** Release stale wayfinder claims.
  - **Interaction:** `HITL` — verify the claim is abandoned before changing its assignee.
  - **Target:** the linked map issue and each linked stale claim.
  - **State:** `Open; frontier empty because every unblocked ticket is stale and assigned`.
  - **Context:** Current session.
  - **Runtime:** none.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `gh issue edit <ticket-number> --remove-assignee <assignee> --repo <owner>/<repo>`
- **Anchor with no descendant**
  - **Follow-up:** `/to-spec` — collect concluded anchors.
  - **Interaction:** `HITL` — confirm the anchor still describes work worth specifying.
  - **Target:** the linked `idea` anchor.
  - **State:** `Open; no native descendant spec or wayfinder map`.
  - **Context:** Fresh session.
  - **Runtime:** the `task-type:planning` model and effort, always with `--context long_context`.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `/to-spec <anchor-number>`

When there are no tracker findings and the ledger branch produces neither a finding nor an
incomplete-audit card, render the same header and a clean empty-state card titled
`No loose ends found`. Its body says: `No reportable tracker defects found. No open spec has
or structural workflow artifacts have exceeded the effective grace period.` This is a normal
successful report, including on an empty tracker.

After writing the report, open it with the platform opener (`open` on macOS, `xdg-open` on
Linux, or `start` on Windows), then print the absolute file path in the terminal. End the
skill there; when the user chooses a finding, they invoke the recommendation directly
rather than routing the already-selected follow-up through `/next`.
