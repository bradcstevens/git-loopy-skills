---
name: sync-branches
description: Run the /sync-branches skill.
model: gpt-6.1-terra
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "272K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "sync-branches" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/sync-branches/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent sync-branches --model gpt-6.1-terra --reasoning-effort low --context default -i 'Invoke the /sync-branches skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
