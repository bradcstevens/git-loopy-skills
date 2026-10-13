---
name: jev-ultrafast
description: Run the /jev-ultrafast skill.
model: claude-sonnet-5.5
reasoning-effort: low
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "jev-ultrafast" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/jev-ultrafast/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent jev-ultrafast --model claude-sonnet-5.5 --reasoning-effort low --context default -i 'Invoke the /jev-ultrafast skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
