# Skill selection

Use the route table in `SKILL.md` for engineering work. This reference resolves
wrapper choices and standalone requests; return one recommendation through the
same runtime, context, and output steps.

## Interview wrappers

Choose `/grill-with-docs` in a working directory: its interview retains domain
language in `CONTEXT.md` and decisions in ADRs. Choose `/grill-me` without a
repository: the interview is stateless. Both run `/grilling`; recommend that
primitive directly only when the user wants the interview without either wrapper.

## Build scope

A multi-session build needs `/to-spec` and `/to-tickets` before `/implement`.
Tickets carry their blocking edges and are worked blockers-first; each
implementation starts from its self-contained ticket in fresh context. A small,
agreed change can go straight to `/implement` in the current context.

Keep interview, spec, and ticket synthesis together while the next phase fits
the remaining smart zone. At a phase boundary where it no longer fits, apply
`PHASE-BOUNDARIES.md`; its ordered tree owns the context transition.

## Standalone branches

| Desired outcome | Recommend | Scope |
| --- | --- | --- |
| Publish completed, integrated work as a project-versioned GitHub release | `/release` | Follow the target project's release gates; user-invoked, outside the delivery chain. |
| Perform a step only a human can take | `/wizard` | Generate an interactive bash wizard for provisioning, credentials, dashboards, or cutovers. Agent-executable work stays with the agent. |
| Re-pitch the last message with its missing context | `/wait-what` | Stay in this conversation and use the project's domain vocabulary. |
| Learn a concept across sessions | `/teach` | Use the current directory as the learning workspace. |
| Write or revise a skill, `AGENTS.md`, or a pointed-at agent document | `/writing-for-agents` | Apply the agent-writing reference; disclose skill mechanics only when writing a skill. |
| Reconcile git-loopy's pinned SDK model roster and one configuration scope | `/sync-model-roster` | Repair the roster first, then align model, effort, context, and task-route capabilities. |
| Research licensed Copilot models and align their routing and enforcement | `/model-fit` | Synchronize Copilot built-ins and git-loopy; `research-only` leaves configuration unchanged. |

Research, prototypes, questionnaires, vocabulary work, and conflict resolution
also have standalone entry points in the route table. Select them for the
specific unresolved gate, even when no broader delivery flow is active.

User-invoked skills are recommendations for the human to invoke. Their presence
in this map gives them no implicit invocation or chain-spawn permission.
