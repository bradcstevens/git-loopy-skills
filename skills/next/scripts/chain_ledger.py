"""Repository lookup, ledger storage and interoperable ledger locks."""

import datetime
import glob
import json
import os
import subprocess
import tempfile
import time
import uuid
from typing import Optional


LEDGER_RELATIVE_PATH = os.path.join(".git-loopy", "subagents.jsonl")


def repository_root(cwd: str) -> str:
    def git(*args: str, directory: str = cwd) -> str:
        return subprocess.check_output(
            ["git", "-C", directory, *args], text=True, stderr=subprocess.PIPE,
        ).strip()

    def resolved(directory: str, path: str) -> str:
        return os.path.realpath(os.path.join(directory, path))

    worktrees = git("worktree", "list", "--porcelain")
    main = next(
        (line[len("worktree "):] for line in worktrees.splitlines()
         if line.startswith("worktree ")), None,
    )
    if not main:
        raise ValueError("could not resolve repository root")
    common = resolved(cwd, git("rev-parse", "--git-common-dir"))
    if os.path.realpath(main) != common:
        return main

    git_dir = resolved(cwd, git("rev-parse", "--git-dir"))
    current = resolved(cwd, git("rev-parse", "--show-toplevel"))
    anchor = os.path.join(common, "git-loopy-worktree-root")
    if not os.path.lexists(anchor):
        if git_dir != common:
            raise ValueError("repository root is not recorded for this separate-git-dir repository")
        try:
            os.symlink(current, anchor)
        except FileExistsError:
            if not os.path.islink(anchor):
                raise ValueError("could not record repository root: " + anchor)
    if not os.path.islink(anchor):
        raise ValueError("could not read repository root: " + anchor)
    recorded = os.readlink(anchor)
    recorded_common = resolved(recorded, git("rev-parse", "--git-common-dir", directory=recorded))
    if recorded_common != common:
        raise ValueError("recorded repository root belongs to a different repository: " + recorded)
    return recorded


def parse_process_start(value: str) -> Optional[datetime.datetime]:
    normalized = " ".join(value.split())
    try:
        parsed = datetime.datetime.strptime(normalized, "%a %b %d %H:%M:%S %Y")
    except ValueError:
        return None
    if normalized.split()[0] != parsed.strftime("%a"):
        return None
    return parsed


def process_start(pid: int) -> str:
    return " ".join(subprocess.check_output(
        ["ps", "-o", "lstart=", "-p", str(pid)],
        text=True, env={**os.environ, "TZ": "UTC"},
    ).split())


def owner_is_gone(pid: int, owner_start: str) -> bool:
    try:
        if pid <= 0:
            raise ProcessLookupError
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    try:
        current_start = process_start(pid)
    except subprocess.CalledProcessError:
        return False
    recorded = parse_process_start(owner_start)
    current = parse_process_start(current_start)
    if recorded is None or current is None:
        return False
    return current != recorded


def claim_is_stale(claim_dir: str, stale_after_seconds: int) -> bool:
    try:
        with open(os.path.join(claim_dir, "pid"), encoding="utf-8") as owner:
            pid_text, owner_start = owner.read().rstrip("\n").split("\t", 1)
            pid = int(pid_text)
    except (FileNotFoundError, ValueError):
        try:
            return (
                stale_after_seconds >= 0
                and time.time() - os.stat(claim_dir).st_mtime >= stale_after_seconds
            )
        except FileNotFoundError:
            return False
    return owner_is_gone(pid, owner_start)


def lock_is_stale(lock_dir: str) -> bool:
    try:
        stale_after = int(os.environ.get("CHAIN_LOCK_STALE_SECONDS", "300"))
    except ValueError:
        stale_after = -1
    return claim_is_stale(lock_dir, stale_after)


def release_lock(lock_dir: str) -> None:
    try:
        os.unlink(os.path.join(lock_dir, "pid"))
    except FileNotFoundError:
        pass
    try:
        os.rmdir(lock_dir)
    except FileNotFoundError:
        pass


def write_owner(lock_dir: str) -> None:
    start = process_start(os.getpid())
    with open(os.path.join(lock_dir, "pid"), "w", encoding="utf-8") as owner:
        owner.write(f"{os.getpid()}\t{start}\n")


def reclaim(lock_dir: str) -> None:
    claimed = f"{lock_dir}.reclaim.{os.getpid()}.{uuid.uuid4().hex}"
    try:
        os.rename(lock_dir, claimed)
    except FileNotFoundError:
        return
    release_lock(claimed)


def recover_stale_lock(lock_dir: str) -> None:
    recovery = lock_dir + ".recovery"
    try:
        os.mkdir(recovery)
    except FileExistsError:
        return
    try:
        write_owner(recovery)
        if lock_is_stale(lock_dir):
            reclaim(lock_dir)
    finally:
        release_lock(recovery)


def acquire_lock(lock_dir: str, timeout: Optional[float] = 1) -> bool:
    """Use the bash recovery guard; None waits indefinitely for later ports."""
    deadline = None if timeout is None else time.monotonic() + timeout
    while True:
        if os.path.isdir(lock_dir + ".recovery"):
            if lock_is_stale(lock_dir + ".recovery"):
                reclaim(lock_dir + ".recovery")
        else:
            try:
                os.mkdir(lock_dir)
            except FileExistsError:
                recover_stale_lock(lock_dir)
            else:
                try:
                    write_owner(lock_dir)
                except (OSError, subprocess.CalledProcessError):
                    release_lock(lock_dir)
                    raise
                return True
        if deadline is not None and time.monotonic() >= deadline:
            return False
        time.sleep(0.01)


def cleanup_replacements(ledger_path: str) -> None:
    for replacement in glob.glob(os.path.join(os.path.dirname(ledger_path), ".subagents.*")):
        try:
            os.unlink(replacement)
        except FileNotFoundError:
            pass


def read_ledger(ledger_path: str) -> Optional[list]:
    try:
        with open(ledger_path, encoding="utf-8") as ledger:
            return [json.loads(line) for line in ledger if line.strip()]
    except (OSError, json.JSONDecodeError):
        return None


def write_ledger(ledger_path: str, rows: list) -> bool:
    replacement = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=os.path.dirname(ledger_path),
            prefix=".subagents.", delete=False,
        ) as temporary:
            replacement = temporary.name
            for row in rows:
                temporary.write(json.dumps(row, separators=(",", ":")) + "\n")
        os.replace(replacement, ledger_path)
        return True
    except OSError:
        if replacement is not None:
            try:
                os.unlink(replacement)
            except FileNotFoundError:
                pass
        return False


def is_open(row: dict) -> bool:
    return not row.get("finish_time")


def matches_worktree(row: dict, worktree: str) -> bool:
    return (
        isinstance(row.get("worktree"), str)
        and bool(row["worktree"])
        and os.path.realpath(row["worktree"]) == os.path.realpath(worktree)
    )


def matches_run(row: dict, payload: dict) -> bool:
    if not is_open(row) or row.get("session_id") != payload["sessionId"]:
        return False
    if "agentId" in payload:
        return (
            row.get("agent_id") == payload["agentId"]
            and row.get("agent_type") == payload["agentType"]
        )
    return matches_worktree(row, payload["cwd"]) and row.get("agent_type") == payload["agentName"]
