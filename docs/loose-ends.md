Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=loose-ends
```

```bash
npx skills update loose-ends
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/loose-ends)

## What it does

`loose-ends` is a read-only tracker survey for workflow-bearing specs that were published but never
decomposed. It writes one self-contained HTML report to the OS temp directory, opens it, prints its
absolute path, and leaves both the tracker and repository unchanged.

The current tracer follows one finding class: an open issue with the exact spec body shape and zero
native sub-issues. It ignores `intentional` issues, holds recent activity for a seven-day grace
period by default, and reports both created age and qualifying idle time. Pass
`/loose-ends --grace-days 0` to inspect every eligible spec immediately.

## When to reach for it

You invoke this by typing `/loose-ends` — the agent will not launch a whole-tracker sweep on its
own. Reach for it when you want to find published specs whose decomposition may have been dropped,
or as a periodic tracker hygiene check.

An empty report is a successful result: no open spec has exceeded the effective grace period without
native sub-issues. The report never creates labels, comments, or tickets; `intentional` remains a
human assertion that suppresses its findings.

## The report

Each `Never decomposed` card retains the raw classification evidence: the four spec headings and a
zero-child native sub-issue query. It shows the issue, created age, idle time, effective grace
period, and a complete recommendation for `/to-tickets`.

The report is static and self-contained. All tracker-provided data is escaped before it is
interpolated, so the file remains useful after it opens without making further tracker requests.

## Where it fits

`/continuation` reports what was recorded; `/loose-ends` reports what was never recorded. The two
surveys are complementary, not interchangeable: a published spec with no later decomposition leaves
no continuation record for `/continuation` to read.

Unlike a router, `/loose-ends` does not send its already-selected finding through [`next`](./next.md).
The user invokes the `/to-tickets` recommendation directly from the report, where the required human
approval makes the follow-up HITL. [`to-tickets`](./to-tickets.md) then creates the native
sub-issues that make the finding disappear on a future survey.
