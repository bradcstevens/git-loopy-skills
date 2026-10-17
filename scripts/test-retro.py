#!/usr/bin/env python3
"""Offline checks for the pinned retrospective and its Copilot adaptations."""

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RetroTests(unittest.TestCase):
    def test_catalog_documents_user_invocation_and_copilot_sources(self):
        docs = (ROOT / "docs/retro.md").read_text(encoding="utf-8")
        for required in (
            "npx skills add bradcstevens/git-loopy-skills --skill=retro",
            "[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/retro)",
            "## What it does",
            "## When to reach for it",
            "## Where the findings land",
            "## Common questions",
            "## It's working if",
            "## Where it fits",
            "~/.copilot/session-state/<id>/events.jsonl",
            "/chronicle",
            "COPILOT_HOME",
            "~/.copilot/copilot-instructions.md",
            "~/.copilot/instructions/",
            ".github/copilot-instructions.md",
            "[next](./next.md)",
            "[writing-for-agents](./writing-for-agents.md)",
            "Nothing changes until you pick a candidate.",
        ):
            with self.subTest(required=required):
                self.assertIn(required, docs)
        for stale in ("CLAUDE.md", "~/.claude", "https://aihero.dev/skills-", "\u2014"):
            with self.subTest(stale=stale):
                self.assertNotIn(stale, docs)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(
            "| [retro](docs/retro.md) | `/retro` | Conduct a retrospective on a coding session. |",
            readme,
        )

    def test_copilot_adaptations_preserve_the_pinned_retrospective(self):
        text = (ROOT / "skills/retro/SKILL.md").read_text(encoding="utf-8")
        adaptations = (
            (
                "2. Read the primary sources for the session the user specifies. "
                "Use Copilot CLI's `~/.copilot/session-state/<id>/events.jsonl` "
                "and `/chronicle` session history. If the user doesn't specify a "
                "session, default to the current one, using its session ID from "
                "the runtime context rather than guessing from the newest log. "
                "If `COPILOT_HOME` is set, use it instead of `~/.copilot`. "
                "If the session cannot be identified or its log cannot be read, "
                "report the gap and ask for the session ID or log; do not "
                "substitute another session.",
                "2. Read the primary sources for the session the user specifies. "
                "This may mean searching through session logs on this machine. "
                "If the user doesn't specify a session, default to the current one.",
            ),
            (
                "- **Steering files**: are there any steering instructions that "
                "should be moved to coding standards (or automated checks) "
                "instead? _Use when_ `AGENTS.md` / `.github/copilot-instructions.md` "
                "in the repo, or `~/.copilot/copilot-instructions.md` and "
                "`~/.copilot/instructions/` (`*.instructions.md`) in the user's "
                "global scope, are particularly large.",
                "- **Global AGENTS.md**: are there any steering instructions that "
                "should be moved to coding standards (or automated checks) "
                "instead? _Use when_ the AGENTS.md file is particularly large - "
                "in the repo OR the user's global scope.",
            ),
            (
                "Inspect these files where they exist; steering and standards "
                "files are user-created, not guaranteed by a stock Copilot CLI install:",
                "You have access to several files in the repo:",
            ),
            (
                "- `AGENTS.md` / `.github/copilot-instructions.md`:",
                "- `CLAUDE.md`/`AGENTS.md`:",
            ),
            (
                '\nAfter presenting the candidates, ask which the user accepts. '
                'Propose only; do not edit files or install checks. Then call the '
                'Skill tool with "next", passing the accepted candidates (or none) '
                'so they can become tickets.\n',
                "",
            ),
        )
        for local, upstream in adaptations:
            with self.subTest(adaptation=local):
                self.assertEqual(text.count(local), 1)
                text = text.replace(local, upstream, 1)
        text = re.sub(r"^(model|effort|context):[^\n]*\n", "", text, flags=re.M)
        # bradcstevens/mattpocock-skills@49dd158d1076134a641b33efb035946536778336.
        self.assertEqual(
            hashlib.sha256(text.encode()).hexdigest(),
            "33fbc28568e3146f20fd908b12998bc0ab30aa4f4c87288199a40793efa94696",
        )
        metadata = (ROOT / "skills/retro/agents/openai.yaml").read_bytes()
        self.assertEqual(
            hashlib.sha256(metadata).hexdigest(),
            "cb6fb9d7e6b4be5975f41f6def1dd00a1255bad5d9b02696b124c924a8b8745c",
        )
        writing = (ROOT / "skills/writing-for-agents/SKILL.md").read_text(encoding="utf-8")
        self.assertNotIn("disable-model-invocation: true", writing)
        policy = (ROOT / "skills/writing-for-agents/agents/openai.yaml").read_text(encoding="utf-8")
        self.assertNotIn("allow_implicit_invocation: false", policy)


if __name__ == "__main__":
    unittest.main()
