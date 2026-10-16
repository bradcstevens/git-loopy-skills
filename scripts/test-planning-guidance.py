#!/usr/bin/env python3
"""Offline contracts for the independently installed planning Skills."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PlanningGuidanceTests(unittest.TestCase):
    def skill(self, name):
        return (ROOT / "skills" / name / "SKILL.md").read_text(encoding="utf-8")

    def test_grilling_loads_both_skills_and_records_before_routing(self):
        text = self.skill("grill-with-docs")
        self.assertIn('Call the Skill tool twice, for "grilling" and "domain-modeling".', text)
        self.assertIn("## Record the decision", text)
        self.assertIn("GLOSSARY.md", text)
        self.assertIn("**Never answer your own grilling questions.**", text)
        self.assertIn('Call the Skill tool with "next"', text)
        self.assertLess(text.index("## Record the decision"), text.index('Call the Skill tool with "next"'))

    def test_spec_is_a_durable_planning_document_before_decomposition(self):
        text = self.skill("to-spec")
        publication = text.split("3. Write the spec", 1)[1].split("\n\n", 1)[0]
        self.assertIn("`ready-for-human`", publication)
        self.assertIn("Never apply `ready-for-agent`", publication)
        self.assertIn("disable-model-invocation: false", text)
        self.assertIn("## Record the specification", text)
        self.assertIn("gh issue comment <spec-issue>", text)
        self.assertLess(text.index("## Record the specification"), text.index("## Decomposition handoff"))
        self.assertIn("git-loopy plan <spec>", text)
        self.assertIn('Call the Skill tool with "to-tickets"', text)
        agent = (ROOT / ".github/agents/to-spec.agent.md").read_text()
        self.assertIn("`ready-for-human`", agent)
        self.assertNotIn("pinned to high", agent)

    def test_ticket_graph_and_label_rules_have_one_owner(self):
        text = self.skill("to-tickets")
        for rule in (
            "sub-issue", "/sub_issues", "dependencies/blocked_by",
            "exactly one `task-type:` label", "`ready-for-agent`",
            "Decide independently whether to add the configured `parallel-safe` marker",
            "Work the **frontier**", "Do NOT close or modify any parent issue",
        ):
            with self.subTest(rule=rule):
                self.assertEqual(text.count(rule), 1, rule)
        self.assertIn("Omit this section when blockers were set as native edges.", text)
        self.assertIn("disable-model-invocation: false", text)
        self.assertIn("## 6. Record the decomposition", text)
        self.assertIn("**Only record once the whole approved graph is durable.**", text)
        self.assertIn("gh issue comment <spec-issue>", text)
        self.assertIn('Call the Skill tool with "next"', text)
        self.assertNotIn("with `/implement`", text)
        self.assertNotIn("gh issue close <spec-issue>", text)

    def test_synced_pages_keep_upstream_guidance_and_local_entry_points(self):
        for name in ("grill-with-docs", "to-spec", "to-tickets"):
            with self.subTest(skill=name):
                page = (ROOT / "docs" / f"{name}.md").read_text(encoding="utf-8")
                self.assertTrue(page.startswith("Quickstart:\n"))
                self.assertIn(f"--skill={name}", page)
                self.assertIn(f"/tree/main/skills/{name})", page)
                self.assertIn("## Common questions", page)
                self.assertNotIn("aihero.dev/skills-", page)
                for target in re.findall(r"\]\(([^)]+)\)", page):
                    if target.startswith(("./", "../")):
                        self.assertRegex(target, r"^\./[^/]+\.md$")
                        self.assertTrue((ROOT / "docs" / target).is_file(), target)
                self.assertNotIn("CONTEXT-MAP.md", page)
                self.assertNotIn("\u2014", page)
                self.assertNotIn("\u2014", self.skill(name))
        agent = (ROOT / ".github/agents/to-spec.agent.md").read_text()
        self.assertNotIn("\u2014", agent)


if __name__ == "__main__":
    unittest.main()
