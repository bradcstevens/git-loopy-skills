#!/usr/bin/env python3
"""Offline CLI contract for the scorecard/profile role boundary."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VALIDATOR = REPO / "scripts/validate-profile-roles.py"
TASK_TYPES = ("planning", "review", "implementation", "test", "docs", "chore", "bugfix")


class ProfileRoles(unittest.TestCase):
    def test_published_catalog_roles_match_profile_stems(self):
        result = subprocess.run(
            [sys.executable, str(VALIDATOR), str(REPO)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("7 scorecard git-loopy role(s) match profiles/", result.stdout)

    def test_renamed_scorecard_role_reports_both_sides_of_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "profiles").mkdir()
            for task_type in TASK_TYPES:
                (root / "profiles" / f"{task_type}.md").write_text("Role delta\n")
            scorecard = root / "skills/model-scorecard/profiles.json"
            scorecard.parent.mkdir(parents=True)
            roles = {f"git-loopy:{key}": {} for key in TASK_TYPES}
            roles["copilot:explore"] = {}
            roles["git-loopy:reviewer"] = roles.pop("git-loopy:review")
            scorecard.write_text(json.dumps({"roles": roles}))

            result = subprocess.run(
                [sys.executable, str(VALIDATOR), str(root)],
                capture_output=True, text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scorecard/profile role mismatch", result.stderr)
        self.assertIn("missing: git-loopy:review", result.stderr)
        self.assertIn("extra: git-loopy:reviewer", result.stderr)


if __name__ == "__main__":
    unittest.main()
