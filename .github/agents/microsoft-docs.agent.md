---
name: microsoft-docs
description: Run the /microsoft-docs skill.
model: gpt-6-astra
reasoning-effort: medium
metadata:
  scorecard-context: "1050K"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "microsoft-docs" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/microsoft-docs/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent microsoft-docs --model gpt-6-astra --reasoning-effort medium --context long_context -i 'Invoke the /microsoft-docs skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
