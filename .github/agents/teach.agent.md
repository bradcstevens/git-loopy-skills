---
name: teach
description: Run the /teach skill.
model: gpt-6-astra
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "teach" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/teach/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent teach --model gpt-6-astra --reasoning-effort low --context default -i 'Invoke the /teach skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
