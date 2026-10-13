---
name: show-me
description: Run the /show-me skill.
model: claude-sonnet-5.5
reasoning-effort: medium
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "show-me" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/show-me/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent show-me --model claude-sonnet-5.5 --reasoning-effort medium --context default -i 'Invoke the /show-me skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
