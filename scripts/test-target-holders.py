#!/usr/bin/env python3
"""Exercise the read-only holder command against a repository and tracker fixture."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / "skills/next/scripts/target-holders.py"


class TargetHolderTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.env = {**os.environ, "GH_REPO": "fixture/repo"}
        self.git("init", "--quiet")
        self.git("-c", "user.name=test", "-c", "user.email=test@example.com",
                 "commit", "--quiet", "--allow-empty", "-m", "initial")
        self.ledger = self.root / ".git-loopy/subagents.jsonl"
        self.references = []
        self.prs = {}
        self.bin = self.root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text(
            "#!" + sys.executable + "\n"
            "import json, os, re, sys\n"
            "args = sys.argv[1:]\n"
            "if os.environ.get('FIXTURE_GH_FAIL'):\n"
            "    sys.exit('tracker unavailable')\n"
            "prs = json.loads(os.environ['FIXTURE_PRS'])\n"
            "if args[:2] == ['api', 'graphql']:\n"
            "    query = next(a[6:] for a in args if a.startswith('query='))\n"
            "    nodes = {}\n"
            "    for alias, number in re.findall(r'(target\\d+):issueOrPullRequest"
            r"\(number:(\d+)\)', query):" + "\n"
            "        nodes[alias] = ({'__typename': 'PullRequest', "
            "'closingIssuesReferences': {'nodes': [{'number': 15}]}} "
            "if number in prs else {'__typename': 'Issue', 'number': int(number)})\n"
            "    print(json.dumps({'data': {'repository': nodes}}))\n"
            "elif args[:2] == ['issue', 'view']:\n"
            "    print(json.dumps({'closedByPullRequestsReferences': "
            "json.loads(os.environ['FIXTURE_REFERENCES'])}))\n"
            "elif args[:2] == ['pr', 'view']:\n"
            "    print(json.dumps(prs[args[2]]))\n"
            "else:\n"
            "    sys.exit('unexpected gh command: ' + repr(args))\n",
            encoding="utf-8",
        )
        gh.chmod(0o755)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.root), *args], text=True, stderr=subprocess.PIPE,
        ).strip()

    def write_rows(self, rows):
        self.ledger.parent.mkdir(exist_ok=True)
        self.ledger.write_text(
            "".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8",
        )

    def add_pr(self, number=42, state="OPEN", branch="implementation"):
        self.references.append({"number": number})
        self.prs[str(number)] = {
            "number": number, "state": state, "headRefName": branch,
            "url": "https://github.com/fixture/repo/pull/" + str(number),
        }

    def holders(self, target="issue-15", cwd=None, *args):
        before = {
            str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()
        }
        result = subprocess.run(
            [sys.executable, str(COMMAND), "--target", target, *args],
            cwd=cwd or self.root,
            env={**self.env, "FIXTURE_PRS": json.dumps(self.prs),
                 "FIXTURE_REFERENCES": json.dumps(self.references)},
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {
            str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()
        }, "holder lookup must leave the repository byte-for-byte unchanged")
        return json.loads(result.stdout)

    def test_open_closing_pull_request_holds_the_target(self):
        self.add_pr()
        report = self.holders()
        self.assertEqual(report["canonical_target"], "issue-15")
        self.assertTrue(report["held"])
        self.assertEqual(report["holders"], [{
            "kind": "pull-request", "number": 42, "branch": "implementation",
            "url": "https://github.com/fixture/repo/pull/42", "own": False,
        }])

    def test_open_bound_rows_hold_all_equivalent_target_spellings(self):
        self.add_pr(state="CLOSED")
        self.write_rows([
            {"target": "42", "session_id": "session-a", "agent_id": "agent-a",
             "worktree": str(self.root / "reserved"), "finish_time": None},
            {"target": "issue-15", "session_id": "finished", "agent_id": "finished",
             "finish_time": "2026-11-06T00:00:00Z"},
            {"target": "15", "session_id": "reservation", "finish_time": None},
            {"target": "issue-99", "session_id": "other", "agent_id": "other"},
        ])
        for target in ("15", "issue-15", "42"):
            with self.subTest(target=target):
                report = self.holders(target)
                self.assertEqual(report["canonical_target"], "issue-15")
                self.assertTrue(report["held"])
                self.assertEqual(report["holders"], [{
                    "kind": "bound-run", "session_id": "session-a", "agent_id": "agent-a",
                    "worktree": str(self.root / "reserved"), "own": False,
                }])

    def test_live_head_branch_owner_is_reported_but_dead_owner_is_not(self):
        self.add_pr()
        worktree = self.root / "implementation-worktree"
        self.git("worktree", "add", "--quiet", "-b", "implementation", str(worktree))
        marker = worktree / ".git-loopy/worktree-owner"
        marker.parent.mkdir()
        start = " ".join(subprocess.check_output(
            ["ps", "-o", "lstart=", "-p", str(os.getpid())],
            env={**os.environ, "TZ": "UTC"}, text=True,
        ).split())
        marker.write_text(str(os.getpid()) + "\t" + start + "\n", encoding="utf-8")
        report = self.holders()
        self.assertEqual(len(report["holders"]), 2)
        self.assertIn({
            "kind": "worktree-owner", "worktree": str(worktree), "branch": "implementation",
            "number": 42, "owner_pid": os.getpid(), "owner_start": start, "own": False,
        }, report["holders"])
        marker.write_text("2147483647\t" + start + "\n", encoding="utf-8")
        self.assertEqual([h["kind"] for h in self.holders()["holders"]], ["pull-request"])
        # A reused live PID with a different start is also a dead marker.
        marker.write_text(str(os.getpid()) + "\tThu Jan 1 00:00:00 1970\n", encoding="utf-8")
        self.assertEqual([h["kind"] for h in self.holders()["holders"]], ["pull-request"])

    def test_own_linked_worktree_and_remediation_branch_pass_without_hiding_holders(self):
        self.add_pr()
        worktree = self.root / "owned"
        self.git("worktree", "add", "--quiet", "-b", "implementation", str(worktree))
        self.write_rows([{
            "target": "issue-15", "session_id": "caller", "agent_id": "caller-agent",
            "worktree": str(worktree),
        }])
        report = self.holders(cwd=worktree)
        self.assertFalse(report["held"])
        self.assertEqual(len(report["holders"]), 2)
        self.assertTrue(all(holder["own"] for holder in report["holders"]))
        report = self.holders("issue-15", self.root, "--caller-branch", "implementation")
        self.assertFalse(report["held"])
        self.assertTrue(all(holder["own"] for holder in report["holders"]))
        self.write_rows([{
            "target": "issue-15", "session_id": "foreign", "agent_id": "foreign-agent",
            "worktree": str(self.root / "elsewhere"),
        }])
        report = self.holders(cwd=worktree)
        self.assertTrue(report["held"], "an own PR must not mask another bound run")
        self.assertFalse(report["holders"][0]["own"])

    def test_own_claimed_worktree_passes_without_a_pull_request(self):
        self.write_rows([{
            "target": "15", "session_id": "caller", "agent_id": "caller-agent",
            "worktree": str(self.root),
        }])
        report = self.holders()
        self.assertFalse(report["held"])
        self.assertEqual(report["holders"][0]["session_id"], "caller")
        self.assertTrue(report["holders"][0]["own"])

    def test_unheld_target_reports_no_holders_and_creates_no_ledger(self):
        self.add_pr(state="MERGED")
        report = self.holders()
        self.assertEqual(report, {
            "canonical_target": "issue-15", "held": False, "holders": [],
        })
        self.assertFalse(self.ledger.exists())

    def test_remediation_branch_matches_a_reserved_rows_recorded_branch(self):
        self.write_rows([{
            "target": "issue-15", "session_id": "caller", "agent_id": "caller-agent",
            "worktree": str(self.root / "reserved"), "worktree_branch": "remediation",
        }])
        report = self.holders("15", self.root, "--caller-branch", "remediation")
        self.assertFalse(report["held"])
        self.assertTrue(report["holders"][0]["own"])

    def test_separate_git_directory_uses_the_primary_ledger_without_writing_an_anchor(self):
        primary = self.root / "separate"
        metadata = self.root / "metadata"
        subprocess.run([
            "git", "init", "--quiet", "--separate-git-dir", str(metadata), str(primary),
        ], check=True)
        self.ledger = primary / ".git-loopy/subagents.jsonl"
        self.write_rows([{
            "target": "issue-15", "session_id": "foreign", "agent_id": "foreign-agent",
            "worktree": str(self.root / "foreign"),
        }])
        report = self.holders(cwd=primary)
        self.assertTrue(report["held"])
        self.assertEqual(report["holders"][0]["session_id"], "foreign")
        self.assertFalse((metadata / "git-loopy-worktree-root").exists())

    def test_tracker_failure_is_a_blocker_not_a_free_target(self):
        self.env["FIXTURE_GH_FAIL"] = "1"
        result = subprocess.run(
            [sys.executable, str(COMMAND), "--target", "issue-15"],
            cwd=self.root,
            env={**self.env, "FIXTURE_PRS": "{}", "FIXTURE_REFERENCES": "[]"},
            capture_output=True, text=True, timeout=15,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["error"], "holder-lookup-failed")
        self.assertFalse(self.ledger.exists())


if __name__ == "__main__":
    unittest.main()
