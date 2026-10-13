---
name: setup-git-loopy-skills
description: Run the /setup-git-loopy-skills skill.
model: claude-sonnet-5.5
reasoning-effort: low
disable-model-invocation: true
metadata:
  scorecard-context: "200K"
  scorecard-context-tier: "default"
---

<!-- model-scorecard: start -->
Call the Skill tool with "setup-git-loopy-skills" immediately and follow its instructions.
If the skill is not installed, read and follow [SKILL.md](../../skills/setup-git-loopy-skills/SKILL.md) instead.

For the recorded context, launch from the repository root with:

```bash
copilot --agent setup-git-loopy-skills --model claude-sonnet-5.5 --reasoning-effort low --context default -i 'Invoke the /setup-git-loopy-skills skill.'
```

Context metadata is advisory; selecting this agent alone does not set the context tier.
<!-- model-scorecard: end -->
