---
name: writing-for-agents
description: Run the /writing-for-agents skill.
model: claude-opus-5.5
reasoning-effort: xhigh
metadata:
  scorecard-context: "1M"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "writing-for-agents" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/writing-for-agents/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent writing-for-agents --model claude-opus-5.5 --reasoning-effort xhigh --context long_context -i 'Invoke the /writing-for-agents skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
