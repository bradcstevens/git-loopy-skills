#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export SWEEP="$REPO/skills/next/scripts/sweep.sh"
python3 - "$@" <<'PY'
import datetime
import errno
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys
import unittest


# CI runners have no git identity, so every committing command passes this one.
IDENTITY = ("-c", "user.name=test", "-c", "user.email=test@example.com")

# Stands in for gh: logs each call, then lists the merged pull requests recorded for --head.
GH_STUB = r'''
import json
import os
import subprocess
import sys

watched = json.loads(os.environ.get("GH_STUB_WATCH", "[]"))
with open(os.environ["GH_STUB_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:] + [[os.path.exists(path) for path in watched]]) + "\n")
if os.environ.get("GH_STUB_FAIL"):
    sys.exit("HTTP 502: Bad Gateway")
if os.environ.get("GH_STUB_RUN"):
    subprocess.run(os.environ["GH_STUB_RUN"], shell=True, check=True)
head = sys.argv[sys.argv.index("--head") + 1]
with open(os.environ["GH_STUB_PULLS"]) as pulls:
    print(json.dumps(json.load(pulls).get(head, [])))
'''


class SweepCLI(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sweep-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.repo = self.root / "repo"
        self.git("init", "--quiet", str(self.repo), cwd=self.root)
        self.git(*IDENTITY, "commit", "--quiet", "--allow-empty", "-m", "initial")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", str(cwd or self.repo), *args],
                              check=True, capture_output=True).stdout

    def sweep_result(self, *args, env=None):
        return subprocess.run(["bash", os.environ["SWEEP"], "--repo", str(self.repo), *args],
                              cwd=self.root, capture_output=True, text=True, env=env)

    def write_ledger(self, *rows):
        ledger = self.root / "subagents.jsonl"
        ledger.write_text("".join(json.dumps(row) + "\n" for row in rows))
        return ledger

    def sweep(self, *args, expected=0, env=None):
        result = subprocess.run(["bash", os.environ["SWEEP"], "--repo",
                                 str(self.repo), *args], cwd=self.root,
                                capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, expected, result.stderr)
        return json.loads(result.stdout)

    def stub_command(self, name, script, shebang="/bin/sh", directory=None):
        """Write an executable stand-in for a command into its own directory, and return that."""
        directory = self.root / (directory or f"{name}-bin")
        directory.mkdir(exist_ok=True)
        (directory / name).write_text(f"#!{shebang}\n{script}\n")
        (directory / name).chmod(0o755)
        return directory

    def process_start(self, pid):
        start = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                               env={**os.environ, "TZ": "UTC"}, check=True,
                               capture_output=True, text=True).stdout
        return " ".join(start.split())

    def mark(self, path, pid, start=None):
        if start is None:
            start = self.process_start(pid)
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
        holder = self.hold(child_dir)
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
        self.git(*IDENTITY, "commit", "--quiet", "-m", "source")
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

    def hold(self, directory):
        holder = subprocess.Popen(
            [sys.executable, "-c", "import time; print('ready', flush=True); time.sleep(120)"],
            cwd=directory, stdout=subprocess.PIPE, text=True,
        )
        def stop():
            holder.terminate()
            holder.wait()
            holder.stdout.close()
        self.addCleanup(stop)
        self.assertEqual(holder.stdout.readline().strip(), "ready")
        return holder

    def test_escaped_names_are_still_held(self):
        for name in ("bell\atree", "escape\x1btree", "delete\x7ftree", "caret^Gtree"):
            with self.subTest(name=name):
                linked = self.root / name
                self.git("worktree", "add", "--quiet", "--detach", str(linked))
                holder = self.hold(linked)
                row = next(row for row in self.sweep()["worktrees"]
                           if row["path"] == str(linked))
                self.assertEqual(row["classification"], "held")
                self.assertIn(holder.pid, row["holder_pids"])

    def test_ambiguous_lsof_spelling_holds_every_worktree_it_could_name(self):
        control = self.root / "spelled\atree"
        caret = self.root / "spelled^Gtree"
        for path in (control, caret):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        holder = self.hold(caret)
        rows = {row["path"]: row for row in self.sweep()["worktrees"]}
        for path in (control, caret):
            self.assertEqual(rows[str(path)]["classification"], "held")
            self.assertIn(holder.pid, rows[str(path)]["holder_pids"])
        self.assertEqual(rows[str(self.repo)]["classification"], "unvouched")

    def test_ambiguous_spelling_never_lets_one_worktree_hide_another(self):
        control = self.root / "nest\a"
        caret = self.root / "nest^G" / "inner"
        for path in (control, caret):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        (control / "inner").mkdir()
        holder = self.hold(control / "inner")
        rows = {row["path"]: row for row in self.sweep()["worktrees"]}
        for path in (control, caret):
            self.assertEqual(rows[str(path)]["classification"], "held")
            self.assertIn(holder.pid, rows[str(path)]["holder_pids"])

    def test_ambiguous_nested_worktree_never_hides_its_parent(self):
        for outer_name, nested_name, held_name in (("outer-caret", "b^G", "b\a"),
                                                   ("outer-control", "y\a", "y^G")):
            with self.subTest(nested=nested_name):
                outer = self.root / outer_name
                nested = outer / nested_name
                for path in (outer, nested):
                    self.git("worktree", "add", "--quiet", "--detach", str(path))
                (outer / held_name).mkdir()
                holder = self.hold(outer / held_name)
                row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(outer))
                self.assertEqual(row["classification"], "held")
                self.assertIn(holder.pid, row["holder_pids"])

    def test_byte_ff_is_held_whichever_way_lsof_spells_it(self):
        linked = self.root / os.fsdecode(b"byte\xfftree")
        try:
            linked.mkdir()
        except OSError as error:
            if error.errno == errno.EILSEQ:
                self.skipTest("this file system rejects byte 0xff in names")
            raise
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        holder = self.hold(linked)
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])

    def test_registered_spelling_the_kernel_never_prints_is_still_held(self):
        (self.root / "casebase").mkdir()
        if not (self.root / "CASEBASE").exists():
            self.skipTest("this file system is case-sensitive")
        linked = self.root / "CASEBASE" / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        holder = self.hold(linked)
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])
        self.assertEqual(row["errors"], [])

    def test_case_differing_worktree_stays_held_when_git_cannot_inspect_it(self):
        (self.root / "brokenbase").mkdir()
        if not (self.root / "BROKENBASE").exists():
            self.skipTest("this file system is case-sensitive")
        for breakage in ("index", "gitfile"):
            with self.subTest(breakage):
                linked = self.root / "BROKENBASE" / breakage
                self.git("worktree", "add", "--quiet", "--detach", str(linked))
                if breakage == "index":
                    index = self.git("rev-parse", "--path-format=absolute", "--git-path",
                                     "index", cwd=linked)
                    Path(os.fsdecode(index).removesuffix("\n")).write_text("corrupt\n")
                else:
                    (linked / ".git").write_text("gitdir: /nonexistent/sweep-test-gitdir\n")
                holder = self.hold(linked)
                row = next(row for row in self.sweep(expected=1)["worktrees"]
                           if row["path"] == str(linked))
                self.assertEqual(row["classification"], "held")
                self.assertIn(holder.pid, row["holder_pids"])
                self.assertTrue(row["errors"])

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
        self.git(*IDENTITY, "commit", "--quiet", "-m", "tracked")
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
        before = ledger.read_bytes()
        for args, env in [
            (("--ledger", str(ledger)), None),
            ((), {**os.environ, "CHAIN_LEDGER": str(ledger)}),
        ]:
            with self.subTest(args=args):
                report = self.sweep(*args, env=env)
                self.assertEqual(report["ledger"], str(ledger))
                self.assertEqual(report["worktrees"][0]["ledger_rows"], 1)
                self.assertEqual(report["worktrees"][0]["classification"], "unvouched")
                self.assertEqual(ledger.read_bytes(), before)

    def test_invalid_arguments_exit_two_without_a_report(self):
        result = subprocess.run(["bash", os.environ["SWEEP"], "--no-such-option"],
                                cwd=self.repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_missing_pwd_fails_the_sweep(self):
        tools = self.root / "tools"
        tools.mkdir()
        for tool in ("git", "lsof", "bash", "dirname"):
            (tools / tool).symlink_to(shutil.which(tool))
        result = subprocess.run(
            ["bash", os.environ["SWEEP"], "--repo", str(self.repo)], cwd=self.root,
            capture_output=True, text=True,
            env={**os.environ, "PATH": str(tools), "CHAIN_PYTHON": sys.executable},
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("pwd not found", result.stderr)

    def test_uninspectable_directories_are_flagged_not_misread(self):
        leaf = self.root / "locked-leaf"
        parent = self.root / "locked-parent"
        nested = parent / "linked"
        for path in (leaf, nested):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        for path in (leaf, parent):
            self.lock(path)
        rows = {row["path"]: row for row in self.sweep(expected=1)["worktrees"]}
        self.assertTrue(any("kernel's spelling" in error for error in rows[str(leaf)]["errors"]))
        self.assertIsNone(rows[str(nested)]["exists"])
        self.assertTrue(rows[str(nested)]["errors"])

    def lock(self, path):
        if os.geteuid() == 0:
            self.skipTest("permission checks do not bind root")
        path.chmod(0)
        self.addCleanup(path.chmod, 0o755)

    def test_marker_behind_an_unsearchable_directory_is_flagged(self):
        linked = self.root / "marked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        self.mark(linked, os.getpid())
        self.lock(linked / ".git-loopy")
        row = next(row for row in self.sweep(expected=1)["worktrees"]
                   if row["path"] == str(linked))
        self.assertTrue(any("worktree-owner" in error for error in row["errors"]))

    def test_unreadable_untracked_directory_is_flagged_not_clean(self):
        wip = self.repo / "wip"
        wip.mkdir()
        (wip / "notes").write_text("unsaved\n")
        self.lock(wip)
        row = self.sweep(expected=1)["worktrees"][0]
        self.assertIsNone(row["dirty"])
        self.assertTrue(row["errors"])

    def test_parent_replaced_by_a_file_reads_as_vanished(self):
        linked = self.root / "replaced" / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        shutil.rmtree(self.root / "replaced")
        (self.root / "replaced").write_text("now a file\n")
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertIs(row["exists"], False)
        self.assertEqual(row["errors"], [])

    def test_unreliable_nested_registration_does_not_hide_its_parent(self):
        outer = self.root / "outer"
        nested = outer / "nested"
        for path in (outer, nested):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        (nested / ".git").write_text("gitdir: /nonexistent/sweep-test-gitdir\n")
        holder = self.hold(nested)
        rows = {row["path"]: row for row in self.sweep(expected=1)["worktrees"]}
        self.assertEqual(rows[str(outer)]["classification"], "held")
        self.assertIn(holder.pid, rows[str(outer)]["holder_pids"])

    def test_lsof_annotation_after_a_worktree_root_still_holds_it(self):
        linked = self.root / "annotated"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        stub = self.root / "stub-bin"
        stub.mkdir()
        (stub / "lsof").write_text(f"#!/bin/sh\nprintf 'p1\\0R0\\0n%s (deleted)\\0' '{linked}'\n")
        (stub / "lsof").chmod(0o755)
        report = self.sweep(env={**os.environ, "PATH": str(stub) + os.pathsep + os.environ["PATH"]})
        rows = {row["path"]: row for row in report["worktrees"]}
        self.assertEqual(rows[str(linked)]["holder_pids"], [1])
        self.assertEqual(rows[str(self.repo)]["holder_pids"], [])

    def test_annotated_sibling_name_never_lets_a_nested_worktree_hide_its_parent(self):
        outer = self.root / "outer-annotated"
        nested = outer / "sub"
        for path in (outer, nested):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        (outer / "sub (2)").mkdir()
        holder = self.hold(outer / "sub (2)")
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(outer))
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])

    def test_nested_worktree_outranks_its_parent_only_when_certain(self):
        outer = self.root / "outer-certain"
        self.git("worktree", "add", "--quiet", "--detach", str(outer))
        annotated = outer / "x (deleted)"
        vanished = outer / "gone"
        cloned = outer / "cloned"
        for path in (annotated, vanished, cloned):
            self.git("worktree", "add", "--quiet", "--detach", str(path))
        shutil.rmtree(vanished)
        shutil.rmtree(cloned)
        self.git("init", "--quiet", str(cloned), cwd=self.root)
        stub = self.root / "stub-bin"
        stub.mkdir()
        (stub / "lsof").write_text(
            "#!/bin/sh\n"
            f"printf 'p1\\0R0\\0n%s\\0' '{outer}/x (deleted)'\n"
            f"printf 'p2\\0R0\\0n%s\\0' '{vanished}'\n"
            f"printf 'p3\\0R0\\0n%s\\0' '{cloned}'\n"
        )
        (stub / "lsof").chmod(0o755)
        report = self.sweep(expected=1,
                            env={**os.environ, "PATH": str(stub) + os.pathsep + os.environ["PATH"]})
        rows = {row["path"]: row for row in report["worktrees"]}
        self.assertEqual(rows[str(outer)]["holder_pids"], [1, 2, 3])
        self.assertIn("directory belongs to another repository", rows[str(cloned)]["errors"])

    def test_vanished_worktree_under_a_differently_spelled_ancestor_is_still_held(self):
        (self.root / "\u00e9base").mkdir()
        if not (self.root / "\u00c9BASE").exists():
            self.skipTest("this file system is case-sensitive")
        linked = self.root / "\u00c9BASE" / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        holder = self.hold(linked)
        shutil.rmtree(linked)
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])

    def test_vanished_case_differing_worktree_is_still_held(self):
        (self.root / "gonebase").mkdir()
        if not (self.root / "GONEBASE").exists():
            self.skipTest("this file system is case-sensitive")
        linked = self.root / "GONEBASE" / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(linked))
        holder = self.hold(linked)
        shutil.rmtree(linked)
        row = next(row for row in self.sweep()["worktrees"] if row["path"] == str(linked))
        self.assertIs(row["exists"], False)
        self.assertEqual(row["classification"], "held")
        self.assertIn(holder.pid, row["holder_pids"])

    def test_missing_or_old_interpreter_exits_two_without_a_report(self):
        old = self.root / "old-python"
        old.write_text("#!/bin/sh\nexit 1\n")
        old.chmod(0o755)
        for python, reason in ((old, "is older"), (self.root / "no-python", "not found")):
            with self.subTest(reason):
                result = subprocess.run(["bash", os.environ["SWEEP"]], cwd=self.repo,
                                        capture_output=True, text=True,
                                        env={**os.environ, "CHAIN_PYTHON": str(python)})
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("requires Python 3.9 or newer", result.stderr)
                self.assertIn(reason, result.stderr)

    def test_inspection_and_ledger_failures_are_not_empty_successes(self):
        def lsof_that(label, body):
            directory = self.stub_command("lsof", body, directory=f"{label}-bin")
            return {**os.environ, "PATH": f"{directory}{os.pathsep}{os.environ['PATH']}"}
        ledger = self.root / "malformed.jsonl"
        ledger.write_text("not json\n")
        pending = self.root / "pending.jsonl"
        Path(str(pending) + ".pending").write_text("not json\n")
        empty = self.root / "empty.jsonl"
        Path(str(empty) + ".pending").write_text(json.dumps({"worktree": ""}) + "\n")
        unreadable = self.root / "unreadable.jsonl"
        Path(str(unreadable) + ".pending").write_text(json.dumps({"worktree": str(self.repo)}))
        if os.geteuid() != 0:
            Path(str(unreadable) + ".pending").chmod(0)
        for label, args, environment in [
            ("denied", (), lsof_that("denied", "echo 'inspection denied' >&2\nexit 1")),
            ("silent", (), lsof_that("silent", "exit 1")),
            ("empty", (), lsof_that("empty", "exit 0")),
            ("ledger", ("--ledger", str(ledger)), os.environ),
            ("pending", ("--remove", "--ledger", str(pending)), os.environ),
            ("empty pending", ("--remove", "--ledger", str(empty)), os.environ),
            *((("unreadable pending", ("--remove", "--ledger", str(unreadable)), os.environ),)
              if os.geteuid() != 0 else ()),
        ]:
            with self.subTest(label):
                result = subprocess.run(
                    ["bash", os.environ["SWEEP"], "--repo", str(self.repo), *args],
                    cwd=self.root, capture_output=True, text=True, env=environment,
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("error:", result.stderr)
        # Only removal reads the pending record, so a report never fails over it.
        for ledger_path in (pending, unreadable):
            self.assertEqual(self.sweep("--ledger", str(ledger_path))["counts"]["unvouched"], 1)

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

    def commit(self, message, cwd=None):
        self.git(*IDENTITY, "commit", "--quiet", "--allow-empty", "-m", message, cwd=cwd)

    def linked(self, name, branch=None, base=None):
        path = (base or self.root) / name
        self.git("worktree", "add", "--quiet", "-b", branch or name, str(path))
        return path

    def dead_owner(self, path):
        self.mark(path, *self.ended_process())

    def tip(self, branch):
        return os.fsdecode(self.git("rev-parse", f"refs/heads/{branch}")).strip()

    def has_branch(self, branch):
        return subprocess.run(["git", "-C", str(self.repo), "rev-parse", "--verify", "--quiet",
                               f"refs/heads/{branch}"], capture_output=True).returncode == 0

    def registered(self):
        return {os.fsdecode(field[len(b"worktree "):])
                for field in self.git("worktree", "list", "--porcelain", "-z").split(b"\0")
                if field.startswith(b"worktree ")}

    def row(self, report, path):
        return next(row for row in report["worktrees"] if row["path"] == str(path))

    def stub_github(self, pulls=None, fail=False, path=(), watch=(), run=None):
        """Return an environment whose gh lists, per branch, the merged pull requests in pulls."""
        stub = self.stub_command("gh", GH_STUB, shebang=sys.executable)
        (stub / "pulls.json").write_text(json.dumps(pulls or {}))
        self.gh_log = stub / "calls.jsonl"
        env = {**os.environ, "PATH": os.pathsep.join([*path, str(stub), os.environ["PATH"]]),
               "GH_STUB_PULLS": str(stub / "pulls.json"), "GH_STUB_LOG": str(self.gh_log),
               "GH_STUB_WATCH": json.dumps([str(watched) for watched in watch])}
        if fail:
            env["GH_STUB_FAIL"] = "1"
        if run:
            env["GH_STUB_RUN"] = run
        return env

    def rebase_to_edit(self, path, *options, upstream="HEAD~1"):
        """Leave a worktree stopped at an interactive rebase's edit step, clean but unfinished."""
        self.commit("one", cwd=path)
        self.commit("two", cwd=path)
        subprocess.run(["git", "-C", str(path), *IDENTITY, "rebase", "--quiet", "-i",
                        *options, upstream],
                       env={**os.environ, "GIT_SEQUENCE_EDITOR": "sed -i.bak -e s/^pick/edit/"},
                       check=True, capture_output=True)

    def ignore(self, path, pattern):
        (path / ".gitignore").write_text(pattern + "\n")
        self.git("add", ".gitignore", cwd=path)
        self.commit("ignore " + pattern, cwd=path)

    def asked_github_about(self):
        if not self.gh_log.exists():
            return []
        calls = [json.loads(line) for line in self.gh_log.read_text().splitlines()]
        return [call[call.index("--head") + 1] for call in calls]

    def present_at_each_github_call(self):
        return [json.loads(line)[-1] for line in self.gh_log.read_text().splitlines()]

    def before_look(self, number, script):
        """Stub lsof to run a shell snippet before its numbered listing; the second precedes removal."""
        count = self.root / "lsof-calls"
        return str(self.stub_command("lsof", (
            f'n=$(cat "{count}" 2>/dev/null || echo 0)\n'
            f'echo $((n + 1)) > "{count}"\n'
            f'if [ "$n" -eq {number - 1} ]; then\n{script}\nfi\n'
            f'exec "{shutil.which("lsof")}" "$@"')))

    def test_without_remove_a_vouched_worktree_is_only_reported(self):
        done = self.linked("done")
        self.dead_owner(done)
        report = self.sweep(env=self.stub_github())
        row = self.row(report, done)
        self.assertEqual(row["classification"], "marked")
        self.assertNotIn("outcome", row)
        self.assertNotIn("removed", report["counts"])
        self.assertTrue(done.is_dir())
        self.assertTrue(self.has_branch("done"))
        self.assertEqual(self.asked_github_about(), [])

    def test_remove_takes_a_dead_owners_clean_worktree_then_its_merged_branch(self):
        done = self.linked("done")
        # A squash merge leaves this commit outside main's ancestry.
        self.commit("work", cwd=done)
        detached = self.root / "detached"
        self.git("worktree", "add", "--quiet", "--detach", str(detached))
        for path in (done, detached):
            self.dead_owner(path)
        env = self.stub_github({"done": [{"headRefOid": self.tip("done"), "isCrossRepository": False}]})
        report = self.sweep("--remove", env=env)
        row = self.row(report, done)
        self.assertEqual((row["outcome"], row["reasons"]), ("removed", []))
        self.assertEqual((row["branch_outcome"], row["branch_reasons"]), ("deleted", []))
        self.assertFalse(done.exists())
        self.assertNotIn(str(done), self.registered())
        self.assertFalse(self.has_branch("done"))
        row = self.row(report, detached)
        self.assertEqual((row["outcome"], row["branch_outcome"]), ("removed", None))
        self.assertFalse(detached.exists())
        self.assertEqual(self.asked_github_about(), ["done"])
        self.assertEqual(report["counts"], {"held": 0, "marked": 2, "unvouched": 1,
                                            "removed": 2, "pruned": 0, "declined": 1})
        self.assertEqual(self.row(report, self.repo)["reasons"], ["main-worktree", "unvouched"])

    def test_live_owner_keeps_its_worktree(self):
        alive = self.linked("alive")
        self.mark(alive, os.getpid())
        unreadable = self.linked("unreadable")
        self.mark(unreadable, os.getpid())
        (unreadable / ".git-loopy" / "worktree-owner").write_text("broken\n")
        report = self.sweep("--remove", expected=1, env=self.stub_github())
        row = self.row(report, alive)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["owner-alive"]))
        self.assertEqual(self.row(report, unreadable)["reasons"],
                         ["inspection-errors", "owner-liveness-unknown"])
        for path in (alive, unreadable):
            self.assertTrue(path.is_dir())
        self.assertTrue(self.has_branch("alive"))
        self.assertEqual(self.asked_github_about(), [])

    def test_merge_status_comes_from_the_remote_never_from_ancestry(self):
        # Each branch sits at main's own commit, so local ancestry would call every one merged.
        paths = {name: self.linked(name) for name in ("unmerged", "elsewhere", "forked")}
        tip = self.tip("unmerged")
        for path in paths.values():
            self.dead_owner(path)
        env = self.stub_github({
            "elsewhere": [{"headRefOid": "0" * 40, "isCrossRepository": False}],
            "forked": [{"headRefOid": tip, "isCrossRepository": True}],
        })
        report = self.sweep("--remove", env=env)
        for name, reason in (("unmerged", "not-merged"), ("elsewhere", "merged-at-another-commit"),
                             ("forked", "not-merged")):
            with self.subTest(name):
                row = self.row(report, paths[name])
                self.assertEqual(row["outcome"], "removed")
                self.assertEqual((row["branch_outcome"], row["branch_reasons"]), ("kept", [reason]))
                self.assertEqual(self.tip(name), tip)
        self.assertEqual(sorted(self.asked_github_about()), ["elsewhere", "forked", "unmerged"])

    def test_branch_stays_when_its_worktree_cannot_be_removed(self):
        if os.geteuid() == 0:
            self.skipTest("permission checks do not bind root")
        sealed = self.root / "sealed"
        sealed.mkdir()
        stuck = self.linked("stuck", base=sealed)
        self.dead_owner(stuck)
        marker = (stuck / ".git-loopy" / "worktree-owner").read_bytes()
        env = self.stub_github({"stuck": [{"headRefOid": self.tip("stuck"), "isCrossRepository": False}]})
        sealed.chmod(0o555)
        self.addCleanup(sealed.chmod, 0o755)
        row = self.row(self.sweep("--remove", expected=1, env=env), stuck)
        self.assertEqual(row["outcome"], "declined")
        # git deleted the registration and the directory's contents before failing on it.
        self.assertEqual(row["reasons"], ["removal-failed", "registration-lost"])
        self.assertNotIn(str(stuck), self.registered())
        self.assertTrue(row["errors"])
        self.assertIsNone(row["branch_outcome"])
        self.assertTrue(self.has_branch("stuck"))
        self.assertEqual((stuck / ".git-loopy" / "worktree-owner").read_bytes(), marker)
        self.assertEqual(self.asked_github_about(), [])

    def test_uncommitted_changes_refuse_removal_whatever_else_is_true(self):
        def stage(path):
            (path / "notes").write_text("staged\n")
            self.git("add", "notes", cwd=path)
        changes = {
            "untracked": lambda path: (path / "notes").write_text("unsaved\n"),
            "staged": stage,
            "modified": lambda path: (path / "tracked").write_text("changed\n"),
        }
        for name, change in changes.items():
            path = self.linked(name)
            (path / "tracked").write_text("committed\n")
            self.git("add", "tracked", cwd=path)
            self.commit("tracked", cwd=path)
            self.dead_owner(path)
            change(path)
        unvouched = self.linked("unvouched")
        alive = self.linked("alive")
        self.mark(alive, os.getpid())
        held = self.linked("held")
        self.dead_owner(held)
        for path in (unvouched, alive, held):
            (path / "notes").write_text("unsaved\n")
        self.hold(held)
        report = self.sweep("--remove", env=self.stub_github())
        for name in (*changes, "unvouched", "alive", "held"):
            with self.subTest(name):
                path = self.root / name
                row = self.row(report, path)
                self.assertEqual(row["outcome"], "declined")
                self.assertIn("uncommitted-changes", row["reasons"])
                self.assertTrue(path.is_dir())
                self.assertTrue(self.has_branch(name))
        self.assertEqual((self.root / "modified" / "tracked").read_text(), "changed\n")
        self.assertEqual(self.row(report, unvouched)["reasons"], ["uncommitted-changes", "unvouched"])
        self.assertEqual(self.row(report, alive)["reasons"], ["uncommitted-changes", "owner-alive"])
        self.assertIn("held", self.row(report, held)["reasons"])
        self.assertEqual(self.asked_github_about(), [])

    def test_held_worktree_is_never_removed(self):
        occupied = self.linked("occupied")
        self.dead_owner(occupied)
        holder = self.hold(occupied)
        row = self.row(self.sweep("--remove", env=self.stub_github()), occupied)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["held"]))
        self.assertIn(holder.pid, row["holder_pids"])
        self.assertTrue(occupied.is_dir())

    def test_a_holder_seen_on_the_second_look_still_refuses_removal(self):
        late = self.linked("late")
        self.dead_owner(late)
        lsof = self.before_look(2, f"printf 'p1\\0R0\\0n%s\\0' '{late}'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), late)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["held"]))
        self.assertEqual((row["classification"], row["holder_pids"]), ("held", [1]))
        self.assertTrue(late.is_dir())
        self.assertTrue(self.has_branch("late"))

    def test_a_marker_rewritten_before_removal_refuses_it(self):
        late = self.linked("late")
        self.dead_owner(late)
        lsof = self.before_look(2, f"printf 'x' >> '{late}/.git-loopy/worktree-owner'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), late)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["marker-changed"]))
        self.assertTrue(late.is_dir())

    def test_work_written_after_the_worktree_was_judged_clean_is_still_refused(self):
        late = self.linked("late")
        self.dead_owner(late)
        marker = (late / ".git-loopy" / "worktree-owner").read_bytes()
        lsof = self.before_look(2, f"echo unsaved > '{late}/notes'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), late)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["uncommitted-changes"]))
        self.assertEqual((late / "notes").read_text(), "unsaved\n")
        self.assertEqual((late / ".git-loopy" / "worktree-owner").read_bytes(), marker)
        self.assertIn(str(late), self.registered())
        self.assertTrue(self.has_branch("late"))

    def during_worktree_remove(self, script):
        """Stub git to run a shell snippet as git worktree remove starts, after every sweep check."""
        return str(self.stub_command("git", (
            f'case " $* " in *" worktree remove "*) {script} ;; esac\n'
            f'exec "{shutil.which("git")}" "$@"')))

    def test_every_removal_finishes_before_github_is_asked_about_a_branch(self):
        first, second = self.linked("first"), self.linked("second")
        for path in (first, second):
            self.dead_owner(path)
        report = self.sweep("--remove", env=self.stub_github(watch=(first, second)))
        self.assertEqual(report["counts"]["removed"], 2)
        self.assertEqual(self.present_at_each_github_call(), [[False, False], [False, False]])

    def test_detached_commits_no_ref_contains_refuse_removal(self):
        scratch = self.root / "scratch"
        self.git("worktree", "add", "--quiet", "--detach", str(scratch))
        self.commit("only copy", cwd=scratch)
        head = os.fsdecode(self.git("rev-parse", "HEAD", cwd=scratch)).strip()
        self.dead_owner(scratch)
        row = self.row(self.sweep("--remove", env=self.stub_github()), scratch)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["unreferenced-head"]))
        self.assertEqual(os.fsdecode(self.git("rev-parse", "HEAD", cwd=scratch)).strip(), head)

    def test_an_unfinished_operation_refuses_removal(self):
        rebasing = self.linked("rebasing")
        self.rebase_to_edit(rebasing)
        self.dead_owner(rebasing)
        row = self.row(self.sweep("--remove", env=self.stub_github()), rebasing)
        self.assertIs(row["dirty"], False)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["operation-in-progress"]))
        self.assertTrue(rebasing.is_dir())

    def test_nested_worktree_registered_under_another_spelling_still_protects_its_work(self):
        outer = self.linked("outer")
        if not (self.root / "OUTER").exists():
            self.skipTest("this file system is case-sensitive")
        self.ignore(outer, "inner/")
        inner = self.linked("inner", base=self.root / "OUTER")
        (inner / "unsaved").write_text("work\n")
        self.dead_owner(outer)
        row = self.row(self.sweep("--remove", env=self.stub_github()), outer)
        self.assertEqual(row["reasons"], ["contains-worktree"])
        self.assertEqual((outer / "inner" / "unsaved").read_text(), "work\n")

    def test_a_worktree_containing_the_repository_itself_is_never_removed(self):
        enclosing = self.root / "enclosing"
        bare = self.root / "bare.git"
        self.git("clone", "--quiet", "--bare", str(self.repo), str(bare))
        self.git("--git-dir", str(bare), "worktree", "add", "--quiet", "-b", "enclosing",
                 str(enclosing))
        bare.rename(enclosing / "bare.git")
        bare = enclosing / "bare.git"
        self.git("--git-dir", str(bare), "worktree", "repair", str(enclosing))
        with (bare / "info" / "exclude").open("a") as exclude:
            exclude.write("bare.git/\n")
        self.dead_owner(enclosing)
        env = {**self.stub_github(), "GIT_CONFIG_COUNT": "1",
               "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "all"}
        report = self.sweep("--remove", "--repo", str(bare), env=env)
        row = self.row(report, enclosing)
        self.assertIs(row["dirty"], False)
        self.assertEqual(row["reasons"], ["contains-repository"])
        self.assertTrue((bare / "HEAD").is_file())

    def test_gits_own_check_refuses_late_work_even_where_status_hides_untracked_files(self):
        self.git("config", "status.showUntrackedFiles", "no")
        late = self.linked("late")
        self.dead_owner(late)
        git = self.during_worktree_remove(f"echo unsaved > '{late}/notes'")
        row = self.row(self.sweep("--remove", expected=1, env=self.stub_github(path=[git])), late)
        self.assertEqual((row["outcome"], row["reasons"]),
                         ("declined", ["removal-failed", "uncommitted-changes"]))
        self.assertTrue(row["errors"])
        self.assertEqual((late / "notes").read_text(), "unsaved\n")
        self.assertIn(str(late), self.registered())

    def test_unvouched_worktree_is_reported_and_not_removed(self):
        stray = self.linked("stray")
        report = self.sweep("--remove", env=self.stub_github())
        row = self.row(report, stray)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["unvouched"]))
        self.assertTrue(stray.is_dir())
        self.assertIn(str(stray), self.registered())
        self.assertEqual(report["counts"]["removed"], 0)

    def test_main_locked_and_enclosing_worktrees_are_never_removed(self):
        self.dead_owner(self.repo)
        pinned = self.linked("pinned")
        self.dead_owner(pinned)
        self.git("worktree", "lock", str(pinned))
        outer = self.linked("outer")
        self.ignore(outer, "inner/")
        inner = self.linked("inner", base=outer)
        (inner / "unsaved").write_text("work\n")
        self.dead_owner(outer)
        report = self.sweep("--remove", env=self.stub_github())
        self.assertEqual(self.row(report, self.repo)["reasons"], ["main-worktree"])
        self.assertEqual(self.row(report, pinned)["reasons"], ["locked"])
        self.assertEqual(self.row(report, outer)["reasons"], ["contains-worktree"])
        self.assertEqual((inner / "unsaved").read_text(), "work\n")
        self.assertEqual(report["counts"]["removed"], 0)

    def test_vanished_worktree_is_pruned_without_disturbing_any_other(self):
        gone = self.linked("gone")
        locked = self.linked("gone-locked")
        self.git("worktree", "lock", str(locked))
        held = self.linked("gone-held")
        self.hold(held)
        intact = self.linked("intact")
        for path in (gone, locked, held):
            shutil.rmtree(path)
        report = self.sweep("--remove", env=self.stub_github())
        row = self.row(report, gone)
        self.assertEqual((row["outcome"], row["reasons"], row["branch_outcome"]),
                         ("pruned", [], None))
        self.assertNotIn(str(gone), self.registered())
        self.assertTrue(self.has_branch("gone"))
        self.assertIn("locked", self.row(report, locked)["reasons"])
        self.assertIn("held", self.row(report, held)["reasons"])
        for path in (locked, held, intact):
            self.assertIn(str(path), self.registered())
        self.assertTrue(intact.is_dir())
        self.assertEqual(report["counts"]["pruned"], 1)
        self.assertEqual(self.asked_github_about(), [])

    def test_a_vanished_directory_that_reappears_is_not_pruned(self):
        gone = self.linked("gone")
        shutil.rmtree(gone)
        lsof = self.before_look(2, f"mkdir '{gone}'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), gone)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["reappeared"]))
        self.assertIn(str(gone), self.registered())

    def test_a_vanished_worktree_whose_record_holds_work_is_not_pruned(self):
        detached = self.root / "detached"
        self.git("worktree", "add", "--quiet", "--detach", str(detached))
        self.commit("only copy", cwd=detached)
        staged = self.linked("staged")
        (staged / "notes").write_text("staged\n")
        self.git("add", "notes", cwd=staged)
        rebasing = self.linked("rebasing")
        self.rebase_to_edit(rebasing)
        for path in (detached, staged):
            shutil.rmtree(path)
        # Moved rather than deleted: git's record is all that still connects the copy.
        rebasing.rename(self.root / "moved")
        report = self.sweep("--remove", env=self.stub_github())
        for path, reason in ((detached, "unreferenced-head"), (staged, "uncommitted-changes"),
                             (rebasing, "operation-in-progress")):
            with self.subTest(path.name):
                row = self.row(report, path)
                self.assertIs(row["exists"], False)
                self.assertEqual((row["outcome"], row["reasons"]), ("declined", [reason]))
                self.assertIn(str(path), self.registered())
        self.assertEqual(report["counts"]["pruned"], 0)

    def submodule_host(self, name):
        """A worktree with a checked-out submodule holding a commit its upstream never had."""
        library = self.root / f"{name}-library"
        self.git("init", "--quiet", str(library), cwd=self.root)
        self.commit("library", cwd=library)
        host = self.linked(name)
        self.git("-c", "protocol.file.allow=always", "submodule", "--quiet", "add",
                 str(library), "library", cwd=host)
        self.commit("only copy", cwd=host / "library")
        self.git("add", "library", cwd=host)
        self.commit("add library", cwd=host)
        return host

    def test_a_vanished_worktree_keeps_its_submodule_repositories(self):
        host = self.submodule_host("host")
        record = os.fsdecode(self.git("rev-parse", "--absolute-git-dir", cwd=host)).strip()
        shutil.rmtree(host)
        row = self.row(self.sweep("--remove", env=self.stub_github()), host)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["contains-submodule"]))
        self.assertTrue(os.path.isdir(os.path.join(record, "modules", "library")))

    def test_refs_kept_in_a_worktrees_record_refuse_removal(self):
        kept, gone = self.linked("kept"), self.linked("gone")
        for path in (kept, gone):
            self.git("update-ref", "refs/worktree/saved", "HEAD", cwd=path)
        self.dead_owner(kept)
        shutil.rmtree(gone)
        report = self.sweep("--remove", env=self.stub_github())
        for path in (kept, gone):
            with self.subTest(path.name):
                row = self.row(report, path)
                self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["worktree-refs"]))
                self.assertIn(str(path), self.registered())

    def test_a_commit_made_before_the_second_look_refuses_removal(self):
        late = self.root / "late"
        self.git("worktree", "add", "--quiet", "--detach", str(late))
        self.dead_owner(late)
        lsof = self.before_look(
            2, f"git -C '{late}' -c user.name=test -c user.email=test@example.com "
               "commit --quiet --allow-empty -m late")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), late)
        self.assertEqual((row["outcome"], row["reasons"]),
                         ("declined", ["head-moved", "unreferenced-head"]))
        self.assertEqual(os.fsdecode(self.git("log", "-1", "--format=%s", cwd=late)).strip(), "late")

    def test_a_branch_being_rebased_elsewhere_is_not_deleted(self):
        rebasing = self.linked("rebasing", branch="topic")
        self.rebase_to_edit(rebasing)
        forced = self.root / "forced"
        self.git("worktree", "add", "--quiet", "--force", str(forced), "topic")
        self.dead_owner(forced)
        tip = self.tip("topic")
        env = self.stub_github({"topic": [{"headRefOid": tip, "isCrossRepository": False}]})
        row = self.row(self.sweep("--remove", env=env), forced)
        self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                         ("removed", "kept", ["in-another-worktree"]))
        self.assertEqual(self.tip("topic"), tip)

    def test_an_uninspectable_worktree_lists_no_guessed_refusals(self):
        if os.geteuid() == 0:
            self.skipTest("permission checks do not bind root")
        parent = self.root / "sealed"
        hidden = self.linked("hidden", base=parent)
        parent.chmod(0)
        self.addCleanup(parent.chmod, 0o755)
        guarded = self.linked("guarded")
        self.dead_owner(guarded)
        self.lock(guarded / ".git-loopy")
        report = self.sweep("--remove", expected=1, env=self.stub_github())
        row = self.row(report, hidden)
        self.assertIsNone(row["exists"])
        self.assertEqual(row["reasons"], ["inspection-errors"])
        self.assertEqual(self.row(report, guarded)["reasons"], ["inspection-errors"])

    def test_a_worktree_registered_inside_a_candidate_mid_sweep_is_not_deleted(self):
        outer = self.linked("outer")
        self.ignore(outer, ".worktrees/")
        self.dead_owner(outer)
        inner = outer / ".worktrees" / "inner"
        lsof = self.before_look(
            2, f"git -C '{outer}' worktree add --quiet -b inner '{inner}' && echo work > '{inner}/notes'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), outer)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["contains-worktree"]))
        self.assertEqual((inner / "notes").read_text(), "work\n")

    def test_an_open_ledger_row_leaves_its_worktree_to_chain_sh(self):
        reserved, row = self.reservation("reserved", os.getpid(), self.process_start(os.getpid()))
        finished = self.linked("finished")
        for path in (reserved, finished):
            self.dead_owner(path)
        ledger = self.root / "subagents.jsonl"
        ledger.write_text(json.dumps(row) + "\n"
                          + json.dumps({"worktree": str(finished), "finish_time": "done"}) + "\n")
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github())
        row = self.row(report, reserved)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["ledger-owned"]))
        self.assertTrue(reserved.is_dir())
        self.assertEqual(self.row(report, finished)["outcome"], "removed")

    def interrupted_transaction(self, name):
        """Make the worktree of a reserve killed before its row landed, and its pending record."""
        branch = f"git-loopy/reservation-{name}"
        path = self.linked(name, branch=branch)
        self.dead_owner(path)
        record = json.dumps({"worktree": str(path), "branch": branch, "commit": "row",
                             "reservation_id": "interrupted"})
        return path, branch, record

    def test_chain_recover_rolls_back_an_interrupted_transaction_first(self):
        ledger = self.root / "subagents.jsonl"
        pending, branch, record = self.interrupted_transaction("pending")
        Path(str(ledger) + ".pending").write_text(record + "\n")
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github())
        # chain.sh undid its own transaction, so the sweep never saw the worktree.
        self.assertEqual(report["recovered"], {"recovered": 0, "targets": []})
        self.assertNotIn(str(pending), {row["path"] for row in report["worktrees"]})
        self.assertFalse(pending.exists())
        self.assertFalse(self.has_branch(branch))
        self.assertFalse(Path(str(ledger) + ".pending").exists())

    def test_a_transaction_interrupted_mid_sweep_leaves_its_worktree_to_chain_sh(self):
        ledger = self.root / "subagents.jsonl"
        pending, _, record = self.interrupted_transaction("pending")
        lsof = self.before_look(1, f"echo '{record}' > '{ledger}.pending'")
        row = self.row(self.sweep("--remove", "--ledger", str(ledger),
                                  env=self.stub_github(path=[lsof])), pending)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["ledger-owned"]))
        self.assertTrue(pending.is_dir())

    def test_a_lock_or_ledger_row_added_before_removal_refuses_it(self):
        locked, reserved = self.linked("locked"), self.linked("reserved")
        for path in (locked, reserved):
            self.dead_owner(path)
        ledger = self.root / "subagents.jsonl"
        row = json.dumps({"worktree": str(reserved), "finish_time": ""})
        lsof = self.before_look(2, f"git -C '{self.repo}' worktree lock '{locked}' && "
                                f"echo '{row}' > '{ledger}'")
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github(path=[lsof]))
        self.assertEqual(self.row(report, locked)["reasons"], ["locked"])
        self.assertEqual(self.row(report, reserved)["reasons"], ["ledger-owned"])
        for path in (locked, reserved):
            self.assertTrue(path.is_dir())

    def test_a_holder_that_arrives_during_earlier_removals_still_refuses(self):
        first, second = self.linked("first"), self.linked("second")
        for path in (first, second):
            self.dead_owner(path)
        # The third look precedes the second candidate's removal, whichever candidate that is.
        lsof = self.before_look(3, f"printf 'p1\\0R0\\0n%s\\0p1\\0R0\\0n%s\\0' '{first}' '{second}'")
        report = self.sweep("--remove", env=self.stub_github(path=[lsof]))
        rows = [self.row(report, path) for path in (first, second)]
        self.assertEqual(sorted(row["outcome"] for row in rows), ["declined", "removed"])
        declined = next(row for row in rows if row["outcome"] == "declined")
        self.assertEqual((declined["reasons"], declined["holder_pids"]), (["held"], [1]))
        self.assertTrue(Path(declined["path"]).is_dir())

    def test_files_in_an_uninitialised_submodule_directory_refuse_removal(self):
        library = self.root / "library"
        self.git("init", "--quiet", str(library), cwd=self.root)
        self.commit("library", cwd=library)
        self.git("-c", "protocol.file.allow=always", "submodule", "--quiet", "add",
                 str(library), "library")
        self.commit("add library")
        written, empty = self.linked("written"), self.linked("empty")
        (written / "library" / "notes").write_text("work\n")
        for path in (written, empty):
            self.dead_owner(path)
        report = self.sweep("--remove", env=self.stub_github())
        row = self.row(report, written)
        self.assertIs(row["dirty"], False)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["contains-submodule"]))
        self.assertEqual((written / "library" / "notes").read_text(), "work\n")
        self.assertEqual(self.row(report, empty)["outcome"], "removed")

    def test_a_look_that_fails_after_a_removal_still_reports_it(self):
        first, second = self.linked("first"), self.linked("second")
        for path in (first, second):
            self.dead_owner(path)
        lsof = self.before_look(3, "echo 'lsof: cannot inspect' >&2")
        report = self.sweep("--remove", expected=1, env=self.stub_github(path=[lsof]))
        rows = [self.row(report, path) for path in (first, second)]
        self.assertEqual(sorted(row["outcome"] for row in rows), ["declined", "removed"])
        declined = next(row for row in rows if row["outcome"] == "declined")
        self.assertEqual(declined["reasons"], ["inspection-errors"])
        self.assertTrue(Path(declined["path"]).is_dir())
        removed = next(row for row in rows if row["outcome"] == "removed")
        self.assertEqual(removed["branch_reasons"], ["not-merged"])

    def test_a_marker_claimed_during_removal_is_never_overwritten(self):
        late = self.linked("late")
        self.dead_owner(late)
        marker = late / ".git-loopy" / "worktree-owner"
        git = self.during_worktree_remove(f"mkdir -p '{marker.parent}' && printf 'claimed' > '{marker}'")
        row = self.row(self.sweep("--remove", expected=1, env=self.stub_github(path=[git])), late)
        self.assertEqual((row["outcome"], row["reasons"]),
                         ("declined", ["removal-failed", "marker-changed"]))
        self.assertEqual(marker.read_text(), "claimed")

    def test_an_unfinished_notes_merge_refuses_removal(self):
        self.git(*IDENTITY, "notes", "add", "-m", "ours")
        self.git(*IDENTITY, "notes", "--ref", "other", "add", "-m", "theirs")
        noting = self.linked("noting")
        merge = subprocess.run(["git", "-C", str(noting), *IDENTITY, "notes", "merge", "other"],
                               capture_output=True)
        self.assertEqual(merge.returncode, 1, "the notes merge should stop on its conflict")
        self.dead_owner(noting)
        row = self.row(self.sweep("--remove", env=self.stub_github()), noting)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["operation-in-progress"]))

    def test_an_orphan_worktrees_unborn_branch_needs_no_decision(self):
        fresh = self.root / "fresh"
        added = subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "--quiet",
                                "--orphan", "-b", "fresh", str(fresh)], capture_output=True)
        if added.returncode:
            self.skipTest("this git cannot add an orphan worktree")
        self.dead_owner(fresh)
        row = self.row(self.sweep("--remove", env=self.stub_github()), fresh)
        self.assertEqual((row["outcome"], row["branch_outcome"], row["errors"]), ("removed", None, []))
        self.assertEqual(self.asked_github_about(), [])

    def reservation(self, name, parent_pid, parent_start, bound=False):
        """Leave the worktree, marker and open ledger row chain.sh reserve would."""
        path = self.linked(name, branch=f"git-loopy/reservation-{name}")
        self.mark(path, parent_pid, parent_start)
        # A fresh spawn time, so only a dead parent, never age, lets recover reclaim it.
        spawned = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        row = {"reservation_id": name, "route": "/implement", "target": f"issue-{name}",
               "spawn_time": spawned.replace("+00:00", "Z"), "worktree": str(path), "chain_depth": 1,
               "parent_pid": parent_pid, "parent_start": parent_start,
               "finish_time": "", "outcome": ""}
        if bound:
            row.update(agent_id="agent", agent_type="implement-agent", session_id="session")
        return path, row

    def ended_process(self):
        ended = subprocess.Popen(["true"])
        ended.wait()
        return ended.pid, "Mon Jan 1 00:00:00 2001"

    def trace_bash(self):
        """Return an environment in which every bash script logs its path and arguments."""
        self.bash_log = self.root / "bash.log"
        tracer = self.root / "trace.sh"
        tracer.write_text(f'printf "%s\\n" "$0 $*" >> "{self.bash_log}"\n')
        return {"BASH_ENV": str(tracer)}

    def test_remove_hands_orphaned_reservations_to_chain_recover(self):
        orphan, row = self.reservation("orphan", *self.ended_process())
        ledger = self.write_ledger(row)
        chain = Path(os.environ["SWEEP"]).with_name("chain.sh")
        recover = f"{chain} recover --ledger {ledger} --stale-after-seconds 300"
        # A report recovers nothing.
        report = self.sweep("--ledger", str(ledger), env={**os.environ, **self.trace_bash()})
        self.assertNotIn(recover, self.bash_log.read_text().splitlines())
        self.assertNotIn("recovered", report)
        self.assertEqual(json.loads(ledger.read_text()), row)
        env = {**self.stub_github(), **self.trace_bash()}
        env.pop("CHAIN_RESERVATION_STALE_SECONDS", None)
        report = self.sweep("--remove", "--ledger", str(ledger), env=env)
        self.assertEqual(self.bash_log.read_text().splitlines().count(recover), 1)
        reclaimed = json.loads(ledger.read_text())
        self.assertEqual(reclaimed["outcome"], "reclaimed")
        self.assertTrue(reclaimed["finish_time"])
        self.assertEqual(report["recovered"], {"recovered": 1, "targets": ["issue-orphan"]})
        self.assertFalse(orphan.exists())
        self.assertNotIn(str(orphan), self.registered())
        self.assertNotIn(str(orphan), {listed["path"] for listed in report["worktrees"]})

    def test_a_dirty_orphaned_reservation_is_retained_by_recover_then_refused(self):
        orphan, row = self.reservation("orphan", *self.ended_process())
        (orphan / "notes").write_text("work\n")
        ledger = self.write_ledger(row)
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github())
        self.assertEqual(report["recovered"]["retained_worktrees"], [str(orphan)])
        self.assertEqual(json.loads(ledger.read_text())["outcome"], "reclaimed")
        listed = self.row(report, orphan)
        self.assertEqual((listed["outcome"], listed["reasons"]),
                         ("declined", ["uncommitted-changes"]))
        self.assertEqual((orphan / "notes").read_text(), "work\n")

    def test_recover_keeps_reclaimed_worktrees_containing_unique_work(self):
        detached, detached_row = self.reservation("detached", *self.ended_process())
        self.git("checkout", "--quiet", "--detach", cwd=detached)
        self.commit("only copy", cwd=detached)
        head = os.fsdecode(self.git("rev-parse", "HEAD", cwd=detached)).strip()
        vanished, vanished_row = self.reservation("vanished", *self.ended_process())
        (vanished / "notes").write_text("staged\n")
        self.git("add", "notes", cwd=vanished)
        shutil.rmtree(vanished)
        ledger = self.write_ledger(detached_row, vanished_row)
        result = self.sweep_result("--remove", "--ledger", str(ledger), env=self.stub_github())
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["recovered"]["recovered"], 2)
        self.assertEqual(sorted(report["recovered"]["retained_worktrees"]),
                         sorted([str(detached), str(vanished)]))
        self.assertIn("contains work that exists nowhere else", result.stderr)
        self.assertEqual(self.row(report, detached)["reasons"], ["unreferenced-head"])
        self.assertEqual(self.row(report, vanished)["reasons"], ["uncommitted-changes"])
        self.assertEqual(os.fsdecode(self.git("rev-parse", "HEAD", cwd=detached)).strip(), head)
        self.assertIn(str(vanished), self.registered())

    def test_judge_names_what_removal_would_destroy(self):
        clean, dirty = self.linked("clean"), self.linked("dirty")
        (dirty / "notes").write_text("work\n")
        detached = self.root / "detached"
        self.git("worktree", "add", "--quiet", "--detach", str(detached))
        self.commit("only copy", cwd=detached)
        for path, expected in ((clean, []), (dirty, ["uncommitted-changes"]),
                               (detached, ["unreferenced-head"]), (self.repo, ["main-worktree"]),
                               (self.root / "never-existed", [])):
            with self.subTest(path.name):
                self.assertEqual(self.sweep("--judge", str(path)), expected)
        self.assertTrue(dirty.is_dir())
        # An existing directory it cannot place, or cannot inspect, is never judged harmless.
        (self.root / "unregistered").mkdir()
        result = self.sweep_result("--judge", str(self.root / "unregistered"))
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("not a registered worktree", result.stderr)
        for args in (("--judge", str(clean), "--remove"), ("--judge", "")):
            with self.subTest(args):
                result = self.sweep_result(*args)
                self.assertEqual((result.returncode, result.stdout), (2, ""))

    def test_judge_finds_a_worktree_named_in_another_spelling(self):
        composed = self.root / "caf\u00e9"
        decomposed = self.root / "cafe\u0301"
        self.git("worktree", "add", "--quiet", "--detach", str(composed))
        if not decomposed.exists():
            self.skipTest("this file system tells the two Unicode spellings apart")
        self.commit("only copy", cwd=composed)
        self.assertEqual(self.sweep("--judge", str(decomposed)), ["unreferenced-head"])

    def test_a_failed_sweep_still_says_what_recover_did(self):
        orphan, row = self.reservation("orphan", *self.ended_process())
        ledger = self.write_ledger(row)
        lsof = self.before_look(1, "echo 'lsof: cannot inspect' >&2")
        result = self.sweep_result("--remove", "--ledger", str(ledger),
                                   env=self.stub_github(path=[lsof]))
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("chain.sh recover had already run", result.stderr)
        self.assertIn("issue-orphan", result.stderr)

    def test_a_sweep_still_finishes_when_recovery_removes_the_checkout_it_named(self):
        orphan, row = self.reservation("orphan", *self.ended_process())
        ledger = self.write_ledger(row)
        result = subprocess.run(["bash", os.environ["SWEEP"], "--repo", str(orphan), "--remove",
                                 "--ledger", str(ledger)], cwd=self.root, capture_output=True,
                                text=True, env=self.stub_github())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["recovered"]["targets"], ["issue-orphan"])
        self.assertFalse(orphan.exists())

    def test_an_empty_reservation_threshold_means_the_default_as_it_does_for_plan(self):
        report = self.sweep("--remove", env={**self.stub_github(),
                                             "CHAIN_RESERVATION_STALE_SECONDS": ""})
        self.assertEqual(report["recovered"], {"recovered": 0, "targets": []})

    def test_a_live_bound_reservation_is_left_to_chain_sh(self):
        live, row = self.reservation("live", os.getpid(), self.process_start(os.getpid()),
                                     bound=True)
        # Even a marker that would vouch for the directory yields to the open row.
        self.dead_owner(live)
        ledger = self.write_ledger(row)
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github())
        self.assertEqual(report["recovered"], {"recovered": 0, "targets": []})
        listed = self.row(report, live)
        self.assertEqual((listed["outcome"], listed["reasons"]), ("declined", ["ledger-owned"]))
        self.assertEqual(json.loads(ledger.read_text()), row)
        self.assertTrue(live.is_dir())

    def test_a_ledger_spelling_another_normalization_still_owns_its_worktree(self):
        live, row = self.reservation("caf\u00e9", os.getpid(), self.process_start(os.getpid()),
                                     bound=True)
        decomposed = self.root / "cafe\u0301"
        if not decomposed.exists():
            self.skipTest("this file system tells the two Unicode spellings apart")
        self.dead_owner(live)
        row["worktree"] = str(decomposed)
        ledger = self.write_ledger(row)
        listed = self.row(self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github()), live)
        self.assertEqual((listed["outcome"], listed["reasons"]), ("declined", ["ledger-owned"]))
        self.assertEqual(listed["ledger_rows"], 1)
        self.assertTrue(live.is_dir())

    def test_a_repository_without_a_ledger_still_sweeps(self):
        done = self.linked("done")
        self.dead_owner(done)
        report = self.sweep("--remove", env=self.stub_github())
        self.assertEqual(report["recovered"], {"recovered": 0, "targets": []})
        self.assertEqual(self.row(report, done)["outcome"], "removed")
        self.assertFalse((self.repo / ".git-loopy" / "subagents.jsonl").exists())

    def test_recovering_a_vanished_reservation_prunes_no_other_worktree(self):
        orphan, row = self.reservation("orphan", *self.ended_process())
        kept = self.linked("kept")
        (kept / "notes").write_text("staged\n")
        self.git("add", "notes", cwd=kept)
        for path in (orphan, kept):
            shutil.rmtree(path)
        ledger = self.write_ledger(row)
        report = self.sweep("--remove", "--ledger", str(ledger), env=self.stub_github())
        self.assertEqual(report["recovered"]["recovered"], 1)
        self.assertNotIn(str(orphan), self.registered())
        self.assertIn(str(kept), self.registered())
        self.assertEqual(self.row(report, kept)["reasons"], ["uncommitted-changes"])

    def test_a_branch_check_that_cannot_read_gits_records_keeps_the_branch(self):
        if os.geteuid() == 0:
            self.skipTest("permission checks do not bind root")
        done = self.linked("done")
        self.dead_owner(done)
        # A bystander keeps git's worktree records directory alive after the removal.
        self.linked("bystander")
        records = self.repo / ".git" / "worktrees"
        env = self.stub_github({"done": [{"headRefOid": self.tip("done"), "isCrossRepository": False}]},
                               run=f"chmod 0 '{records}'")
        self.addCleanup(records.chmod, 0o755)
        row = self.row(self.sweep("--remove", expected=1, env=env), done)
        records.chmod(0o755)
        self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                         ("removed", "kept", ["branch-check-failed"]))
        self.assertTrue(row["errors"])
        self.assertTrue(self.has_branch("done"))

    def test_a_registration_that_moves_before_removal_is_left_alone(self):
        late = self.linked("late")
        self.dead_owner(late)
        moved = self.root / "moved"
        lsof = self.before_look(2, f"git -C '{self.repo}' worktree move '{late}' '{moved}'")
        row = self.row(self.sweep("--remove", env=self.stub_github(path=[lsof])), late)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["registration-changed"]))
        self.assertIn(str(moved), self.registered())

    def test_a_branch_bisected_or_rewritten_elsewhere_is_not_deleted(self):
        bisecting = self.linked("bisecting", branch="bisected")
        self.commit("one", cwd=bisecting)
        self.commit("two", cwd=bisecting)
        for step in (("start",), ("bad",), ("good", "HEAD~2")):
            self.git("bisect", *step, cwd=bisecting)
        stacked = self.linked("stacked", branch="stack")
        self.commit("lower", cwd=stacked)
        self.git("branch", "lower", cwd=stacked)
        self.rebase_to_edit(stacked, "--update-refs", upstream="HEAD~3")
        pulls = {}
        for branch in ("bisected", "lower"):
            forced = self.root / f"forced-{branch}"
            self.git("worktree", "add", "--quiet", "--force", str(forced), branch)
            self.dead_owner(forced)
            pulls[branch] = [{"headRefOid": self.tip(branch), "isCrossRepository": False}]
        report = self.sweep("--remove", env=self.stub_github(pulls))
        for branch in ("bisected", "lower"):
            with self.subTest(branch):
                row = self.row(report, self.root / f"forced-{branch}")
                self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                                 ("removed", "kept", ["in-another-worktree"]))
                self.assertTrue(self.has_branch(branch))

    def test_a_vanished_worktree_registered_by_relative_path_is_pruned(self):
        relative = self.root / "relative"
        self.git("-c", "worktree.useRelativePaths=true", "worktree", "add", "--quiet",
                 "-b", "relative", str(relative))
        shutil.rmtree(relative)
        row = self.row(self.sweep("--remove", env=self.stub_github()), relative)
        self.assertEqual((row["outcome"], row["reasons"]), ("pruned", []))
        self.assertNotIn(str(relative), self.registered())

    def test_worktrees_forced_onto_one_branch_share_its_decision(self):
        shared = self.linked("shared")
        twin = self.root / "twin"
        self.git("worktree", "add", "--quiet", "--force", str(twin), "shared")
        for path in (shared, twin):
            self.dead_owner(path)
        env = self.stub_github({"shared": [{"headRefOid": self.tip("shared"), "isCrossRepository": False}]})
        report = self.sweep("--remove", env=env)
        for path in (shared, twin):
            row = self.row(report, path)
            self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                             ("removed", "deleted", []))
        self.assertFalse(self.has_branch("shared"))
        self.assertEqual(self.asked_github_about(), ["shared"])

    def test_a_branch_stays_while_a_twin_on_it_stays(self):
        pulls = {}
        for branch, keep_twin in (("pruned-twin", lambda twin: shutil.rmtree(twin)),
                                  ("dirty-twin", lambda twin: (twin / "notes").write_text("work\n"))):
            removed = self.linked(f"{branch}-removed", branch=branch)
            twin = self.root / f"{branch}-twin"
            self.git("worktree", "add", "--quiet", "--force", str(twin), branch)
            for path in (removed, twin):
                self.dead_owner(path)
            keep_twin(twin)
            pulls[branch] = [{"headRefOid": self.tip(branch), "isCrossRepository": False}]
        report = self.sweep("--remove", env=self.stub_github(pulls))
        for branch, twin_outcome, reason in (("pruned-twin", "pruned", "twin-not-removed"),
                                             ("dirty-twin", "declined", "in-another-worktree")):
            with self.subTest(branch):
                row = self.row(report, self.root / f"{branch}-removed")
                self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                                 ("removed", "kept", [reason]))
                twin = self.row(report, self.root / f"{branch}-twin")
                self.assertEqual((twin["outcome"], twin["branch_outcome"]), (twin_outcome, None))
                self.assertTrue(self.has_branch(branch))
        self.assertEqual(self.asked_github_about(), [])

    def test_a_branch_that_moves_during_the_lookup_is_kept(self):
        moving = self.linked("moving")
        self.dead_owner(moving)
        tip = self.tip("moving")
        self.commit("elsewhere")
        env = self.stub_github({"moving": [{"headRefOid": tip, "isCrossRepository": False}]},
                          run=f"git -C '{self.repo}' update-ref refs/heads/moving HEAD")
        row = self.row(self.sweep("--remove", env=env), moving)
        self.assertEqual((row["outcome"], row["branch_outcome"], row["branch_reasons"]),
                         ("removed", "kept", ["branch-moved"]))
        self.assertNotEqual(self.tip("moving"), tip)

    def test_a_checked_out_submodule_is_a_named_refusal(self):
        host = self.submodule_host("host")
        self.dead_owner(host)
        row = self.row(self.sweep("--remove", env=self.stub_github()), host)
        self.assertIs(row["dirty"], False)
        self.assertEqual((row["outcome"], row["reasons"]), ("declined", ["contains-submodule"]))
        self.assertTrue((host / "library" / ".git").exists())

    def test_branch_checked_out_elsewhere_is_kept_without_asking_github(self):
        shared = self.linked("shared")
        twin = self.root / "twin"
        self.git("worktree", "add", "--quiet", "--force", str(twin), "shared")
        self.dead_owner(shared)
        row = self.row(self.sweep("--remove", env=self.stub_github()), shared)
        self.assertEqual(row["outcome"], "removed")
        self.assertEqual((row["branch_outcome"], row["branch_reasons"]),
                         ("kept", ["in-another-worktree"]))
        self.assertTrue(self.has_branch("shared"))
        self.assertTrue(twin.is_dir())
        self.assertEqual(self.asked_github_about(), [])

    def test_unanswered_merge_question_keeps_the_branch_and_fails_the_sweep(self):
        lonely = self.linked("lonely")
        twin = self.root / "twin"
        self.git("worktree", "add", "--quiet", "--force", str(twin), "lonely")
        for path in (lonely, twin):
            self.dead_owner(path)
        report = self.sweep("--remove", expected=1, env=self.stub_github(fail=True))
        for path in (lonely, twin):
            with self.subTest(path.name):
                row = self.row(report, path)
                self.assertEqual(row["outcome"], "removed")
                self.assertEqual((row["branch_outcome"], row["branch_reasons"]),
                                 ("kept", ["merge-status-unknown"]))
                self.assertTrue(any("Bad Gateway" in error for error in row["errors"]))
        self.assertTrue(self.has_branch("lonely"))

    def test_a_hooks_exported_repository_never_redirects_the_sweep(self):
        other = self.root / "other"
        self.git("init", "--quiet", str(other), cwd=self.root)
        self.commit("other", cwd=other)
        bystander = self.root / "bystander"
        self.git("worktree", "add", "--quiet", "-b", "bystander", str(bystander), cwd=other)
        self.dead_owner(bystander)
        staged = self.linked("staged")
        self.dead_owner(staged)
        (staged / "notes").write_text("staged\n")
        self.git("add", "notes", cwd=staged)
        # What a git hook running in the other repository exports to its children.
        hook = {"GIT_DIR": str(other / ".git"), "GIT_WORK_TREE": str(other),
                "GIT_INDEX_FILE": str(other / ".git" / "index")}
        report = self.sweep("--remove", env={**self.stub_github(), **hook})
        self.assertEqual({row["path"] for row in report["worktrees"]}, {str(self.repo), str(staged)})
        self.assertIn("uncommitted-changes", self.row(report, staged)["reasons"])
        self.assertTrue((bystander / ".git").is_file())

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
