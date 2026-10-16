#!/usr/bin/env python3
"""Offline contract for the user-invoked chief-of-staff Skill."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ChiefOfStaffTests(unittest.TestCase):
    def test_user_invoked_coordinator_uses_copilot_background_agents(self):
        skill = ROOT / "skills/chief-of-staff"
        text = (skill / "SKILL.md").read_text(encoding="utf-8")
        frontmatter = text.split("---", 2)[1]
        self.assertIn("\ndisable-model-invocation: true\n", frontmatter)
        metadata = (skill / "agents/openai.yaml").read_text(encoding="utf-8")
        self.assertIn("  allow_implicit_invocation: false\n", metadata)
        for instruction in (
            "Tactical: how do I complete the immediate task?",
            "Strategic: how do I modify the environment",
            "Copilot CLI `/every`",
            "suggest recurring schedules",
            "All work should be done in subagents.",
            "Copilot CLI background `task` agents",
            "`mode: \"background\"`",
            "**context pointers**",
            "**pit of success**",
            "**data sources**",
            '**"no workarounds"**',
        ):
            with self.subTest(instruction=instruction):
                self.assertIn(instruction, text)

    def test_documented_slash_command_is_published_in_the_index(self):
        docs = (ROOT / "docs/chief-of-staff.md").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^## (.+)$", docs, re.MULTILINE), [
            "What it does",
            "When to reach for it",
            "How it works",
            "Where it fits",
        ])
        self.assertIn("--skill=chief-of-staff", docs)
        self.assertIn("`/every`", docs)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(
            "| [chief-of-staff](docs/chief-of-staff.md) | `/chief-of-staff` |",
            readme,
        )


if __name__ == "__main__":
    unittest.main()
