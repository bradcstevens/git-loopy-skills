#!/usr/bin/env python3
"""Scan live GitHub Copilot CLI sessions working in this repository and log each scan.

    sessions.py scan [--repo DIR] [--state-dir DIR] [--log PATH] [--no-record]

A Copilot CLI session keeps its state in ``$COPILOT_HOME/session-state/<id>/``.
While a process holds the session it writes ``inuse.<pid>.lock``; the session
is live when that process still runs and is a ``copilot`` process (a reused
PID running anything else is not). ``workspace.yaml`` records the directory
the session started in, which places it in one of the repository's worktrees.

Each scan prints JSON to stdout and, unless ``--no-record`` is given, appends
one line to the /next session log (default
``<repository root>/.git-loopy/next/sessions.jsonl``). Every line names the
sessions that scan saw, so the next scan reports which are ``new`` since the
previous one and which have ``ended``.
"""

from __future__ import annotations

import argparse
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple

LOCK_PATTERN = re.compile(r"^inuse\.(\d+)\.lock$")
COPILOT_EXECUTABLE = re.compile(r"^copilot(?:$|[-.])", re.IGNORECASE)
WORKSPACE_FIELDS = ("id", "cwd", "git_root", "branch", "name", "client_name", "created_at", "updated_at")


def now_utc() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def real(path: str) -> str:
    return os.path.realpath(os.path.expanduser(path))


def git(repo: str, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", repo, *args], check=True, capture_output=True, text=True
    ).stdout


def list_worktrees(repo: str) -> List[Dict[str, Optional[str]]]:
    worktrees: List[Dict[str, Optional[str]]] = []
    current: Dict[str, Optional[str]] = {}
    for line in git(repo, "worktree", "list", "--porcelain").splitlines() + [""]:
        if not line:
            if current.get("path"):
                worktrees.append(current)
            current = {}
        elif line.startswith("worktree "):
            current = {"path": real(line[len("worktree "):]), "branch": None}
        elif line.startswith("branch "):
            current["branch"] = line[len("branch "):].replace("refs/heads/", "", 1)
        elif line == "detached":
            current["branch"] = None
    return worktrees


def repository_root(repo: str, worktrees: List[Dict[str, Optional[str]]]) -> str:
    """The main worktree, as chain.sh resolves it for its own ledger."""
    common_dir = real(os.path.join(repo, git(repo, "rev-parse", "--git-common-dir").strip()))
    main = worktrees[0]["path"] if worktrees else None
    if main and main != common_dir:
        return main
    # A separate-git-dir checkout: chain.sh records its working tree beside the common dir.
    anchor = os.path.join(common_dir, "git-loopy-worktree-root")
    if os.path.islink(anchor):
        return real(os.readlink(anchor))
    return real(git(repo, "rev-parse", "--show-toplevel").strip())


def copilot_processes() -> Dict[int, str]:
    output = subprocess.run(
        ["ps", "-A", "-o", "pid=,command="], check=True, capture_output=True, text=True
    ).stdout
    processes: Dict[int, str] = {}
    for line in output.splitlines():
        pid, _, command = line.strip().partition(" ")
        # The executable, or the script a runtime such as node runs, is named copilot;
        # a mere ~/.copilot path in the arguments does not make a process a session holder.
        tokens = command.split()[:2]
        if pid.isdigit() and any(COPILOT_EXECUTABLE.match(os.path.basename(t)) for t in tokens):
            processes[int(pid)] = command.strip()
    return processes


def read_workspace(path: str) -> Dict[str, str]:
    fields: Dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as workspace:
            for line in workspace:
                key, sep, value = line.partition(":")
                if sep and key in WORKSPACE_FIELDS:
                    fields[key] = value.strip().strip("'\"")
    except OSError:
        pass
    return fields


def live_sessions(state_dir: str, processes: Dict[int, str]) -> List[Dict[str, object]]:
    sessions = []
    try:
        entries = os.scandir(state_dir)
    except FileNotFoundError:
        return sessions
    with entries:
        for entry in entries:
            if not entry.is_dir():
                continue
            try:
                names = os.listdir(entry.path)
            except OSError:
                continue
            pids = sorted(int(m.group(1)) for m in map(LOCK_PATTERN.match, names) if m)
            holders = [pid for pid in pids if pid in processes]
            if not holders:
                continue
            workspace = read_workspace(os.path.join(entry.path, "workspace.yaml"))
            sessions.append(
                {
                    "session_id": workspace.get("id") or entry.name,
                    "pid": holders[-1],
                    "name": workspace.get("name"),
                    "client": workspace.get("client_name"),
                    "cwd": workspace.get("cwd"),
                    "git_root": workspace.get("git_root"),
                    "started_branch": workspace.get("branch"),
                    "created_at": workspace.get("created_at"),
                    "updated_at": workspace.get("updated_at"),
                }
            )
    return sessions


