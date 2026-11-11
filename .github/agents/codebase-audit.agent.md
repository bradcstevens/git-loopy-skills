---
name: codebase-audit
description: Run the /codebase-audit skill.
model: claude-opus-5.5
reasoning-effort: xhigh
metadata:
  scorecard-context: "1050K"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "codebase-audit" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/codebase-audit/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent codebase-audit --model claude-opus-5.5 --reasoning-effort xhigh --context long_context -i 'Invoke the /codebase-audit skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
