---
name: research
description: Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent.
model: gpt-6-astra
effort: medium
context: 1050K
---

Spin up a **background agent** to do the research, so you keep working while it reads.

Its job:

1. Investigate the question against **primary sources** (official docs, source code, specs, first-party APIs), not a secondary write-up of them. Follow every claim back to the source that owns it.
2. Write the findings to a single Markdown file, citing each claim's source.
3. Save it where the repo already keeps such notes; match the existing convention, and if there is none, put it somewhere sensible and say where.

Call the Skill tool with "microsoft-docs" for anything related to Microsoft technologies such as Azure or Copilot Studio.

## Owning the transition, or not

Most research is **nested**: another skill, such as `/wayfinder`, `/triage`, or `/grill-with-docs`,
needed a fact before it could decide. Nested research records nothing of its own; it hands its
durable pointers back to the skill that asked: the findings file's path, the commit SHA that
carries it, and the branch it lives on. That skill records once, for the transition it owns.

Research owns this record **only** when it was invoked directly on its own tracker ticket
(a `wayfinder:research` ticket, say) and durably resolves it. Then, and only then:

1. Commit the findings file.
2. Post the answer as a resolution comment on the ticket and **close the ticket**. That comment is
   the durable record of what this transition changed.

### When the question survives the session

Not every directly-owned ticket gets answered. If the reading is done, the partial findings are
committed and posted, and the question is still open, leave the ticket open and post the partial
findings as a comment anyway, so the next session starts from what was learnt rather than from
scratch.

At the conclusion of a `/research` session invoked directly on a ticket, call the Skill tool with "to-spec"
if the answer settles a spec, or call the Skill tool with "implement" if settled work is ready to build.
Otherwise the ticket stays open for a later `/research` session to pick up.
