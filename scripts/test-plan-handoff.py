#!/usr/bin/env python3
"""Offline checks of the published handoff probes and persona shell surface."""

import itertools
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


class PlanHandoffTests(unittest.TestCase):
    def test_each_independently_installed_skill_uses_the_same_readiness_contract(self):
        for skill in ("to-spec", "next"):
            text = (REPO / "skills" / skill / "SKILL.md").read_text()
            section = text.split("## Decomposition handoff\n", 1)[1]
            probe = re.search(r"```bash\n(.*?)\n```", section, re.S).group(1)
            for tracker, hook, executable in itertools.product((False, True), repeat=3):
                with self.subTest(skill=skill, tracker=tracker, hook=hook, executable=executable):
                    with tempfile.TemporaryDirectory() as directory:
                        root = Path(directory)
                        for present, relative in (
                            (tracker, "docs/agents/issue-tracker.md"),
                            (hook, ".github/hooks/git-loopy-chain.json"),
                            (executable, "bin/git-loopy"),
                        ):
                            if present:
                                path = root / relative
                                path.parent.mkdir(parents=True, exist_ok=True)
                                path.write_text("#!/bin/sh\nexit 99\n")
                                path.chmod(0o755)
                        result = subprocess.run(
                            [BASH, "--noprofile", "--norc", "-c", probe],
                            cwd=root, env={**os.environ, "PATH": str(root / "bin")},
                            capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode == 0, tracker and hook and executable)
                        self.assertEqual(result.stdout, "")
                        self.assertEqual(result.stderr, "")

    def test_shell_surface_keeps_wayfinder_and_to_spec_but_retires_to_tickets(self):
        generated = subprocess.run(
            [BASH, str(REPO / "scripts/generate-shell-env.sh"), "--print"],
            check=True, capture_output=True, text=True,
        ).stdout
        result = subprocess.run(
            [BASH, "--noprofile", "--norc", "-c",
             generated + "\ndeclare -F wayfinder to-spec; ! declare -F to-tickets"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["wayfinder", "to-spec"])
        self.assertNotIn("to-tickets", generated)
        self.assertFalse((REPO / ".github/agents/to-tickets.agent.md").exists())
        for name in ("wayfinder", "to-spec"):
            self.assertTrue((REPO / ".github/agents" / f"{name}.agent.md").is_file())
        self.assertTrue((REPO / "skills/to-tickets/SKILL.md").is_file())


if __name__ == "__main__":
    unittest.main()
