#!/usr/bin/env python3
import atexit
import json
import os
import subprocess
import sys
import tempfile
import time


def decision(reason: str, **details: object) -> None:
    print(json.dumps({"decision": "allow", "reason": reason, **details}, separators=(",", ":")))


def repository_root(cwd: object) -> str | None:
    if not isinstance(cwd, str) or not cwd:
        return None

    result = subprocess.run(
        ["git", "-C", cwd, "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        return None
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            return line.removeprefix("worktree ")
    return None


def acquire_lock(lock_dir: str) -> bool:
    deadline = time.monotonic() + 1
    while True:
        try:
            os.mkdir(lock_dir)
        except FileExistsError:
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.05)
            continue

        start = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(os.getpid())],
            capture_output=True,
            text=True,
        ).stdout.split()
        with open(os.path.join(lock_dir, "pid"), "w", encoding="utf-8") as owner:
            owner.write(f"{os.getpid()}\t{' '.join(start)}\n")
        return True


def release_lock(lock_dir: str) -> None:
    try:
        os.unlink(os.path.join(lock_dir, "pid"))
        os.rmdir(lock_dir)
    except FileNotFoundError:
        pass


try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

if not isinstance(payload, dict):
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

if payload.get("stop_hook_active") is True:
    decision("stop-hook-active")
    raise SystemExit(0)

root = repository_root(payload.get("cwd"))
if root is None:
    decision("repository-not-found")
    raise SystemExit(0)

ledger_path = os.path.join(root, ".git-loopy", "subagents.jsonl")
if not os.path.exists(ledger_path):
    decision("no-ledger")
    raise SystemExit(0)

lock_dir = ledger_path + ".lock"
if not acquire_lock(lock_dir):
    decision("ledger-busy")
    raise SystemExit(0)
atexit.register(release_lock, lock_dir)

try:
    with open(ledger_path, encoding="utf-8") as ledger:
        rows = [json.loads(line) for line in ledger if line.strip()]
except (OSError, json.JSONDecodeError):
    decision("invalid-ledger")
    raise SystemExit(0)

unrouted = next(
    (
        row
        for row in rows
        if isinstance(row, dict) and row.get("finish_time") and not row.get("routed")
    ),
    None,
)
if unrouted is None:
    decision("no-unrouted-completion")
    raise SystemExit(0)

target = unrouted.get("target")
if not isinstance(target, str) or not target:
    decision("invalid-completed-row")
    raise SystemExit(0)

unrouted["routed"] = True
unrouted["routed_at"] = payload.get("timestamp")
ledger_dir = os.path.dirname(ledger_path)
try:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=ledger_dir,
        prefix=".subagents.",
        delete=False,
    ) as temporary:
        for row in rows:
            temporary.write(json.dumps(row, separators=(",", ":")) + "\n")
        temporary_path = temporary.name
    os.replace(temporary_path, ledger_path)
except OSError:
    if "temporary_path" in locals():
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
    decision("ledger-update-failed")
    raise SystemExit(0)

print(
    json.dumps(
        {
            "decision": "block",
            "reason": "A completed run is unrouted. Run /next now.",
            "target": target,
        },
        separators=(",", ":"),
    )
)
