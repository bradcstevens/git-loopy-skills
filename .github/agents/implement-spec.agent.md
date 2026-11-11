---
name: implement-spec
description: Run the /implement-spec skill.
model: claude-opus-5.5
reasoning-effort: xhigh
disable-model-invocation: true
metadata:
  scorecard-context: "1M"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "implement-spec" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/implement-spec/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent implement-spec --model claude-opus-5.5 --reasoning-effort xhigh --context long_context -i 'Invoke the /implement-spec skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
