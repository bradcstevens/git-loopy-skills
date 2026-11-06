---
name: retro
description: Run the /retro skill.
model: gpt-6-astra
reasoning-effort: medium
disable-model-invocation: true
metadata:
  scorecard-context: "1050K"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "retro" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/retro/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent retro --model gpt-6-astra --reasoning-effort medium --context long_context -i 'Invoke the /retro skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
