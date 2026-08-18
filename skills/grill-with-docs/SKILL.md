---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

Run a `/grilling` session, using the `/domain-modeling` skill.

## Record the decision

A grilling session that lands a decision — a glossary term pinned, an ADR written, a question
answered — has made a durable workflow transition, and this skill owns it. Record it so the next
session reads the decision rather than re-litigating it.

**Only record after the decision is durable.** In order:

1. Land the decision where it lives: the ADR under `docs/adr/` or the `CONTEXT.md` entry,
   committed.
2. Post one resolution comment on the issue or ticket being grilled, gisting the decision and
   linking the ADR.

The ADR is the decision's grounds, not a link in prose: a reader who cannot see the ADR cannot
judge whether the question still stands, so name its commit in the comment.

**Never answer your own grilling questions.** A decision belongs to the human being grilled; an
agent that settles an open question on their behalf has broken the whole point of the skill.

When the grilled issue has no open question left, close it. When one remains, leave it open and
say in the comment which question is still live, so the next session knows where to resume.

A grilling nested inside another skill's session — `/triage` step 4, a `/wayfinder` grilling
ticket — is not a transition of its own. It records nothing separately; it hands its durable
pointers (the resolution comment, the ADR commit SHA) back to the skill that owns the transition.

At the conclusion of a `/grilling` session, run `/next`.
