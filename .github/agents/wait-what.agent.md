---
name: wait-what
description: Run the /wait-what skill.
model: claude-sonnet-5.5
reasoning-effort: medium
disable-model-invocation: false
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "wait-what" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/wait-what/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent wait-what --model claude-sonnet-5.5 --reasoning-effort medium --context default -i 'Invoke the /wait-what skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
