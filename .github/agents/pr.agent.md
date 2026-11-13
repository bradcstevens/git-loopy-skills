---
name: pr
description: Run the /pr skill.
model: gpt-6.1-terra
reasoning-effort: low
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "pr" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/pr/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent pr --model gpt-6.1-terra --reasoning-effort low --context default -i 'Invoke the /pr skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
