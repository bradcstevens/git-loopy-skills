---
name: create-readme
description: Run the /create-readme skill.
model: gpt-6.1-terra
reasoning-effort: low
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "create-readme" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/create-readme/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent create-readme --model gpt-6.1-terra --reasoning-effort low --context default -i 'Invoke the /create-readme skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
