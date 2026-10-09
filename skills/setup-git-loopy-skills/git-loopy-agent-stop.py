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
            if lock_is_stale(lock_dir):
                reclaimed = f"{lock_dir}.reclaim.{os.getpid()}"
                try:
                    os.replace(lock_dir, reclaimed)
                    os.unlink(os.path.join(reclaimed, "pid"))
                    os.rmdir(reclaimed)
                except OSError:
                    pass
                continue
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


def lock_is_stale(lock_dir: str) -> bool:
    try:
        with open(os.path.join(lock_dir, "pid"), encoding="utf-8") as owner:
            pid_text, owner_start = owner.read().rstrip("\n").split("\t", 1)
            pid = int(pid_text)
    except (FileNotFoundError, ValueError):
        try:
            stale_after = int(os.environ.get("CHAIN_LOCK_STALE_SECONDS", "300"))
        except ValueError:
            return False
        try:
            return stale_after >= 0 and time.time() - os.stat(lock_dir).st_mtime >= stale_after
        except FileNotFoundError:
            return False

    try:
        if pid <= 0:
            raise ProcessLookupError
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False

    current_start = subprocess.run(
        ["ps", "-o", "lstart=", "-p", str(pid)],
        capture_output=True,
        text=True,
    ).stdout.split()
    return " ".join(current_start) != owner_start


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

unrouted = [
    row
    for row in rows
    if (
        isinstance(row, dict)
        and row.get("finish_time")
        and row.get("outcome") != "reclaimed"
        and not row.get("routed")
    )
]
if not unrouted:
    decision("no-unrouted-completion")
    raise SystemExit(0)

routable = [
    row for row in unrouted if isinstance(row.get("target"), str) and row["target"]
]
if not routable:
    decision("invalid-completed-row")
    raise SystemExit(0)
targets = [row["target"] for row in routable]

# Fan-out finishes in batches, and one `/next` fill refills every slot the batch
# freed, so the whole batch is routed by a single block. Blocking once per
# completion would spend the runtime's eight consecutive blocks on turns with
# nothing left to fill, and stop_hook_active stands this hook aside on the turn
# a block forces, so the rest of the batch would be stranded unrouted. A row the
# chain script could not have written is left out rather than withholding the
# batch: it is never marked routed, so refusing the readable rows over it would
# stall every later natural stop as well.
for row in routable:
    row["routed"] = True
    row["routed_at"] = payload.get("timestamp")
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

if len(targets) == 1:
    reason = "A completed run is unrouted. Run /next now."
else:
    reason = (
        f"{len(targets)} completed runs are unrouted. "
        "Run /next now and refill every freed slot."
    )

print(
    json.dumps(
        {
            "decision": "block",
            "reason": reason,
            "targets": targets,
        },
        separators=(",", ":"),
    )
)
