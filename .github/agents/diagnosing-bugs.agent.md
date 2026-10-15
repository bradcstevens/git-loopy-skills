---
name: diagnosing-bugs
description: Run the /diagnosing-bugs skill.
model: claude-opus-5.5
reasoning-effort: medium
metadata:
  scorecard-context: "1M"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "diagnosing-bugs" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/diagnosing-bugs/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent diagnosing-bugs --model claude-opus-5.5 --reasoning-effort medium --context long_context -i 'Invoke the /diagnosing-bugs skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
