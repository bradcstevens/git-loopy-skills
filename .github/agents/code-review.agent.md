---
name: code-review
description: Run the /code-review skill.
model: claude-opus-5.5
reasoning-effort: medium
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "code-review" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/code-review/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent code-review --model claude-opus-5.5 --reasoning-effort medium --context default -i 'Invoke the /code-review skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
