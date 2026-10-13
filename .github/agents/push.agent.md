---
name: push
description: Run the /push skill.
model: claude-sonnet-5.5
reasoning-effort: low
disable-model-invocation: false
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "push" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/push/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent push --model claude-sonnet-5.5 --reasoning-effort low --context default -i 'Invoke the /push skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
