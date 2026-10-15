#!/usr/bin/env python3
"""Check the pinned PR format and its publication contract without network access."""

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PrGuidanceTests(unittest.TestCase):
    def test_pr_matches_upstream_except_generated_copilot_headers(self):
        # bradcstevens/mattpocock-skills at 49dd158d1076134a641b33efb035946536778336.
        upstream = {
            "SKILL.md": "ab63f1cf78647389edcd386c9427c5dfca27ed2836930c24773ffee834c19bcd",
            "CREDITS.md": "a7a087127665d7298a72280ef6e19c41ad8404523712a788c8dc3ab414bc2497",
            "agents/openai.yaml": "2295b586624db4ef546f3fd4695492f039d941a46d8a1593a702ce3ca511b8ad",
        }
        for name, digest in upstream.items():
            with self.subTest(file=name):
                content = (ROOT / "skills/pr" / name).read_bytes()
                if name == "SKILL.md":
                    opening, header, body = content.split(b"---", 2)
                    header = re.sub(rb"^(model|effort|context):[^\n]*\n", b"", header, flags=re.M)
                    content = b"---".join((opening, header, body))
                self.assertEqual(hashlib.sha256(content).hexdigest(), digest)

    def test_push_uses_pr_for_create_and_update_without_losing_chain_evidence(self):
        text = (ROOT / "skills/push/SKILL.md").read_text(encoding="utf-8")
        step = text.split("## 6. Resolve the pull request\n", 1)[1].split("\n## 7.", 1)[0]
        for required in (
            'Call the Skill tool with "pr"',
            "gh pr create",
            "gh pr edit",
            "--body-file",
            "Closes #<n>",
            "every issue the branch resolves",
            "validation results",
            "## Evidence",
            "before-and-after",
            "Do not invent",
        ):
            with self.subTest(required=required):
                self.assertIn(required, step)

    def test_catalog_links_automatic_pr_to_its_documented_format(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("| [pr](docs/pr.md) | automatic | Use when writing a PR body. |", readme)
        docs = (ROOT / "docs/pr.md").read_text(encoding="utf-8")
        for required in (
            "[Skill source](../skills/pr/SKILL.md)",
            "## What it does",
            "## The template",
            "## Common questions",
            "## It's working if",
            "## Where it fits",
            "[push](./push.md)",
        ):
            with self.subTest(required=required):
                self.assertIn(required, docs)
        self.assertNotIn("https://aihero.dev/skills-", docs)


if __name__ == "__main__":
    unittest.main()
