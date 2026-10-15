---
name: research
description: Run the /research skill.
model: gpt-6-astra
reasoning-effort: medium
metadata:
  scorecard-context: "1050K"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "research" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/research/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent research --model gpt-6-astra --reasoning-effort medium --context long_context -i 'Invoke the /research skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
