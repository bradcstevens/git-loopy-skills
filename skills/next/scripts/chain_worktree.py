"""Worktree cleanup shared by completion and pending transaction rollback."""

import errno
import json
import os
import subprocess
import sys
from typing import Optional, Tuple

from chain_ledger import repository_root


def remove_worktree(worktree: str, force: bool = False) -> bool:
    root = repository_root(os.getcwd())
    if not os.path.exists(worktree):
        return subprocess.run(["git", "-C", root, "worktree", "prune"]).returncode == 0

    marker = os.path.join(worktree, ".git-loopy", "worktree-owner")
    backup = None
    if os.path.isfile(marker):
        with open(marker, "rb") as stream:
            backup = stream.read()
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    try:
        os.rmdir(os.path.dirname(marker))
    except OSError as error:
        if error.errno not in (errno.ENOENT, errno.ENOTEMPTY, errno.EEXIST):
            raise
    try:
        command = ["git", "-C", root, "worktree", "remove"]
        if force:
            command.append("--force")
        removed = subprocess.run([*command, worktree]).returncode == 0
    except OSError:
        if backup is not None and os.path.isdir(worktree):
            restore_marker(marker, backup)
        raise
    if not removed and backup is not None and os.path.isdir(worktree):
        restore_marker(marker, backup)
    return removed


def restore_marker(marker: str, contents: bytes) -> None:
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    with open(marker, "wb") as stream:
        stream.write(contents)


def remove_clean_worktree(worktree: str) -> bool:
    if os.path.exists(worktree):
        status = subprocess.run(
            ["git", "-C", worktree, "status", "--porcelain=v1", "--untracked-files=all",
             "--", ".", ":(exclude).git-loopy/worktree-owner"],
            stdout=subprocess.PIPE, text=True,
        )
        if status.returncode:
            print(f"error: could not inspect worktree; retaining it: {worktree}", file=sys.stderr)
            return False
        if status.stdout.strip():
            print(f"warning: worktree has uncommitted changes and was retained: {worktree}",
                  file=sys.stderr)
            return False
    if not remove_worktree(worktree):
        print(f"warning: could not remove clean worktree; retaining it: {worktree}", file=sys.stderr)
        return False
    return True


def unfinished_worktree(pending_path: str, ledger_path: str) -> Optional[Tuple[str, str]]:
    with open(pending_path, encoding="utf-8") as pending:
        record = json.load(pending)
    if not isinstance(record, dict):
        raise ValueError("pending record is not an object")
    worktree = record.get("worktree")
    branch = record.get("branch", "")
    if not isinstance(worktree, str) or not worktree or not isinstance(branch, str):
        raise ValueError("pending record has invalid worktree or branch")
    if record.get("commit") == "marker":
        if os.path.exists(os.path.join(worktree, ".git-loopy", "worktree-owner")):
            return None
    elif record.get("commit") == "row":
        reservation_id = record.get("reservation_id")
        if not isinstance(reservation_id, str) or not reservation_id:
            raise ValueError("pending record has no reservation_id")
        if os.path.exists(ledger_path):
            with open(ledger_path, encoding="utf-8") as ledger:
                for line in ledger:
                    if not line.strip():
                        continue
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise ValueError("ledger row is not an object")
                    recorded = row.get("reservation_id")
                    if "reservation_id" in row and (
                        not isinstance(recorded, str) or not recorded
                    ):
                        raise ValueError("ledger row has invalid reservation_id")
                    if recorded == reservation_id:
                        return None
    else:
        raise ValueError("pending record has invalid commit")
    return worktree, branch


def worktree_registered_on_branch(root: str, path: str, branch: str) -> bool:
    if not branch:
        return False
    listing = subprocess.run(
        ["git", "-C", root, "worktree", "list", "--porcelain"],
        capture_output=True, text=True, check=True,
    )
    path = os.path.realpath(os.path.abspath(path))
    for block in listing.stdout.strip().split("\n\n"):
        record = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            record[key] = value
        if "worktree" not in record or os.path.realpath(record["worktree"]) != path:
            continue
        if any(key in record for key in ("prunable", "detached", "bare")):
            return False
        return record.get("branch") == "refs/heads/" + branch
    return False


def rollback_pending_worktree(pending_path: str, ledger_path: str) -> None:
    if not os.path.isfile(pending_path):
        return
    try:
        record = unfinished_worktree(pending_path, ledger_path)
    except (OSError, ValueError) as error:
        raise OSError(f"unreadable pending worktree record: {pending_path}") from error
    if record is not None:
        worktree, branch = record
        root = repository_root(os.getcwd())
        existed = os.path.lexists(worktree)
        if existed:
            try:
                ours = worktree_registered_on_branch(root, worktree, branch)
            except subprocess.CalledProcessError as error:
                sys.stderr.write(error.stderr)
                raise OSError(
                    f"could not ask git who owns {worktree}; keeping {pending_path}"
                ) from error
            if not ours:
                raise OSError(
                    f"{worktree} is not on branch {branch or '<none>'}, so this transaction "
                    f"did not create it; inspect it, then remove it and {pending_path} by hand "
                    "if it is abandoned"
                )
        # Only an unfinished, proven-owned transaction permits forced rollback.
        # Reclaiming ledger rows always goes through remove_clean_worktree instead.
        if not remove_worktree(worktree, force=True):
            raise OSError(f"could not remove unrecorded worktree: {worktree}")
        if existed and branch and subprocess.run(
            ["git", "-C", root, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch],
            stdout=subprocess.DEVNULL,
        ).returncode == 0:
            if subprocess.run(
                ["git", "-C", root, "branch", "-D", branch],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode:
                print(f"error: could not delete branch of removed worktree: {branch}",
                      file=sys.stderr)
    os.unlink(pending_path)


if __name__ == "__main__":
    try:
        rollback_pending_worktree(*sys.argv[1:])
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
