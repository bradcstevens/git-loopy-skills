---
name: tdd
description: Run the /tdd skill.
model: gpt-6-astra
reasoning-effort: medium
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "tdd" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/tdd/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent tdd --model gpt-6-astra --reasoning-effort medium --context default -i 'Invoke the /tdd skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
