---
name: model-scorecard
description: Run the /model-scorecard skill.
model: gpt-6.1-sol
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "model-scorecard" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/model-scorecard/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent model-scorecard --model gpt-6.1-sol --reasoning-effort low --context default -i 'Invoke the /model-scorecard skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
