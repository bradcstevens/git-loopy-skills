Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=design-control-loop
```

```text
/design-control-loop
```

[Skill source](../skills/design-control-loop/SKILL.md)

## What it does

`design-control-loop` interviews you, agrees a codebase-specific agentic control
loop, and builds it as locally runnable components plus a recurring workflow.
The goal is small, low-risk, reviewable changes that drive a property toward a
target despite other work changing the repository.

The skill reads your repository before asking questions. Existing CI, package
managers, validation, analysis tools, project skills, agent instructions, and
loop conventions shape its proposals. The
[worked example](../skills/design-control-loop/references/example-control-loop.md)
illustrates the shape of a loop; it is not a React or Bun blueprint to reproduce
in every codebase.

## When to reach for it

Use it when a property needs repeated maintenance or gradual improvement:
migrating an old pattern, reducing findings, improving a scoped quality measure,
or keeping an invariant healthy while teammates ship changes. Bring the problem
and boundaries, not necessarily a finished automation design.

For one settled piece of work, use [implement](./implement.md). For an unsettled
goal that first needs a spec, use [grilling](./grilling.md) and
[to-spec](./to-spec.md). This skill is specifically for designing and building
the feedback loop that chooses and delivers successive increments.

## The loop you design together

The [taxonomy](../skills/design-control-loop/references/control-loop-taxonomy.md)
gives the interview a shared vocabulary:

| Component | Decision |
| --- | --- |
| Set point | The desired invariant, threshold, or direction, plus read/change scope. |
| Sensor | How to measure the current state and gap repeatably using suitable repo tooling. |
| Controller | Which target to choose next, how to prioritize, and how much is one reviewable increment. |
| Actuator | A headless Copilot CLI agent, a task-specific skill, golden patterns, and validation. |
| Disturbances | Outside changes to tolerate; optionally a dampener to prevent regressions. |

A focused [grilling](./grilling.md) interview settles the set point and scope.
The remaining decisions cover measurement trade-offs, selection policy,
credentials, model/effort/context, optional spend caps, and validation. The skill
captures the agreed design in writing before building. Sensor, controller, and
actuator can be fused when that matches the design; it does not manufacture
separate stages merely to match a diagram.

## What it builds

The target repository gets version-controlled sensor and controller commands, a
task-specific actuator skill under `.github/skills/<skill-name>/` (or the repo's
existing `.agents/skills/` convention), a recurring workflow, and a standing
memory/feedback file. A loop still being tuned can start as a personal skill.
The generated skill records the golden patterns and judgement needed to run
unattended, with a tailored response template whose final output becomes the PR
body.

Each component must run locally before CI orchestrates it: inspect real sensor
output, check the controller's selected increment, and run the actuator on that
selection with the agreed validation. The
[runner reference](../skills/design-control-loop/references/agent-runner-templates.md)
covers local and CI execution, authentication, billing, and output extraction.
GitHub Actions is the default, not a requirement to replace the repository's CI.

The workflow adds cadence, manual dispatch, PR metadata, feedback loading, and
flow control. The recommended bound is **one open PR per loop**: scheduled runs
no-op when it is met, while manual dispatch bypasses the check and can supply a
`target_path` override. The skill validates YAML and referenced paths, dry-runs
the workflow, and reviews a produced PR before calling the loop complete.

## Common questions

**Is this a fully automatic design exercise?** No. You choose the target,
boundaries, reviewable batch, golden patterns, authentication, and validation
with the agent. The written design is the cheap correction point before build.

**Do I need a new analysis tool?** Not necessarily. Existing lint, tests,
typechecks, structural searches, telemetry, custom scripts, or agent inspection
can be sensors. Stability, cost, repeatability, and disablement risks are
trade-offs to discuss, not a mandatory tool checklist.

**How do reviewers change future behavior?** Standing feedback lives in a
version-controlled memory file loaded into the actuator after the controller on
each run. Where `/iterate` is enabled, an authorized maintainer's PR comment is
routed by the originating workflow's hidden marker; that workflow updates the
existing PR and distills durable feedback into memory. One-off PR details do not
become standing rules.

**Does it stop the problem getting worse between runs?** Only if you choose a
dampener. The skill offers a regression gate comparing measurement with a
baseline; it is optional and can be advisory or blocking as agreed.

**What credentials and budget does CI use?** The interview chooses the built-in
`GITHUB_TOKEN` with `copilot-requests: write` or a `COPILOT_GITHUB_TOKEN` PAT.
Billing and policy prerequisites differ by repository ownership and token choice.
An optional per-run AI-credit cap bounds spend; the runner reference explains
those choices rather than assuming a secret or budget.

## It's working if

- The written design names the target, scope, components, validation, and
  disturbances, with optional dampening decided explicitly.
- Sensor, controller, and actuator run locally and produce sensible results.
- The generated skill is sufficient for unattended work, follows repo patterns,
  and defines the reviewer's required PR output.
- Workflow YAML parses, all referenced paths exist, and scheduled work respects
  the agreed open-PR bound.
- Standing feedback survives runs, enabled iteration updates the existing PR,
  and the loop has produced at least one reviewed PR.

## Where it fits

This skill builds a recurring driver around the git-loopy toolchain. The
actuator can use [implement](./implement.md), [code-review](./code-review.md),
and [next](./next.md); issue-tracker conventions and triage labels remain the
human steering surface. It is not a replacement for those transitions.
Once output is consistently good, tune cadence or batch size deliberately rather
than producing PRs faster than humans can review them.
