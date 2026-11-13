---
name: loop-me
description: Run the /loop-me skill.
model: gpt-6-astra
reasoning-effort: medium
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "loop-me" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/loop-me/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent loop-me --model gpt-6-astra --reasoning-effort medium --context default -i 'Invoke the /loop-me skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
