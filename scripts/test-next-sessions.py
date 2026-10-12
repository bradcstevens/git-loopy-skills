#!/usr/bin/env python3
"""Offline tests for skills/next/scripts/sessions.py: live-session scan and the /next session log."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "skills", "next", "scripts", "sessions.py")


def git(cwd: str, *args: str) -> None:
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True)


class SessionScanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)
        git(self.repo, "init", "--quiet", "-b", "main")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@e", "commit", "--quiet", "--allow-empty", "-m", "i")
        self.linked = os.path.join(self.tmp, "repo-42")
        git(self.repo, "worktree", "add", "--quiet", "-b", "issue-42", self.linked)
        self.nested = os.path.join(self.repo, ".git", "loopy", "issue-7")
        git(self.repo, "worktree", "add", "--quiet", "-b", "issue-7", self.nested)
        self.other = os.path.join(self.tmp, "other")
        os.makedirs(self.other)
        git(self.other, "init", "--quiet")
        self.state = os.path.join(self.tmp, "session-state")
        os.makedirs(self.state)
        self.copilot = self.fake_copilot()

    def fake_copilot(self) -> subprocess.Popen:
        # ps reports argv[0], so a sleep named copilot stands in for a live CLI session.
        process = subprocess.Popen(["bash", "-c", "exec -a copilot sleep 120"])
        deadline = 50
        while deadline and b"copilot" not in subprocess.run(
            ["ps", "-o", "command=", "-p", str(process.pid)], capture_output=True
        ).stdout:
            deadline -= 1
            time.sleep(0.05)
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        return process

    def dead_pid(self) -> int:
        process = subprocess.Popen([sys.executable, "-c", "pass"])
        process.wait()
        return process.pid

    def session(self, session_id: str, cwd: str, pid: int, git_root: str = "") -> None:
        path = os.path.join(self.state, session_id)
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, "workspace.yaml"), "w", encoding="utf-8") as workspace:
            workspace.write(
                f"id: {session_id}\ncwd: {cwd}\ngit_root: {git_root or cwd}\nbranch: main\n"
                f"name: Session {session_id}\nclient_name: github/cli\ncreated_at: 2026-10-11T00:00:00.000Z\n"
            )
        open(os.path.join(path, f"inuse.{pid}.lock"), "w").close()

    def scan(self, *extra: str, self_id: str = "") -> dict:
        env = dict(os.environ, COPILOT_AGENT_SESSION_ID=self_id)
        result = subprocess.run(
            [sys.executable, SCRIPT, "scan", "--repo", self.linked, "--state-dir", self.state, *extra],
            check=True, capture_output=True, text=True, env=env,
        )
        return json.loads(result.stdout)

    def log_lines(self) -> list:
        with open(os.path.join(self.repo, ".git-loopy", "next", "sessions.jsonl"), encoding="utf-8") as log:
            return [json.loads(line) for line in log]

    def test_reports_only_live_copilot_sessions_in_this_repository(self) -> None:
        pid = self.copilot.pid
        self.session("main-s", self.repo, pid)
        self.session("linked-s", os.path.join(self.linked, "sub"), pid)
        self.session("nested-s", self.nested, pid)
        self.session("dead-s", self.repo, self.dead_pid())
        self.session("reused-pid-s", self.repo, os.getpid())
        self.session("other-repo-s", self.other, pid)

        report = self.scan(self_id="main-s")

        by_id = {s["session_id"]: s for s in report["sessions"]}
        self.assertEqual(set(by_id), {"main-s", "linked-s", "nested-s"})
        self.assertEqual(report["repository"], self.repo)
        self.assertEqual((by_id["linked-s"]["worktree"], by_id["linked-s"]["branch"]), (self.linked, "issue-42"))
        self.assertEqual((by_id["nested-s"]["worktree"], by_id["nested-s"]["branch"]), (self.nested, "issue-7"))
        self.assertTrue(by_id["main-s"]["self"])
        self.assertFalse(by_id["linked-s"]["self"])
        self.assertEqual({s["status"] for s in report["sessions"]}, {"new"})
        held = {w["path"]: w["sessions"] for w in report["worktrees"]}
        self.assertEqual(held[self.linked], ["linked-s"])

    def test_log_tracks_new_continuing_and_ended_sessions_across_runs(self) -> None:
        pid = self.copilot.pid
        self.session("a", self.repo, pid)
        self.session("b", self.linked, pid)
        first = self.scan(self_id="a")
        self.assertIsNone(first["previous_scan_at"])

        os.remove(os.path.join(self.state, "b", f"inuse.{pid}.lock"))
        self.session("c", self.nested, pid)
        second = self.scan(self_id="a")

        self.assertEqual({s["session_id"]: s["status"] for s in second["sessions"]}, {"a": "continuing", "c": "new"})
        self.assertEqual([s["session_id"] for s in second["ended"]], ["b"])
        self.assertEqual(second["previous_scan_at"], first["scanned_at"])
        lines = self.log_lines()
        self.assertEqual(len(lines), 2)
        self.assertEqual((lines[1]["invoked_by"], lines[1]["new"], lines[1]["ended"]), ("a", ["c"], ["b"]))
        self.assertEqual(sorted(s["session_id"] for s in lines[1]["sessions"]), ["a", "c"])

    def test_no_record_leaves_the_log_untouched(self) -> None:
        self.session("a", self.repo, self.copilot.pid)
        self.scan("--no-record")
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git-loopy", "next", "sessions.jsonl")))

    def test_names_open_chain_reservations_held_by_a_session(self) -> None:
        self.session("a", self.repo, self.copilot.pid)
        ledger = os.path.join(self.repo, ".git-loopy", "subagents.jsonl")
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        with open(ledger, "w", encoding="utf-8") as rows:
            rows.write(json.dumps({"target": "12", "session_id": "a", "finish_time": ""}) + "\n")
            rows.write(json.dumps({"target": "9", "session_id": "a", "finish_time": "2026-10-11T00:00:00Z"}) + "\n")
            rows.write("not json\n")
        report = self.scan("--no-record")
        self.assertEqual(report["sessions"][0]["chain_targets"], ["12"])

    def test_missing_state_dir_reports_no_sessions(self) -> None:
        shutil.rmtree(self.state)
        report = self.scan("--no-record")
        self.assertEqual(report["sessions"], [])


if __name__ == "__main__":
    unittest.main()
