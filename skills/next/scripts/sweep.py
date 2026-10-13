#!/usr/bin/env python3
"""Report worktree ownership without changing the repository."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from sessions import repository_root


def git(repo, *args):
    return subprocess.run(
        ["git", "--no-optional-locks", "-C", repo, *args],
        check=True, capture_output=True,
    ).stdout


def worktrees(repo):
    rows = []
    for record in git(repo, "worktree", "list", "--porcelain", "-z").split(b"\0\0"):
        fields = dict(field.partition(b" ")[::2] for field in record.split(b"\0") if field)
        if b"worktree" in fields:
            rows.append({
                "path": os.path.realpath(os.fsdecode(fields[b"worktree"])),
                "branch": os.fsdecode(fields.get(b"branch", b"")) or None,
                "bare": b"bare" in fields,
                "classification": "unvouched",
            })
    return rows


def marker_owner(path):
    marker = os.path.join(path, ".git-loopy", "worktree-owner")
    if not os.path.lexists(marker):
        return None
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("chain.sh")), "owner", "--worktree", path],
        check=True, capture_output=True, text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    return json.loads(result.stdout)


def holders(rows):
    with subprocess.Popen(
        ["lsof", "-nP", "-F0pn"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ) as process:
        try:
            stdout, stderr = process.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
    if process.returncode not in (0, 1) or stderr:
        raise RuntimeError(f"lsof inspection failed: {os.fsdecode(stderr).strip()}")
    if process.returncode == 1 and stdout:
        raise RuntimeError("lsof inspection returned partial results")
    found = {row["path"]: set() for row in rows}
    pid = None
    for field in stdout.split(b"\0"):
        field = field.lstrip(b"\n")
        if field.startswith(b"p"):
            pid = int(field[1:])
        elif field.startswith(b"n/") and pid is not None and pid not in (os.getpid(), process.pid):
            # lsof escapes non-printing bytes even with NUL field separators.
            escapes = {b"a": b"\a", b"b": b"\b", b"f": b"\f", b"n": b"\n",
                       b"r": b"\r", b"t": b"\t", b"v": b"\v", b"\\": b"\\"}
            name = re.sub(
                rb"\\(x[0-9a-fA-F]{2}|[abfnrtv\\])",
                lambda match: (bytes([int(match[1][1:], 16)]) if match[1].startswith(b"x")
                               else escapes[match[1]]),
                field[1:],
            )
            path = os.path.realpath(os.fsdecode(name))
            matches = [root for root in found if path == root or path.startswith(root + os.sep)]
            if matches:
                found[max(matches, key=len)].add(pid)
    return found


def resolve_root(repo, rows):
    common = os.path.realpath(os.path.join(
        repo, os.fsdecode(git(repo, "rev-parse", "--git-common-dir")).removesuffix("\n"),
    ))
    if rows and rows[0]["bare"]:
        root = common
    else:
        git_dir = os.path.realpath(os.path.join(
            repo, os.fsdecode(git(repo, "rev-parse", "--git-dir")).removesuffix("\n"),
        ))
        if (rows and rows[0]["path"] == common and git_dir != common
                and not os.path.islink(os.path.join(common, "git-loopy-worktree-root"))):
            raise RuntimeError("separate-git-dir repository root is unrecorded; run from its main checkout")
        root = repository_root(repo, rows)
        if rows and rows[0]["path"] == common:
            root_common = os.path.realpath(os.path.join(
                root, os.fsdecode(git(root, "rev-parse", "--git-common-dir")).removesuffix("\n"),
            ))
            if root_common != common:
                raise RuntimeError("recorded repository root belongs to another repository")
            rows[0]["path"] = root
    return root


def ledger_counts(path):
    counts = {}
    try:
        ledger = open(path, encoding="utf-8")
    except FileNotFoundError:
        return counts
    with ledger:
        for number, line in enumerate(ledger, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict) or not isinstance(row.get("worktree"), str) or not row["worktree"]:
                raise ValueError(f"{path}:{number}: ledger row requires a worktree path")
            worktree = os.path.realpath(row["worktree"])
            counts[worktree] = counts.get(worktree, 0) + 1
    return counts


def error_message(error):
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        detail = error.stderr
        return os.fsdecode(detail).strip()
    return str(error)


def inspect_worktree(row, pids, recorded):
    path = row["path"]
    row.update(ledger_rows=recorded, holder_pids=sorted(pids), errors=[],
               exists=os.path.isdir(path), dirty=None, owner_alive=None)
    marked = os.path.lexists(os.path.join(path, ".git-loopy", "worktree-owner"))
    row["classification"] = "held" if pids else "marked" if marked else "unvouched"
    if marked:
        try:
            owner = marker_owner(path)
            if owner is None:
                row["errors"].append("marker disappeared during sweep")
            elif owner.get("reason"):
                row["errors"].append(owner["reason"])
            else:
                row["owner_alive"] = owner["alive"]
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))
    if row["exists"]:
        try:
            top = os.path.realpath(os.fsdecode(
                git(path, "rev-parse", "--show-toplevel"),
            ).removesuffix("\n"))
            if top != path:
                raise RuntimeError("directory no longer resolves to the registered worktree")
            row["dirty"] = bool(git(
                path, "status", "--porcelain=v1", "-z", "--untracked-files=all",
                "--ignore-submodules=none", "--", ".", ":(exclude).git-loopy/worktree-owner",
            ))
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.getcwd(), help="path inside the repository")
    parser.add_argument("--ledger", default=os.environ.get("CHAIN_LEDGER"),
                        help="spawn ledger (default: repository .git-loopy/subagents.jsonl)")
    args = parser.parse_args()
    try:
        rows = worktrees(args.repo)
        root = resolve_root(args.repo, rows)
        ledger = os.path.abspath(args.ledger or os.path.join(root, ".git-loopy", "subagents.jsonl"))
        rows = [row for row in rows if not row.pop("bare")]
        recorded = ledger_counts(ledger)
        held = holders(rows) if rows else {}
        for row in rows:
            inspect_worktree(row, held[row["path"]], recorded.get(row["path"], 0))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"error: {error_message(error)}", file=sys.stderr)
        return 1
    counts = {name: sum(row["classification"] == name for row in rows)
              for name in ("held", "marked", "unvouched")}
    print(json.dumps({"worktrees": rows, "counts": counts, "ledger": ledger}))
    return int(any(row["errors"] for row in rows))


if __name__ == "__main__":
    sys.exit(main())
