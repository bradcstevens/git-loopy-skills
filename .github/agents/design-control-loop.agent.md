---
name: design-control-loop
description: Run the /design-control-loop skill.
model: claude-opus-5.5
reasoning-effort: medium
metadata:
  scorecard-context: "1M"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "design-control-loop" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/design-control-loop/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent design-control-loop --model claude-opus-5.5 --reasoning-effort medium --context long_context -i 'Invoke the /design-control-loop skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