def place(path: Optional[str], worktrees: List[Dict[str, Optional[str]]]) -> Optional[Dict[str, Optional[str]]]:
    """The innermost worktree containing ``path`` (worktrees may nest under the main one)."""
    if not path:
        return None
    path = real(path)
    best = None
    for worktree in worktrees:
        root = worktree["path"] or ""
        if (path == root or path.startswith(root.rstrip(os.sep) + os.sep)) and (
            best is None or len(root) > len(best["path"] or "")
        ):
            best = worktree
    return best


def open_ledger_rows(ledger: str) -> List[Dict[str, object]]:
    rows = []
    try:
        with open(ledger, encoding="utf-8") as lines:
            for line in lines:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict) and not row.get("finish_time"):
                    rows.append(row)
    except OSError:
        pass
    return rows


def previous_scan(log_path: str) -> Optional[Dict[str, object]]:
    last = None
    try:
        with open(log_path, encoding="utf-8") as log:
            for line in log:
                line = line.strip()
                if line:
                    try:
                        last = json.loads(line)
                    except ValueError:
                        continue
    except OSError:
        return None
    return last if isinstance(last, dict) else None


def append_record(log_path: str, record: Dict[str, object]) -> None:
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as log:
        fcntl.flock(log, fcntl.LOCK_EX)
        try:
            log.write(json.dumps(record, sort_keys=True) + "\n")
            log.flush()
        finally:
            fcntl.flock(log, fcntl.LOCK_UN)


def scan(repo: str, state_dir: str, log_path: Optional[str], record: bool) -> Tuple[Dict[str, object], Optional[str]]:
    worktrees = list_worktrees(repo)
    root = repository_root(repo, worktrees)
    log_path = log_path or os.path.join(root, ".git-loopy", "next", "sessions.jsonl")
    self_id = os.environ.get("COPILOT_AGENT_SESSION_ID") or None

    ledger_rows = open_ledger_rows(os.path.join(root, ".git-loopy", "subagents.jsonl"))
    in_repo = []
    for session in live_sessions(state_dir, copilot_processes()):
        worktree = place(session["cwd"], worktrees) or place(session["git_root"], worktrees)
        if worktree is None:
            continue
        session["worktree"] = worktree["path"]
        session["branch"] = worktree["branch"]
        session["self"] = session["session_id"] == self_id
        session["chain_targets"] = sorted(
            {str(row.get("target")) for row in ledger_rows if row.get("session_id") == session["session_id"]}
        )
        in_repo.append(session)
    in_repo.sort(key=lambda s: (str(s["worktree"]), str(s["created_at"]), str(s["session_id"])))

    previous = previous_scan(log_path)
    before = {s["session_id"]: s for s in (previous or {}).get("sessions", []) if isinstance(s, dict)}
    seen = {s["session_id"] for s in in_repo}
    for session in in_repo:
        session["status"] = "continuing" if session["session_id"] in before else "new"
    ended = [before[i] for i in sorted(before) if i not in seen]

    report: Dict[str, object] = {
        "scanned_at": now_utc(),
        "repository": root,
        "invoked_by": self_id,
        "log": log_path,
        "previous_scan_at": (previous or {}).get("scanned_at"),
        "sessions": in_repo,
        "ended": ended,
        "worktrees": [
            {
                "path": w["path"],
                "branch": w["branch"],
                "sessions": [s["session_id"] for s in in_repo if s["worktree"] == w["path"]],
            }
            for w in worktrees
        ],
    }
    if record:
        append_record(
            log_path,
            {
                "scanned_at": report["scanned_at"],
                "invoked_by": self_id,
                "sessions": [
                    {k: s[k] for k in ("session_id", "pid", "name", "worktree", "branch", "created_at")}
                    for s in in_repo
                ],
                "new": sorted(s["session_id"] for s in in_repo if s["status"] == "new"),
                "ended": [s["session_id"] for s in ended],
            },
        )
    return report, log_path


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan", help="report live sessions in this repository and log the scan")
    scan_parser.add_argument("--repo", default=os.getcwd(), help="any path inside the repository (default: cwd)")
    scan_parser.add_argument(
        "--state-dir",
        default=os.path.join(os.environ.get("COPILOT_HOME") or os.path.expanduser("~/.copilot"), "session-state"),
        help="Copilot CLI session-state directory (default: $COPILOT_HOME/session-state)",
    )
    scan_parser.add_argument("--log", help="session log path (default: <repo root>/.git-loopy/next/sessions.jsonl)")
    scan_parser.add_argument("--no-record", action="store_true", help="report without appending to the log")
    args = parser.parse_args(argv)

    try:
        report, _ = scan(args.repo, args.state_dir, args.log, not args.no_record)
    except subprocess.CalledProcessError as error:
        print(f"error: {' '.join(error.cmd)} failed: {(error.stderr or '').strip()}", file=sys.stderr)
        return 1
    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
