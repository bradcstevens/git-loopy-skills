---
name: grill-me
description: Run the /grill-me skill.
model: gpt-6.1-terra
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "grill-me" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/grill-me/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent grill-me --model gpt-6.1-terra --reasoning-effort low --context default -i 'Invoke the /grill-me skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
