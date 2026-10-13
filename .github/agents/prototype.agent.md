---
name: prototype
description: Run the /prototype skill.
model: gpt-6-astra
reasoning-effort: medium
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "prototype" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/prototype/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent prototype --model gpt-6-astra --reasoning-effort medium --context default -i 'Invoke the /prototype skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
