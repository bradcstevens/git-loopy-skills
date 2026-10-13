---
name: triage
description: Run the /triage skill.
model: claude-opus-5.5
reasoning-effort: medium
disable-model-invocation: true
metadata:
  scorecard-context: "1M"
  scorecard-context-tier: "long_context"
---

<!-- model-scorecard: start -->
Call the Skill tool with "triage" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/triage/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent triage --model claude-opus-5.5 --reasoning-effort medium --context long_context -i 'Invoke the /triage skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
