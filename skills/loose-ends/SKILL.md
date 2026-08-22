---
name: loose-ends
description: Audit the issue tracker for workflow artifacts that were started but never followed up, then open a read-only HTML report of the findings.
disable-model-invocation: true
---

# Loose Ends

`/loose-ends [--grace-days <non-negative-integer>]`

`/continuation` reports what was recorded; `/loose-ends` reports what was never
recorded. It is a user-invoked survey: it reads the issue tracker and, when available, the
Continuation ledger; writes one static HTML report outside the repository; opens it; prints
its absolute path; and stops.

## Non-negotiable posture

- **Read-only:** use only read operations against the tracker and native Continuation
  consumer. Never create, edit, label, comment on, assign, close, reopen, publish, repair,
  or otherwise mutate an issue, pull request, or ledger.
- **No repository writes:** do not create files in the repository and do not publish a
  Continuation record. The generated report is the sole local write and belongs in the OS
  temp directory.
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

This tracer handles spec-shaped workflow-bearing issues. A spec contains all four exact
Markdown headings: `## Problem Statement`, `## Solution`, `## User Stories`, and
`## Implementation Decisions`. Tickets use a distinct body shape. Never use
`ready-for-agent` to distinguish the two: both specs and tickets carry that label.

`--grace-days` defaults to `7`. It accepts a non-negative integer and overrides only the
`Never decomposed` structural finding's grace period; it never delays defect findings. For
example, `/loose-ends --grace-days 0` exposes every eligible structural finding immediately.
Reject any other argument with the invocation syntax before starting the audit.

## Audit

1. List every open issue, including its number, title, URL, body, creation time, and label
   names. Fetch all result pages; do not assume a small tracker.
2. Identify spec-shaped issues strictly from every heading in the authoritative fingerprint
   above. Do not inspect their `ready-for-agent` label to make this decision.
3. Suppress an issue before any further inspection when its labels include the exact,
   human-applied `intentional` label. The audit never adds, removes, or infers this label.
4. For each remaining spec-shaped issue, fetch all native GitHub sub-issues with the
   read-only `GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` endpoint,
   following pagination. A non-empty result suppresses only the `Never decomposed` finding:
   retain each child's current state for the completed-parent defect check.
5. For every remaining spec with one or more native sub-issues, report `Completed spec still
   open` immediately when every child is currently closed and the parent is currently open.
   Evidence must link the parent, enumerate every child with its live closed state, and give
   the child count. Do not apply a grace period or substitute timestamps for these states.
   Its follow-up action is **Close completed spec**.
6. For each remaining spec with zero native sub-issues, fetch every page of the issue timeline
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
9. Independently enumerate every merged pull request in the repository through GitHub's
   read-only GraphQL API, following pagination for both pull requests and each pull
   request's `closingIssuesReferences`. Use that native closing-reference relationship; a
   generic mention or cross-reference is not evidence that the pull request resolved an
   issue. For each referenced issue, read its current live state and labels. When it is
   currently open and does not carry `intentional`, report `Merged work, open issue`
   immediately. Evidence must link the merged pull request, include its merge timestamp,
   and link the live-open issue. Its follow-up action is **Close resolved issue**. A merge
   is evidence, never a substitute for querying the issue's live state.
10. Run this final pass only when the native `git-loopy continuation` capability advertises
    `reconcile` and a Continuation ledger has records for this repository. Request its
    machine-readable reconciliation projection using the configured trusted-producer policy;
    do not parse ledger comments independently or reimplement native reconciliation.

    For every explicit tracker-state claim in that projection, fetch the claim's target from
    the live tracker and compare its actual state with the state the record claims. A future
    `completion_condition` is an objective, not a claim about current state, and must not
    create drift merely because it is unfinished. When a record's current-state claim and
    the live target differ, and the target does not carry `intentional`, report `Ledger
    drift` immediately. Evidence must preserve the record carrier and claim, alongside the
    live tracker state that contradicts it. Its follow-up action is **Reconcile Continuation
    ledger**.

    A missing `git-loopy` command, unavailable `reconcile` capability, or repository with no
    Continuation records means the ledger is absent: skip this pass without a finding,
    warning, or failure. Continue every tracker-only pass normally. Do not disguise a
    present ledger's malformed record or failed read as absence; surface that read failure
    rather than asserting a complete drift audit.
11. For every reported finding, fetch every page of its target issue's timeline when it was
    not already fetched and calculate created age and idle time using the activity definition
    above. Show those durations as evidence on every card, but never use them to delay an
    immediate defect finding.

## Report

Create one timestamped, static HTML file at
`$TMPDIR/loose-ends-<timestamp>.html`; if `$TMPDIR` is unset, use `/tmp` on Unix-like
systems or `%TEMP%` on Windows. Resolve it to an absolute path before writing. The HTML
must contain all finding data at generation time: it must not make tracker requests or
depend on application code after it is opened. HTML-escape every tracker-provided field
and every Continuation-record field before interpolation.

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
  **`/to-tickets` — decompose published specs**, **Close resolved issue**, **Close completed
  spec**, and **Reconcile Continuation ledger** when their associated findings exist.

Every finding is a complete card containing:

1. Issue number, HTML-escaped title, and link.
2. Finding-class badge and the evidence block.
3. Created age and idle time shown side by side; say `No qualifying activity since creation`
   when that is the idle baseline.
4. A full **Recommendation** block:
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

For the immediate defect groups, replace the `Never decomposed` recommendation with the
matching complete recommendation:

- **Merged work, open issue**
  - **Follow-up:** Close resolved issue.
  - **Interaction:** `HITL` — review the merged pull request and live-open issue before a
    human closes it.
  - **Target:** the linked open issue.
  - **State:** `Open; resolved by merged pull request #<pull-request-number>`.
  - **Context:** Current session.
  - **Runtime:** none.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `gh issue close <issue-number> --repo <owner>/<repo>`
- **Completed spec still open**
  - **Follow-up:** Close completed spec.
  - **Interaction:** `HITL` — review the closed native sub-issues before a human closes the
    parent.
  - **Target:** the linked spec issue.
  - **State:** `Open; all <child-count> native sub-issues closed`.
  - **Context:** Current session.
  - **Runtime:** none.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `gh issue close <issue-number> --repo <owner>/<repo>`
- **Ledger drift**
  - **Follow-up:** Reconcile Continuation ledger.
  - **Interaction:** `HITL` — inspect the native reconciliation evidence and choose the
    repair; the audit must not change the record or tracker.
  - **Target:** the linked issue whose live state contradicts the linked record carrier.
  - **State:** `Ledger claims <claimed-state>; tracker is <live-state>`.
  - **Context:** Fresh session.
  - **Runtime:** the native Continuation command's configured trusted-producer policy.
  - **Prompt:** a separate code block containing exactly one physical ASCII line:
    `git-loopy continuation reconcile --input <reconciliation-request.json> --terminal`

When there are no eligible findings, render the same header and a clean empty-state card:
`No loose ends found` and `No reportable tracker defect or open spec has exceeded the
effective grace period without native sub-issues.` This is a normal successful report,
including on an empty tracker or when the Continuation ledger is absent.

After writing the report, open it with the platform opener (`open` on macOS, `xdg-open` on
Linux, or `start` on Windows), then print the absolute file path in the terminal. End the
skill there; when the user chooses a finding, they invoke the recommendation directly
rather than routing the already-selected follow-up through `/next`.
