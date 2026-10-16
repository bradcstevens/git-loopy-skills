#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export SWEEP="$REPO/skills/next/scripts/sweep.sh"
python3 - "$@" <<'PY'
import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest


class SweepCLI(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sweep-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.repo = self.root / "repo"
        self.git("init", "--quiet", str(self.repo), cwd=self.root)
        self.git("-c", "user.name=test", "-c", "user.email=test@example.com",
                 "commit", "--quiet", "--allow-empty", "-m", "initial")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", str(cwd or self.repo), *args],
                              check=True, capture_output=True).stdout

    def sweep(self, *args, expected=0, env=None):
        result = subprocess.run(["bash", os.environ["SWEEP"], "--repo",
                                 str(self.repo), *args], cwd=self.root,
                                capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, expected, result.stderr)
        return json.loads(result.stdout)

    def mark(self, path, pid, start=None):
        if start is None:
            start = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                                   env={**os.environ, "TZ": "UTC"}, check=True,
                                   capture_output=True, text=True).stdout
            start = " ".join(start.split())
        marker = path / ".git-loopy" / "worktree-owner"
        marker.parent.mkdir(exist_ok=True)
        marker.write_text(f"{pid}\t{start}\n")

    def test_every_unvouched_worktree_is_reported(self):
        linked = self.root / "linked tree"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        report = self.sweep()
        self.assertEqual(report["counts"], {"held": 0, "marked": 0, "unvouched": 2})
        self.assertEqual({row["path"] for row in report["worktrees"]},
                         {str(self.repo), str(linked)})
        for row in report["worktrees"]:
            self.assertEqual(row["classification"], "unvouched")

    def test_marked_worktree_reports_owner_liveness(self):
        self.mark(self.repo, os.getpid())
        row = self.sweep()["worktrees"][0]
        self.assertEqual(row["classification"], "marked")
        self.assertIs(row["owner_alive"], True)
        ended = subprocess.Popen(["true"])
        ended.wait()
        self.mark(self.repo, ended.pid, "Mon Jan 1 00:00:00 2001")
        row = self.sweep()["worktrees"][0]
        self.assertEqual(row["classification"], "marked")
        self.assertIs(row["owner_alive"], False)

    def test_live_holder_wins_even_over_a_dead_marker(self):
        self.mark(self.repo, 2147483647, "Mon Jan 1 00:00:00 2001")
        child_dir = self.repo / "subdirectory"
        child_dir.mkdir()
        holder = subprocess.Popen(
            [sys.executable, "-c", "import time; print('ready', flush=True); time.sleep(120)"],
            cwd=child_dir, stdout=subprocess.PIPE, text=True,
        )
        def stop():
            holder.terminate()
            holder.wait()
            holder.stdout.close()
        self.addCleanup(stop)
        self.assertEqual(holder.stdout.readline().strip(), "ready")
        row = self.sweep()["worktrees"][0]
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])
        self.assertIs(row["owner_alive"], False)

    def test_dirty_state_excludes_only_the_marker(self):
        self.mark(self.repo, os.getpid())
        self.assertIs(self.sweep()["worktrees"][0]["dirty"], False)
        source = self.repo / "source"
        source.write_text("untracked\n")
        self.assertIs(self.sweep()["worktrees"][0]["dirty"], True)
        self.git("add", "source")
        self.assertIs(self.sweep()["worktrees"][0]["dirty"], True)
        self.git("-c", "user.name=test", "-c", "user.email=test@example.com",
                 "commit", "--quiet", "-m", "source")
        source.write_text("modified\n")
        self.assertIs(self.sweep()["worktrees"][0]["dirty"], True)

    def test_vanished_worktree_is_reported_without_pruning(self):
        missing = self.root / "vanished"
        self.git("worktree", "add", "--quiet", "--detach", str(missing))
        missing.rename(self.root / "moved")
        before = self.git("worktree", "list", "--porcelain", "-z")
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(missing))
        self.assertEqual(row["classification"], "unvouched")
        self.assertIs(row["exists"], False)
        self.assertIsNone(row["dirty"])
        self.assertEqual(self.git("worktree", "list", "--porcelain", "-z"), before)

    def test_ledger_only_stays_unvouched_from_linked_checkout(self):
        linked = self.root / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        ledger = self.repo / ".git-loopy" / "subagents.jsonl"
        ledger.parent.mkdir()
        ledger.write_text(json.dumps({"worktree": str(linked),
                                     "parent_pid": os.getpid(), "finish_time": ""}) + "\n")
        report = self.sweep("--repo", str(linked))
        row = next(row for row in report["worktrees"] if row["path"] == str(linked))
        self.assertEqual(row["classification"], "unvouched")
        self.assertEqual(row["ledger_rows"], 1)
        self.assertEqual(report["ledger"], str(ledger))

    def test_invalid_marker_is_marked_but_not_a_proven_dead_owner(self):
        self.mark(self.repo, os.getpid())
        (self.repo / ".git-loopy" / "worktree-owner").write_text("broken\n")
        row = self.sweep(expected=1)["worktrees"][0]
        self.assertEqual(row["classification"], "marked")
        self.assertIsNone(row["owner_alive"])
        self.assertIn("invalid-marker", row["errors"])

    def test_uninspectable_worktree_does_not_hide_other_worktrees(self):
        linked = self.root / "broken"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        (linked / ".git").write_text("gitdir: /nonexistent/sweep-test-gitdir\n")
        rows = self.sweep(expected=1)["worktrees"]
        self.assertEqual(len(rows), 2)
        row = next(row for row in rows if row["path"] == str(linked))
        self.assertEqual(row["classification"], "unvouched")
        self.assertIsNone(row["dirty"])
        self.assertTrue(row["errors"])

    def test_open_file_holds_oddly_named_worktree_not_its_prefix_neighbor(self):
        linked = self.root / 'linked\n\t"\\tree'
        neighbor = Path(str(linked) + "-extra")
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        self.git("worktree", "add", "--quiet", "--detach", str(neighbor))
        with (linked / "open-file").open("w") as handle:
            handle.write("unsaved work")
            handle.flush()
            rows = {row["path"]: row for row in self.sweep()["worktrees"]}
            self.assertEqual(rows[str(linked)]["classification"], "held")
            self.assertIn(os.getpid(), rows[str(linked)]["holder_pids"])
            self.assertEqual(rows[str(neighbor)]["classification"], "unvouched")

    def test_empty_bare_repository_is_not_an_all_unvouched_report(self):
        bare = self.root / "bare.git"
        self.git("init", "--quiet", "--bare", str(bare))
        report = self.sweep("--repo", str(bare), env={
            **os.environ, "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "all",
        })
        self.assertEqual(report["worktrees"], [])
        self.assertEqual(report["counts"], {"held": 0, "marked": 0, "unvouched": 0})

    def test_sweep_changes_no_files_or_git_metadata(self):
        tracked = self.repo / "tracked"
        tracked.write_text("content\n")
        self.git("add", "tracked")
        self.git("-c", "user.name=test", "-c", "user.email=test@example.com",
                 "commit", "--quiet", "-m", "tracked")
        os.utime(tracked, (1, 1))
        self.mark(self.repo, os.getpid())
        def snapshot():
            return {
                str(path.relative_to(self.root)): (
                    path.stat().st_mtime_ns,
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                )
                for path in self.root.rglob("*") if path.is_file()
            }
        before = snapshot()
        self.sweep()
        self.assertEqual(snapshot(), before)

    def test_explicit_and_environment_ledgers_are_read_without_changes(self):
        ledger = self.root / "ledger.jsonl"
        ledger.write_text(json.dumps({"worktree": str(self.repo), "finish_time": "finished"}) + "\n")
        for args, env in [
            (("--ledger", str(ledger)), None),
            ((), {**os.environ, "CHAIN_LEDGER": str(ledger)}),
        ]:
            with self.subTest(args=args):
                report = self.sweep(*args, env=env)
                self.assertEqual(report["ledger"], str(ledger))
                self.assertEqual(report["worktrees"][0]["ledger_rows"], 1)
                self.assertEqual(report["worktrees"][0]["classification"], "unvouched")

    def test_inspection_and_ledger_failures_are_not_empty_successes(self):
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        fake_lsof = fake_bin / "lsof"
        fake_lsof.write_text("#!/bin/sh\necho 'inspection denied' >&2\nexit 1\n")
        fake_lsof.chmod(0o755)
        env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
        ledger = self.root / "malformed.jsonl"
        ledger.write_text("not json\n")
        for args, environment in [((), env), (("--ledger", str(ledger)), os.environ)]:
            with self.subTest(args=args):
                result = subprocess.run(
                    ["bash", os.environ["SWEEP"], "--repo", str(self.repo), *args],
                    cwd=self.root, capture_output=True, text=True, env=environment,
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("error:", result.stderr)

    def test_live_pid_with_reused_start_is_dead_but_unknown_start_is_conservative(self):
        self.mark(self.repo, os.getpid(), "Mon Jan 1 00:00:00 2001")
        self.assertIs(self.sweep()["worktrees"][0]["owner_alive"], False)
        self.mark(self.repo, os.getpid(), "unparseable start")
        self.assertIs(self.sweep()["worktrees"][0]["owner_alive"], True)

    def test_nested_worktree_holder_does_not_hold_outer_checkout(self):
        linked = self.repo / "nested"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        with (linked / "open").open("w"):
            rows = {row["path"]: row for row in self.sweep()["worktrees"]}
        self.assertEqual(rows[str(linked)]["classification"], "held")
        self.assertEqual(rows[str(self.repo)]["classification"], "unvouched")

    def test_running_inside_worktree_does_not_count_sweep_itself_as_holder(self):
        result = subprocess.run(["bash", os.environ["SWEEP"]], cwd=self.repo,
                                check=True, capture_output=True, text=True)
        row = json.loads(result.stdout)["worktrees"][0]
        self.assertEqual(row["classification"], "unvouched")

    def test_bare_repository_ledger_is_shared_by_its_linked_checkout(self):
        bare = self.root / "bare.git"
        self.git("clone", "--quiet", "--bare", str(self.repo), str(bare))
        linked = self.root / "bare-linked"
        self.git("--git-dir", str(bare), "worktree", "add", "--quiet", "--detach", str(linked))
        ledger = bare / ".git-loopy" / "subagents.jsonl"
        ledger.parent.mkdir()
        ledger.write_text(json.dumps({"worktree": str(linked)}) + "\n")
        report = self.sweep("--repo", str(linked))
        self.assertEqual(report["ledger"], str(ledger))
        self.assertEqual(len(report["worktrees"]), 1)
        self.assertEqual(report["worktrees"][0]["ledger_rows"], 1)

    def test_separate_git_dir_reports_working_tree_not_metadata_directory(self):
        metadata = self.root / "metadata.git"
        self.git("init", "--quiet", "--separate-git-dir", str(metadata))
        report = self.sweep()
        self.assertEqual(len(report["worktrees"]), 1)
        self.assertEqual(report["worktrees"][0]["path"], str(self.repo))
        self.assertIs(report["worktrees"][0]["dirty"], False)
        self.assertEqual(report["ledger"], str(self.repo / ".git-loopy" / "subagents.jsonl"))
        self.assertFalse((metadata / "git-loopy-worktree-root").exists())

    def test_worktree_path_with_trailing_whitespace_is_preserved(self):
        linked = self.root / "linked \n"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertIs(row["dirty"], False)
        self.assertEqual(row["classification"], "unvouched")


unittest.main()
PY
