#!/usr/bin/env python3
"""Offline checks of the portable handoff skill's published contract."""

import hashlib
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[1]


class ToHandoffTests(unittest.TestCase):
    def test_skill_matches_pinned_upstream_except_name_and_generated_runtime(self):
        text = (REPO / "skills/to-handoff/SKILL.md").read_text()
        normalized = re.sub(r"^(model|effort|context):.*\n", "", text, flags=re.M)
        normalized = normalized.replace("name: to-handoff\n", "name: handoff\n", 1)
        # skills/productivity/handoff/SKILL.md at upstream 49dd158d1076134a641b33efb035946536778336.
        self.assertEqual(
            hashlib.sha256(normalized.encode()).hexdigest(),
            "4cbb043950dad2ffd3662ff1a5a0b51ae676004b5cae10e3787e8ee7a4ee69d3",
        )

    def test_portable_document_is_discoverable_and_only_user_invoked(self):
        metadata = (REPO / "skills/to-handoff/agents/openai.yaml").read_text()
        self.assertEqual(
            metadata,
            'interface:\n  display_name: "To Handoff"\n'
            '  short_description: "Compact a conversation into a handoff"\n'
            'policy:\n  allow_implicit_invocation: false\n',
        )
        agent = (REPO / ".github/agents/to-handoff.agent.md").read_text()
        self.assertIn("disable-model-invocation: true\n", agent)
        self.assertIn("skills/to-handoff/SKILL.md", agent)
        readme = (REPO / "README.md").read_text()
        self.assertIn("| [to-handoff](docs/to-handoff.md) | `/to-handoff` |", readme)
        docs = (REPO / "docs/to-handoff.md").read_text()
        self.assertIn("npx skills add bradcstevens/git-loopy-skills --skill=to-handoff", docs)
        self.assertIn("## What travels, and what doesn't", docs)
        self.assertIn("## It's working if", docs)
        self.assertNotIn("`/handoff` writes", docs)
        self.assertIn("[/to-handoff](./to-handoff.md)", (REPO / "docs/handoff.md").read_text())


if __name__ == "__main__":
    unittest.main()
