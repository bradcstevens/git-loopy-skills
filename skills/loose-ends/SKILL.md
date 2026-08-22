---
name: loose-ends
description: Audit the issue tracker for workflow artifacts that were started but never followed up, then open a read-only HTML report of the findings.
disable-model-invocation: true
---

# Loose Ends

`/loose-ends [--grace-days <non-negative-integer>]`

`/continuation` reports what was recorded; `/loose-ends` reports what was never
recorded. It is a user-invoked survey: it reads the issue tracker, writes one static HTML
report outside the repository, opens it, prints its absolute path, and stops.

## Non-negotiable posture

- **Read-only:** use only read operations against the tracker. Never create, edit, label,
  comment on, assign, close, reopen, or otherwise mutate an issue or pull request.
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

This tracer handles spec-shaped workflow-bearing issues. Before classifying, read the first
four Markdown headings in the `<spec-template>` in
[`../to-spec/SKILL.md`](../to-spec/SKILL.md); they are the authoritative fingerprint. The
`/to-tickets` issue template has a distinct body shape. Never use `ready-for-agent` to
distinguish the two: both specs and tickets carry that label.

`--grace-days` defaults to `7`. It accepts a non-negative integer and overrides only this
structural finding's grace period; for example, `/loose-ends --grace-days 0` exposes every
eligible finding immediately. Reject any other argument with the invocation syntax before
starting the audit.

## Audit

1. List every open issue, including its number, title, URL, body, creation time, and label
   names. Fetch all result pages; do not assume a small tracker.
2. Identify spec-shaped issues strictly from every heading in the authoritative fingerprint
   above. Do not inspect their `ready-for-agent` label to make this decision.
3. Suppress an issue before any further inspection when its labels include the exact,
   human-applied `intentional` label. The audit never adds, removes, or infers this label.
4. For each remaining spec-shaped issue, fetch all native GitHub sub-issues with the
   read-only `GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` endpoint,
   following pagination. A non-empty result means the spec was decomposed and produces no
   finding in this tracer, regardless of the child states.
5. For a spec with zero native sub-issues, fetch every page of the issue timeline
   read-only. Determine activity from the newest of:
   - a comment event;
   - a label-added or label-removed event;
   - a linked pull-request event, including a cross-reference whose source is a pull
     request.

   Do not use the issue's general `updated_at` value: it does not express this audit's
   definition of activity. If none of those events exists, use `created_at` as the idle
   baseline.
6. Calculate both durations at report-generation time:
   - **Created age:** now minus `created_at`.
   - **Idle time:** now minus the most recent qualifying activity, or `created_at` when no
     qualifying activity exists.

   Hold the finding when idle time is less than the grace period. Report it once idle time
   reaches or exceeds the grace period.
7. For each eligible issue, create a `Never decomposed` finding. Its evidence must
   enumerate the four matching headings from the authoritative fingerprint and state that
   the native sub-issue query returned zero children. Keep the finding's raw evidence in
   the report so the user can judge the classification.

## Report

Create one timestamped, static HTML file at
`$TMPDIR/loose-ends-<timestamp>.html`; if `$TMPDIR` is unset, use `/tmp` on Unix-like
systems or `%TEMP%` on Windows. Resolve it to an absolute path before writing. The HTML
must contain all finding data at generation time: it must not make tracker requests or
depend on application code after it is opened. HTML-escape every tracker-provided field
before interpolation.

Reuse the architecture survey's presentation scaffold in
[`../improve-codebase-architecture/HTML-REPORT.md`](../improve-codebase-architecture/HTML-REPORT.md)
without copying its document-shell or visual conventions. This report adds:

- Header metadata shows the repository, exact generation timestamp, the effective grace
  period, and the finding count. Do not add a generic introduction paragraph.
- Group findings by **follow-up action**, not finding class. This tracer renders
  **`/to-tickets` — decompose published specs**.

Every finding is a complete card containing:

1. Issue number, HTML-escaped title, and link.
2. `Never decomposed` badge and the evidence block.
3. Created age and idle time shown side by side; say `No qualifying activity since
   creation` when that is the idle baseline.
4. A full **Recommendation** block:
   - **Follow-up:** `/to-tickets`
   - **Interaction:** `HITL` — the decomposition needs human approval.
   - **Target:** the linked spec issue.
   - **State:** `Open; no native sub-issues; <effective grace> grace elapsed`.
   - **Context:** `Fresh session`.
   - **Runtime:** read `git-loopy config list` when available and use its
     `task-type:planning` model and effort; otherwise use
     `--model claude-opus-5 --effort xhigh --context long_context`.
   - **Prompt:** a separate code block containing exactly one physical ASCII line:
     `/to-tickets <issue-number>`

The prompt must not contain formatting, line breaks, shell quoting, or explanatory text.

When there are no eligible findings, render the same header and a clean empty-state card:
`No loose ends found` and `No open spec has exceeded the effective grace period without
native sub-issues.` This is a normal successful report, including on an empty tracker.

After writing the report, open it with the platform opener (`open` on macOS, `xdg-open` on
Linux, or `start` on Windows), then print the absolute file path in the terminal. End the
skill there; when the user chooses a finding, they invoke the recommendation directly
rather than routing the already-selected follow-up through `/next`.
