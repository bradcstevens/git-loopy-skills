#!/usr/bin/env python3
"""Offline contract checks for the user-invoked spec orchestrator."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills/implement-spec/SKILL.md"


class ImplementSpecTests(unittest.TestCase):
    def test_copilot_agents_integrate_the_ready_frontier_serially(self):
        text = SKILL.read_text(encoding="utf-8")
        for required in (
            "Implementer, merger and exploration subagents",
            "Copilot CLI `task` tool",
            '`mode: "background"`',
            "agent type that can write files",
            "at most one merger",
            "`git merge --no-ff`",
            "merged into the integration branch",
            "not the tracker's open blocked-by count",
            "Do not reset",
            "calls the Skill tool with `tdd`",
        ):
            with self.subTest(required=required):
                self.assertTrue(required in text, f"Missing guidance: {required}")

    def test_evidence_review_and_cleanup_own_the_transition(self):
        text = SKILL.read_text(encoding="utf-8")
        for required in (
            "per-ticket evidence comment",
            "full integration merge commit SHA",
            "one evidence comment on the spec",
            "reviewed head SHA",
            "read-only",
            "Do not start another broad review",
            "remove every worktree and branch it created",
            "merger, exploration and review-fix worktrees",
            "Never force-remove dirty worktrees",
            "sole copy of the work",
            "retained worktree",
            "Call the Skill tool with `next`",
        ):
            with self.subTest(required=required):
                self.assertTrue(required in text, f"Missing guidance: {required}")

    def test_user_invoked_skill_is_documented_and_indexed(self):
        frontmatter = SKILL.read_text(encoding="utf-8").split("---", 2)[1]
        self.assertIn("disable-model-invocation: true", frontmatter.splitlines())
        metadata = (SKILL.parent / "agents/openai.yaml").read_text(encoding="utf-8")
        self.assertIn("  allow_implicit_invocation: false", metadata.splitlines())
        doc = ROOT / "docs/implement-spec.md"
        self.assertTrue(doc.is_file(), "Missing upstream-derived docs page")
        text = doc.read_text(encoding="utf-8")
        for required in (
            "--skill=implement-spec", "## Common questions", "## It's working if",
            "./setup-git-loopy-skills.md", "evidence comment", "cleanup", "/next",
        ):
            self.assertTrue(required in text, f"Missing docs guidance: {required}")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(
            "| [implement-spec](docs/implement-spec.md) | `/implement-spec` |", readme,
        )


if __name__ == "__main__":
    unittest.main()
