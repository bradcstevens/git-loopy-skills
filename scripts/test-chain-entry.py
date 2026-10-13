#!/usr/bin/env python3
"""Exercise the Python strangler through the frozen chain CLI."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parent.parent
CHAIN = REPO / "skills/next/scripts/chain.sh"


class ChainEntryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.env = {**os.environ, "TZ": "America/Denver"}
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        self.ledger = self.root / ".git-loopy/subagents.jsonl"

    def chain(self, *args, payload=None, **env):
        return subprocess.run(
            [str(CHAIN), *args],
            cwd=self.root,
            env={**self.env, **env},
            input=json.dumps(payload) if payload is not None else "",
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_selected_interpreter_rejects_old_python_before_state_changes(self):
        interpreter = self.root / "old-python"
        interpreter.write_text(
            "#!/bin/sh\n"
            'exec python3 -c \'import runpy, sys; sys.version_info = (3, 8, 20); '
            'runpy.run_path(sys.argv[1], run_name="__main__")\' "$@"\n',
            encoding="utf-8",
        )
        interpreter.chmod(0o755)
        for command in ("reenter", "plan"):
            with self.subTest(command=command):
                result = self.chain(
                    command, payload={"cwd": str(self.root)},
                    CHAIN_PYTHON=str(interpreter),
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Python 3.9", result.stderr)
                self.assertFalse((self.root / ".git-loopy").exists())

    def write_rows(self, rows):
        self.ledger.parent.mkdir(exist_ok=True)
        self.ledger.write_text(
            "".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8",
        )

    def rows(self):
        return [json.loads(line) for line in self.ledger.read_text().splitlines()]

    def reenter(self, **payload):
        result = self.chain("reenter", payload={"cwd": str(self.root), **payload})
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_route_request_is_confirmed_only_by_the_forced_turn(self):
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        self.assertEqual(self.reenter(), {
            "decision": "block",
            "reason": "A completed run is unrouted. Run /next now.",
            "targets": ["issue-done"],
        })
        self.assertEqual(self.rows()[0]["route_attempts"], 1)
        self.assertNotIn("routed", self.rows()[0])
        self.assertEqual(self.reenter(stop_hook_active=True), {
            "decision": "allow", "reason": "stop-hook-active", "confirmed": "issue-done",
        })
        self.assertTrue(self.rows()[0]["routed"])

    def test_selected_interpreter_runs_both_python_and_bash_bodies(self):
        interpreter = self.root / "selected-python"
        log = self.root / "interpreter.log"
        interpreter.write_text(
            '#!/bin/sh\nprintf "%s\\n" "$1" >> "$INTERPRETER_LOG"\n'
            'exec "$REAL_PYTHON" "$@"\n', encoding="utf-8",
        )
        interpreter.chmod(0o755)
        env = {
            "CHAIN_PYTHON": str(interpreter), "REAL_PYTHON": sys.executable,
            "INTERPRETER_LOG": str(log),
        }
        self.assertEqual(self.chain("reenter", payload={}, **env).returncode, 0)
        self.assertEqual(len(log.read_text().splitlines()), 1)
        self.assertEqual(self.chain(
            "owner", "--worktree", str(self.root), **env,
        ).returncode, 0)
        self.assertGreater(len(log.read_text().splitlines()), 2)
        # The default resolves python3 from PATH, rather than ignoring the shim.
        (self.root / "python3").symlink_to(interpreter)
        self.assertEqual(self.chain(
            "reenter", payload={}, **{**env, "CHAIN_PYTHON": "",
                                     "PATH": str(self.root) + os.pathsep + self.env["PATH"]},
        ).returncode, 0)
        self.assertTrue(log.read_text().splitlines()[-1].endswith("chain_entry.py"))

    def test_shim_prefers_copilot_home_then_sibling_next(self):
        helper = REPO / "skills/setup-git-loopy-skills/git-loopy-agent-stop.py"
        home = self.root / "copilot"
        scripts = home / "skills/next/scripts"
        scripts.mkdir(parents=True)
        (scripts / "chain.sh").write_text(
            '#!/bin/sh\nprintf "%s\\n" "$1"\n', encoding="utf-8",
        )
        (scripts / "chain.sh").chmod(0o755)
        result = subprocess.run(
            [sys.executable, str(helper)], env={**self.env, "COPILOT_HOME": str(home)},
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout, "reenter\n")
        (scripts / "chain.sh").unlink()
        result = subprocess.run(
            [sys.executable, str(helper)], env={**self.env, "COPILOT_HOME": str(home)},
            input="{}", capture_output=True, text=True, check=True,
        )
        self.assertEqual(json.loads(result.stdout), {
            "decision": "allow", "reason": "repository-not-found",
        })
        self.assertLessEqual(len(helper.read_text().splitlines()), 10)

    def test_separate_git_dir_anchor_is_shared_with_a_linked_worktree(self):
        main = self.root / "separate"
        metadata = self.root / "metadata"
        linked = self.root / "linked"
        subprocess.run(
            ["git", "init", "--quiet", "--separate-git-dir", str(metadata), str(main)],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(main), "-c", "user.name=test", "-c",
             "user.email=test@example.com", "commit", "--quiet", "--allow-empty", "-m", "initial"],
            check=True,
        )
        self.ledger = main / ".git-loopy/subagents.jsonl"
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        self.assertEqual(self.reenter(cwd=str(main))["targets"], ["issue-done"])
        self.assertEqual(os.readlink(metadata / "git-loopy-worktree-root"), str(main))
        subprocess.run(
            ["git", "-C", str(main), "worktree", "add", "--quiet", "-b", "linked", str(linked)],
            check=True,
        )
        self.assertEqual(self.reenter(cwd=str(linked), stop_hook_active=True), {
            "decision": "allow", "reason": "stop-hook-active", "confirmed": "issue-done",
        })
        self.assertTrue(self.rows()[0]["routed"])
        self.assertFalse((metadata / ".git-loopy").exists())
        self.assertFalse((linked / ".git-loopy").exists())

    def test_installed_shim_finds_repository_local_next(self):
        hooks = self.root / ".github/hooks"
        hooks.mkdir(parents=True)
        helper = hooks / "git-loopy-agent-stop.py"
        shutil.copy2(REPO / "skills/setup-git-loopy-skills/git-loopy-agent-stop.py", helper)
        skills = self.root / "skills"
        skills.mkdir()
        (skills / "next").symlink_to(REPO / "skills/next", target_is_directory=True)
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        result = subprocess.run(
            [sys.executable, str(helper)],
            cwd=self.root,
            env={**self.env, "COPILOT_HOME": str(self.root / "missing-home")},
            input=json.dumps({"cwd": str(self.root)}),
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["targets"], ["issue-done"])
        self.assertEqual(self.rows()[0]["route_attempts"], 1)

    def test_live_unknown_start_and_parsed_start_are_not_reclaimed(self):
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        lock = Path(str(self.ledger) + ".lock")
        lock.mkdir()
        start = subprocess.check_output(
            ["ps", "-o", "lstart=", "-p", str(os.getpid())],
            text=True, env={**self.env, "TZ": "UTC"},
        ).strip()
        for recorded in ("not a timestamp", start.replace(" ", "  ")):
            with self.subTest(start=recorded):
                owner = f"{os.getpid()}\t{recorded}\n"
                (lock / "pid").write_text(owner, encoding="utf-8")
                self.assertEqual(self.reenter()["reason"], "ledger-busy")
                self.assertEqual((lock / "pid").read_text(), owner)
                self.assertNotIn("route_attempts", self.rows()[0])

    def test_recovery_guard_serializes_stale_reclaim(self):
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        lock = Path(str(self.ledger) + ".lock")
        guard = Path(str(lock) + ".recovery")
        lock.mkdir()
        os.utime(lock, (0, 0))
        guard.mkdir()
        (guard / "pid").write_text(f"{os.getpid()}\tunknown\n", encoding="utf-8")
        self.assertEqual(self.reenter()["reason"], "ledger-busy")
        self.assertTrue(lock.exists())
        self.assertNotIn("route_attempts", self.rows()[0])
        os.utime(guard, (0, 0))
        (guard / "pid").unlink()
        os.utime(guard, (0, 0))
        self.assertEqual(self.reenter()["targets"], ["issue-done"])
        self.assertFalse(lock.exists())
        self.assertFalse(guard.exists())
        self.assertFalse(list(self.ledger.parent.glob("*.reclaim.*")))

    def test_bash_reservation_and_reenter_share_the_non_utc_ledger_lock(self):
        self.write_rows([{"target": "issue-done", "finish_time": "2026-10-12T00:00:00Z"}])
        before = self.ledger.read_bytes()
        tracker = self.root / "tracker"
        tracker.write_text('#!/bin/sh\nprintf \'{"number":1}\\n\'\n', encoding="utf-8")
        tracker.chmod(0o755)
        writer = subprocess.Popen(
            [str(CHAIN), "reserve", "--route", "/implement", "--target", "issue-new",
             "--spawn-time", "2026-10-12T00:01:00Z", "--worktree", str(self.root),
             "--chain-depth", "1", "--parent-pid", str(os.getpid()),
             "--session-id", "parent", "--in-place"],
            cwd=self.root,
            env={**self.env, "CHAIN_TRACKER_BIN": str(tracker),
                 "CHAIN_RESERVE_PAUSE_BEFORE_COMMIT": "4"},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            deadline = time.monotonic() + 30
            while not any(
                b"issue-new" in path.read_bytes()
                for path in self.ledger.parent.glob(".subagents.*")
            ):
                if writer.poll() is not None or time.monotonic() >= deadline:
                    self.fail("bash reservation did not reach its pre-commit pause")
                time.sleep(0.02)
            owner = Path(str(self.ledger) + ".lock/pid")
            owner_before = owner.read_bytes()
            start = time.monotonic()
            self.assertEqual(self.reenter(), {"decision": "allow", "reason": "ledger-busy"})
            self.assertGreaterEqual(time.monotonic() - start, 0.9)
            self.assertEqual(owner.read_bytes(), owner_before)
            self.assertEqual(self.ledger.read_bytes(), before)
            stdout, stderr = writer.communicate(timeout=15)
            self.assertEqual(writer.returncode, 0, stdout + stderr)
        finally:
            if writer.poll() is None:
                writer.terminate()
            writer.communicate(timeout=15)
        self.assertEqual(self.reenter()["targets"], ["issue-done"])
        rows = self.rows()
        self.assertEqual([row["target"] for row in rows], ["issue-done", "issue-new"])
        self.assertEqual(rows[0]["route_attempts"], 1)
        self.assertFalse(rows[1]["finish_time"])
        self.assertFalse(Path(str(self.ledger) + ".lock").exists())


if __name__ == "__main__":
    unittest.main()
