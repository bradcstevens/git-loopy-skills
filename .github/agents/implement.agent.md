---
name: implement
description: Run the /implement skill.
model: gpt-6.1-terra
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "implement" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/implement/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent implement --model gpt-6.1-terra --reasoning-effort low --context default -i 'Invoke the /implement skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
