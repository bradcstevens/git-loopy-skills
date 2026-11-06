#!/usr/bin/env python3
"""Report all holders of a canonical chain target without changing state."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


sys.dont_write_bytecode = True
from chain_ledger import owner_is_gone


SCRIPTS = Path(__file__).resolve().parent


def command_json(command):
    result = subprocess.run(
        command, capture_output=True, text=True, timeout=10, check=True,
    )
    return json.loads(result.stdout)


def registered_worktrees():
    output = subprocess.check_output(
        ["git", "worktree", "list", "--porcelain", "-z"], text=True,
    )
    worktrees = []
    for field in output.split("\0"):
        if field.startswith("worktree "):
            worktrees.append({"worktree": field[9:], "branch": None})
        elif field.startswith("branch refs/heads/"):
            worktrees[-1]["branch"] = field[len("branch refs/heads/"):]
    return worktrees


def live_owner(worktree):
    marker = Path(worktree) / ".git-loopy/worktree-owner"
    try:
        pid_text, start = marker.read_text(encoding="utf-8").rstrip("\n").split("\t", 1)
        pid = int(pid_text)
    except (FileNotFoundError, ValueError):
        return None
    if pid <= 0 or not start.strip() or owner_is_gone(pid, start):
        return None
    return {"owner_pid": pid, "owner_start": start}


def primary_worktree(worktrees):
    root = worktrees[0]["worktree"]
    common = os.path.realpath(subprocess.check_output(
        ["git", "rev-parse", "--git-common-dir"], text=True,
    ).strip())
    if os.path.realpath(root) != common:
        return root
    # The chain may already have recorded a separate-git-dir anchor; this reader
    # can use it but must never create one.
    anchor = os.path.join(common, "git-loopy-worktree-root")
    if os.path.islink(anchor):
        root = os.path.realpath(anchor)
        recorded_common = subprocess.check_output(
            ["git", "-C", root, "rev-parse", "--git-common-dir"], text=True,
        ).strip()
        if os.path.realpath(os.path.join(root, recorded_common)) != common:
            raise ValueError("recorded repository root belongs to another repository")
        return root
    git_dir = os.path.realpath(subprocess.check_output(
        ["git", "rev-parse", "--git-dir"], text=True,
    ).strip())
    if git_dir != common:
        raise ValueError("separate-git-dir root is not recorded; supply --ledger")
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True)
    parser.add_argument("--ledger", default=os.environ.get("CHAIN_LEDGER"))
    parser.add_argument("--caller-worktree")
    parser.add_argument("--caller-branch")
    args = parser.parse_args()
    worktrees = registered_worktrees()
    if not args.ledger:
        worktrees[0]["worktree"] = primary_worktree(worktrees)
    root = worktrees[0]["worktree"]
    caller_worktree = os.path.realpath(args.caller_worktree or subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True,
    ).strip())
    branches = {os.path.realpath(w["worktree"]): w["branch"] for w in worktrees}
    caller_branch = args.caller_branch or branches.get(caller_worktree)
    ledger = args.ledger or os.path.join(root, ".git-loopy", "subagents.jsonl")
    identity = command_json([sys.executable, str(SCRIPTS / "target-identity.py"),
                             ledger, args.target])
    if identity.get("error"):
        raise ValueError(identity.get("detail") or identity["error"])
    holders = []
    if os.path.exists(ledger):
        with open(ledger, encoding="utf-8") as source:
            rows = [json.loads(line) for line in source if line.strip()]
        for row in rows:
            if (not row.get("finish_time") and row.get("agent_id")
                    and row.get("target") in identity["equivalent_targets"]):
                holders.append({
                    "kind": "bound-run", "session_id": row.get("session_id"),
                    "agent_id": row["agent_id"], "worktree": row.get("worktree"),
                    **({"branch": row["worktree_branch"]} if row.get("worktree_branch") else {}),
                    "own": False,
                })
    if identity["canonical_target"].startswith("issue-"):
        issue = command_json(["gh", "issue", "view", identity["tracker_target"], "--json",
                              "closedByPullRequestsReferences"])
        for reference in issue["closedByPullRequestsReferences"]:
            pr = command_json(["gh", "pr", "view", str(reference["number"]), "--json",
                               "number,url,state,headRefName"])
            if pr["state"] == "OPEN":
                holders.append({
                    "kind": "pull-request", "number": pr["number"], "url": pr["url"],
                    "branch": pr["headRefName"], "own": False,
                })
                for worktree in worktrees:
                    if worktree["branch"] != pr["headRefName"]:
                        continue
                    owner = live_owner(worktree["worktree"])
                    if owner:
                        holders.append({
                            "kind": "worktree-owner", "number": pr["number"],
                            **worktree, **owner, "own": False,
                        })
    for holder in holders:
        worktree = holder.get("worktree")
        path = os.path.realpath(worktree) if worktree else None
        branch = holder.get("branch") or branches.get(path)
        holder["own"] = (
            path == caller_worktree
            or bool(caller_branch and branch == caller_branch)
        )
    print(json.dumps({
        "canonical_target": identity["canonical_target"],
        "held": any(not holder["own"] for holder in holders), "holders": holders,
    }, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, StopIteration,
            subprocess.SubprocessError) as error:
        print(json.dumps({"error": "holder-lookup-failed", "detail": str(error)}))
        raise SystemExit(2)
