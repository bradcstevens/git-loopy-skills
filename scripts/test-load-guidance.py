#!/usr/bin/env python3
"""Keep shared-host load bounds in each independently installed Skill."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ("diagnosing-bugs", "to-tickets", "to-spec")


class LoadGuidanceTests(unittest.TestCase):
    def text(self, skill):
        return (ROOT / "skills" / skill / "SKILL.md").read_text(encoding="utf-8")

    def test_each_skill_carries_the_shared_host_bounds(self):
        for skill in SKILLS:
            with self.subTest(skill=skill):
                text = self.text(skill)
                for required in (
                    "taskpolicy -c utility <command>",
                    "`nice` is not a substitute",
                    "at most about 2x the logical CPUs",
                    "child workers",
                    "wall-clock cap",
                    "otherwise 30 minutes",
                    "**inconclusive**, never",
                    "inherited priority",
                    "record observations and stop" if skill != "diagnosing-bugs"
                    else "Record the observations and stop",
                    "pgrep",
                    "ownership",
                    "PID",
                ):
                    with self.subTest(required=required):
                        self.assertIn(required, text)

    def test_ordinary_feedback_loops_are_not_capped(self):
        for skill in SKILLS:
            with self.subTest(skill=skill):
                text = self.text(skill)
                self.assertIn("Ordinary feedback loops declared in `AGENTS.md`", text)
                self.assertIn("not deliberate load", text)
                self.assertIn("Run's Host yield policy", text)
                self.assertIn("run to completion", text)
                self.assertIn("cleanup", text)

    def test_diagnosis_does_not_demand_unbounded_escalation(self):
        text = self.text("diagnosing-bugs")
        self.assertNotIn("keep raising the rate until", text)
        self.assertNotIn("Loop the trigger 100", text)
        self.assertIn("Never escalate beyond these bounds", text)
        self.assertIn("All processes started by the diagnosis are reaped", text)

    def test_planning_requires_bounds_before_publication(self):
        for skill in ("to-spec", "to-tickets"):
            with self.subTest(skill=skill):
                text = self.text(skill)
                self.assertIn("Any acceptance criterion", text)
                self.assertIn("Reject or rewrite an unbounded load criterion", text)
                self.assertIn("preserve tighter bounds", text)
                self.assertIn("No escalation beyond those bounds", text)
        self.assertIn("in the ticket itself", self.text("to-tickets"))
        self.assertIn("carried into each resulting ticket", self.text("to-spec"))


if __name__ == "__main__":
    unittest.main()
