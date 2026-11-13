---
name: chief-of-staff
description: Run the /chief-of-staff skill.
model: auto
reasoning-effort: max
metadata:
  scorecard-context: "auto"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "chief-of-staff" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/chief-of-staff/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent chief-of-staff --model auto --reasoning-effort max --context default -i 'Invoke the /chief-of-staff skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
