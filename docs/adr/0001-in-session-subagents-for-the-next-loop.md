# In-session subagents carry the `/next` loop, not detached processes

`/next` auto-spawns its allowlisted routes as **in-session subagents** (the `task` tool), even
though `/handoff` deliberately launches detached `copilot -p` processes for the same kind of work.
We chose in-session because only a subagent emits a `subagentStop` hook event, and that event can
block and force continuation — which is what makes "always run `/next` when a run finishes" a
guarantee rather than a hope. A detached process has no such signal back into the session that
launched it.

## Consequences

- **Subagents cannot be despawned.** The CLI exposes no kill, stop, or release API. A finished
  background subagent parks as `idle` and stays resident until the parent session exits. We treat
  completion as a state in the spawn ledger rather than a process lifecycle, and accept the clutter.
- **`general-purpose` is unusable for this.** It emits no `subagentStart`/`subagentStop`. Each
  allowlisted route is therefore spawned as a custom YAML agent, which does emit.
- **The loop dies with its session.** In-session subagents do not survive the parent. Work that must
  outlive the session still belongs to `/handoff`, which is why that skill stays separate rather
  than being absorbed.

## Considered options

**Detached `copilot -p` processes.** They exit cleanly with known exit codes, survive the parent
session, and would have satisfied the despawn requirement outright. Rejected because the completion
signal only reaches a shell, not the session holding the routing context — re-entering `/next`
would have meant a detached process spawning further detached processes in a session nobody is
watching.

## This reverses a standing ban on delegating `/push`

`/push` carries `disable-model-invocation: true`, and `docs/subagents/skill-to-subagent-map.md`
listed both `/push` and `/resolving-merge-conflicts` under "skills that must not be delegated",
on the grounds that they act on the working tree and want a human on the approval. The chain
automates both anyway, and that reversal is deliberate.

The ban was written when nothing could tell a safe publication from a risky one, so refusing all of
them was the only available answer. The spawn gate now requires a route to be **AFK-safe** as well
as allowlisted, and AFK-safe already means the target is fully specified and needs no further human
judgment. That is a narrower and better-evidenced guarantee than the blanket ban it replaces, so
the ban is lifted rather than worked around.

