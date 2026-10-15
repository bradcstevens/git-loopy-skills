---
name: to-handoff
description: Run the /to-handoff skill.
model: claude-sonnet-5.5
reasoning-effort: medium
disable-model-invocation: true
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "to-handoff" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/to-handoff/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent to-handoff --model claude-sonnet-5.5 --reasoning-effort medium --context default -i 'Invoke the /to-handoff skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
