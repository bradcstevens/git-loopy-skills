#!/usr/bin/env python3
"""Offline regression checks for the four Skills synced in #93."""

import hashlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ("implement", "code-review", "prototype", "research")


class SkillSyncTests(unittest.TestCase):
    def test_synced_files_have_no_em_dashes_and_keep_local_doc_entrypoints(self):
        for skill in SKILLS:
            paths = list((ROOT / "skills" / skill).rglob("*.md"))
            paths += list((ROOT / "skills" / skill).rglob("*.yaml"))
            doc = ROOT / "docs" / f"{skill}.md"
            for path in [*paths, doc]:
                with self.subTest(path=path.relative_to(ROOT)):
                    self.assertNotIn("\u2014", path.read_text(encoding="utf-8"))
            text = doc.read_text(encoding="utf-8")
            self.assertTrue(text.startswith("Quickstart:\n"))
            self.assertIn(f"npx skills add bradcstevens/git-loopy-skills --skill={skill}", text)
            self.assertIn(f"https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/{skill}", text)
            self.assertNotIn("https://aihero.dev/skills-", text)

    def test_research_and_prototype_distinguish_nested_and_owned_transitions(self):
        for skill in ("prototype", "research"):
            with self.subTest(skill=skill):
                text = (ROOT / "skills" / skill / "SKILL.md").read_text(encoding="utf-8")
                for required in (
                    "## Owning the transition, or not",
                    "**nested**",
                    "records nothing of its own",
                    "invoked directly on its own tracker ticket",
                    "**close the ticket**",
                    "### When the question survives the session",
                    "leave the ticket open",
                    'call the Skill tool with "to-spec"',
                ):
                    with self.subTest(required=required):
                        self.assertIn(required, text)
        research = (ROOT / "skills/research/SKILL.md").read_text(encoding="utf-8")
        self.assertIn('Call the Skill tool with "microsoft-docs"', research)

    def test_review_searches_all_standards_and_joins_foreground_reports(self):
        text = (ROOT / "skills/code-review/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("Search the repo for every file that documents how code should be written.", text)
        self.assertIn("When `CODING_STANDARDS.md` or `CONTRIBUTING.md` exists, it must be on the list.", text)
        self.assertIn("Issue both sub-agent calls together, in the foreground", text)
        self.assertIn('Call the Skill tool with "microsoft-code-reference"', text)
        self.assertIn('Call the Skill tool with "microsoft-docs"', text)

    def test_implementation_records_a_pushed_candidate_before_review(self):
        text = (ROOT / "skills/implement/SKILL.md").read_text(encoding="utf-8")
        for required in (
            "disable-model-invocation: false",
            "fetch it from the issue tracker and state its title before starting",
            "If the reference is ambiguous, ask.",
            'Call the Skill tool with "tdd"',
            "## Record the implementation",
            "Never widen your own authority",
            "leave the ticket open",
            "references/conflict-resolution.md",
        ):
            with self.subTest(required=required):
                self.assertIn(required, text)
        push = text.index("`git push`")
        evidence = text.index("gh issue comment", push)
        review = text.index('call the Skill tool with "code-review"', evidence)
        self.assertLess(push, evidence)
        self.assertLess(evidence, review)
        self.assertIn("head you just pushed", text[review:])

    def test_prototype_guides_match_the_upstream_pin(self):
        # bradcstevens/mattpocock-skills@49dd158d1076134a641b33efb035946536778336
        for guide, digest in (
            ("UI.md", "723211e878acbc7b6ff09755263f3295cde724ba902ff0064da41eed51d45ad3"),
            ("LOGIC.md", "f61c7d249e786a79ef289018901c348271e1798dd0b0bc5607b5c6f4d4a01ab9"),
        ):
            with self.subTest(guide=guide):
                data = (ROOT / "skills/prototype" / guide).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
        self.assertNotEqual(
            (ROOT / "skills/prototype/UI.md").read_bytes(),
            (ROOT / "skills/prototype/LOGIC.md").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()
