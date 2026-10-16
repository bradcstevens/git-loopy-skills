Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=chief-of-staff
```

```bash
npx skills update chief-of-staff
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/chief-of-staff)

## What it does

`chief-of-staff` pursues one long-running goal in a single Copilot CLI session. It acts as the Directly Responsible Individual for that goal, keeping the strategic view while background subagents do the work.

It thinks on two tracks at once: **tactical**, completing the immediate task, and **strategic**, improving the environment so the next task goes better. Finishing a task is not the whole outcome. Better checks, clearer interfaces, and access to the right information should make future work easier too.

The skill is still in progress upstream. This port follows the pinned revision; upstream has no docs page for it, so this page describes the Copilot adaptation.

## When to reach for it

You invoke this by typing `/chief-of-staff`. The agent won't reach for it on its own. Give it the goal and pointers to the material it needs, such as a spec, previous commits, or research notes.

Reach for it when the goal needs sustained coordination rather than a single answer: several related tasks, recurring checks, or an environment that keeps making the same work difficult. The coordinating session stays available for dialogue while agents work in the background.

It is not a detached runner or a promise that work survives closing the session. For a bounded task that needs no ongoing coordination, use the skill for that task directly.

## How it works

All task work goes to Copilot CLI background `task` agents using `mode: "background"`. The chief of staff protects its own context window for the goal, decisions, and dialogue with you.

Communication stays sparse through **context pointers**: references to research notes, commits, and other source material that an agent can read. Instead of copying a long report into every message, pass the pointer and enough context to explain why it matters. Results should point back to the evidence too.

Before feature work, the strategic view asks how to improve three things:

| Principle | What it means in practice |
| --- | --- |
| **Pit of success** | Constrained APIs and functions, lint rules that force correctness, and `CODING_STANDARDS.md` guidance for reviewers |
| **Data sources** | Logs from relevant processes, access to test databases, and browser access when the work needs it |
| **No workarounds** | Fix deviations from established conventions proactively instead of bypassing the process with a one-off hack |

Every user message is another opportunity to look for those improvements. The goal is a better environment, not a growing list of instructions that nobody enforces.

When recurring work would help the goal, the skill suggests Copilot CLI `/every` schedules. These are suggestions, not schedules installed automatically. The skill does not prescribe a cadence or turn this session into a persistent service.

## Where it fits

`chief-of-staff` is a user-driven coordinator, not another automatically spawned route in the git-loopy chain.

[loop-me](./loop-me.md) designs recurring workflows. `chief-of-staff` instead carries one goal through a long session, delegating tasks and suggesting schedules where they help. [handoff](./handoff.md) launches a separate background run when work needs to leave the current session; this skill keeps its agents inside the coordinating session.

[codebase-design](./codebase-design.md) provides vocabulary for improving interfaces and boundaries. [code-review](./code-review.md) checks the resulting work and applies the review standards that help build the pit of success. When you are unsure which skill fits the current gate, [next](./next.md) routes you.
