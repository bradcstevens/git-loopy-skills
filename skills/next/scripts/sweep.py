#!/usr/bin/env python3
"""Report worktree ownership without changing the repository."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from sessions import repository_root


LSOF_ESCAPES = {0x08: b"\\b", 0x09: b"\\t", 0x0a: b"\\n", 0x0c: b"\\f", 0x0d: b"\\r",
                0x5c: b"\\\\"}


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


def lsof_spelling(path):
    """Spell a path the way lsof prints names under LC_ALL=C."""
    spelled = bytearray()
    for byte in os.fsencode(path):
        if byte in LSOF_ESCAPES:
            spelled += LSOF_ESCAPES[byte]
        elif 0x20 <= byte < 0x7f:
            spelled.append(byte)
        elif byte < 0x20:
            spelled += b"^" + bytes([byte + 0x40])
        elif byte == 0xff:
            spelled += b"^?"
        else:
            spelled += b"\\x%02x" % byte
    return bytes(spelled)


def holders(rows):
    with subprocess.Popen(
        ["lsof", "-nP", "-F0pRn"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={**os.environ, "LC_ALL": "C"},
    ) as process:
        try:
            stdout, stderr = process.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
    # lsof always lists itself, so an empty listing is a failed inspection too.
    if process.returncode or stderr or not stdout:
        detail = os.fsdecode(stderr).strip() or (
            f"exit status {process.returncode} with {'partial' if stdout else 'no'} output")
        raise RuntimeError(f"lsof inspection failed: {detail}")
    # A literal caret and a control byte can share one spelling; such a name holds both.
    spellings = {}
    for row in rows:
        spellings.setdefault(lsof_spelling(row["path"]), []).append(row["path"])
    found = {row["path"]: set() for row in rows}
    pid = None
    own = False
    for field in stdout.split(b"\0"):
        field = field.lstrip(b"\n")
        if field.startswith(b"p"):
            pid = int(field[1:])
            own = pid in (os.getpid(), process.pid)
        elif field.startswith(b"R"):
            # Linux lsof forks helpers that inherit its working directory.
            own = own or int(field[1:]) == process.pid
        elif field.startswith(b"n/") and pid is not None and not own:
            name = field[1:]
            matches = [spelling for spelling in spellings
                       if name == spelling or name.startswith(spelling + b"/")]
            if matches:
                for path in spellings[max(matches, key=len)]:
                    found[path].add(pid)
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


def inspect_worktree(row, pids, ledger_rows):
    path = row["path"]
    row.update(ledger_rows=ledger_rows, holder_pids=sorted(pids), errors=[],
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
        rows_by_worktree = ledger_counts(ledger)
        pids_by_worktree = holders(rows) if rows else {}
        for row in rows:
            inspect_worktree(row, pids_by_worktree[row["path"]],
                             rows_by_worktree.get(row["path"], 0))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"error: {error_message(error)}", file=sys.stderr)
        return 1
    counts = {name: sum(row["classification"] == name for row in rows)
              for name in ("held", "marked", "unvouched")}
    print(json.dumps({"worktrees": rows, "counts": counts, "ledger": ledger}))
    return int(any(row["errors"] for row in rows))


if __name__ == "__main__":
    sys.exit(main())
