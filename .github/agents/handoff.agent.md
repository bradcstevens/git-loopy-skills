---
name: handoff
description: Run the /handoff skill.
model: claude-sonnet-5.5
reasoning-effort: low
metadata:
  scorecard-context: "936K"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "handoff" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/handoff/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent handoff --model claude-sonnet-5.5 --reasoning-effort low --context long_context -i 'Invoke the /handoff skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
