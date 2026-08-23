#!/usr/bin/env python3
"""agentStop decision helper: re-enter `/next` when a completed run is unrouted.

Blocking is a route *request*, not a route. The block reason does not reach the
parent as a guarantee — the CLI presents it as a dismissible queued prompt, so
the operator can remove it, the session can exit before the forced turn runs, or
the runtime can hit its ceiling of consecutive blocks. Writing `routed` at the
moment of the block would record that intent as a fact, and every dismissal
would drop a chain hop while reporting nothing wrong.

So the request is promoted to `routed` only on evidence the block landed:
`stop_hook_active` true on a following payload, which is the runtime's way of
saying the parent took the turn the block forced. The request records the
session it was asked in, so that evidence confirms the hop it was actually
forced for, and a payload with no `sessionId` cannot make a request at all. A
request that is never confirmed blocks again rather than being silently
consumed.
"""
import atexit
import json
import os
import subprocess
import sys
import tempfile
import time

# Re-blocking an unconfirmed request has to stop somewhere. The runtime permits
# 8 consecutive blocks and then exits without saying why, so the chain's own cap
# trips first and names what it abandoned — see ADR-0004.
MAX_ROUTE_ATTEMPTS = 3

LEDGER_RELATIVE_PATH = os.path.join(".git-loopy", "subagents.jsonl")
BLOCK_REASON = "A completed run is unrouted. Run /next now."


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


def read_ledger(ledger_path: str) -> list | None:
    try:
        with open(ledger_path, encoding="utf-8") as ledger:
            return [json.loads(line) for line in ledger if line.strip()]
    except (OSError, json.JSONDecodeError):
        return None


def write_ledger(ledger_path: str, rows: list) -> bool:
    """Replace the ledger in one atomic step.

    A half-written ledger is worse than no write at all: the next hook reads it
    to decide, so a truncated file looks like a ledger with no completed run.
    The replacement is built beside the ledger and renamed over it, so an
    interrupted helper leaves the previous ledger whole.
    """
    replacement = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=os.path.dirname(ledger_path),
            prefix=".subagents.",
            delete=False,
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
            except OSError:
                pass
        return False


def owed_a_route(row: object) -> bool:
    """A finished run the chain still owes a route.

    Neither a routed row nor an abandoned one is owed anything: the first was
    confirmed, and the second gave up under a reason that named it.
    """
    return (
        isinstance(row, dict)
        and bool(row.get("finish_time"))
        and not row.get("routed")
        and not row.get("route_abandoned")
    )


def route_attempts(row: dict) -> int:
    """How many times a route has been asked for on this row.

    The count is the request itself, because the helper writes it whatever the
    payload carried. The request *time* is only provenance: it comes from
    `timestamp`, which ADR-0005 keeps optional because nothing read it, so a
    request resting on it would be unconfirmable whenever it is absent.
    """
    attempts = row.get("route_attempts")
    return attempts if isinstance(attempts, int) and attempts > 0 else 0


def route_requesters(row: dict) -> list:
    """The sessions still owed a forced turn for this row.

    A block holds open the session it was emitted in, so that is the session
    whose next turn is evidence the block landed. Recording who asked is what
    lets a confirmation find the request it belongs to rather than whichever
    request happens to come first.
    """
    requesters = row.get("route_requested_by")
    if not isinstance(requesters, list):
        return []
    return [name for name in requesters if isinstance(name, str) and name]


def awaiting_confirmation(row: object) -> bool:
    return owed_a_route(row) and route_attempts(row) > 0


def confirmable_by(rows: list, session: object) -> dict | None:
    """The pending request this forced turn is evidence for.

    A turn forced in one session says nothing about a request another session
    made, so only a request this session asked for is confirmed here. The rest
    are left standing for their own sessions to confirm or ask again.
    """
    if not isinstance(session, str) or not session:
        return None
    return next(
        (
            row
            for row in rows
            if awaiting_confirmation(row) and session in route_requesters(row)
        ),
        None,
    )


def confirm_route_request(payload: dict, ledger_path: str | None) -> None:
    """Promote a pending route request to a routed fact, then stand aside.

    Nothing on this path can block. `stop_hook_active` never starts a fresh
    route, so an unreadable or locked ledger only means there is nothing to
    confirm — never a reason to hold the parent open again.
    """
    if ledger_path is None:
        decision("stop-hook-active")
        return

    lock_dir = ledger_path + ".lock"
    if not acquire_lock(lock_dir):
        decision("stop-hook-active")
        return
    atexit.register(release_lock, lock_dir)

    rows = read_ledger(ledger_path)
    if rows is None:
        decision("stop-hook-active")
        return

    requested = confirmable_by(rows, payload.get("sessionId"))
    if requested is None:
        decision("stop-hook-active")
        return

    requested["routed"] = True
    requested["routed_at"] = payload.get("timestamp")
    if not write_ledger(ledger_path, rows):
        decision("stop-hook-active")
        return

    target = requested.get("target")
    if isinstance(target, str) and target:
        decision("stop-hook-active", confirmed=target)
    else:
        decision("stop-hook-active")


try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

if not isinstance(payload, dict):
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

root = repository_root(payload.get("cwd"))
ledger_path = None
if root is not None:
    candidate = os.path.join(root, LEDGER_RELATIVE_PATH)
    if os.path.exists(candidate):
        ledger_path = candidate

if payload.get("stop_hook_active") is True:
    confirm_route_request(payload, ledger_path)
    raise SystemExit(0)

if root is None:
    decision("repository-not-found")
    raise SystemExit(0)

if ledger_path is None:
    decision("no-ledger")
    raise SystemExit(0)

lock_dir = ledger_path + ".lock"
if not acquire_lock(lock_dir):
    decision("ledger-busy")
    raise SystemExit(0)
atexit.register(release_lock, lock_dir)

rows = read_ledger(ledger_path)
if rows is None:
    decision("invalid-ledger")
    raise SystemExit(0)

unrouted = next((row for row in rows if owed_a_route(row)), None)
if unrouted is None:
    decision("no-unrouted-completion")
    raise SystemExit(0)

target = unrouted.get("target")
if not isinstance(target, str) or not target:
    decision("invalid-completed-row")
    raise SystemExit(0)

attempts = route_attempts(unrouted)

if attempts >= MAX_ROUTE_ATTEMPTS:
    # Every request so far went unconfirmed, so asking again will not land
    # either. Give up under a reason that names what was dropped, rather than
    # re-blocking until the runtime halts the session without explaining why.
    unrouted["route_abandoned"] = True
    unrouted["route_abandoned_at"] = payload.get("timestamp")
    if not write_ledger(ledger_path, rows):
        decision("ledger-update-failed")
        raise SystemExit(0)
    decision("route-abandoned", target=target)
    raise SystemExit(0)

# A request is confirmed by a turn from the session that asked for it, so a
# payload carrying no `sessionId` cannot produce one. Blocking on it anyway
# would force a turn nothing could ever credit, and re-block until the cap
# abandoned a hop that had in fact landed. ADR-0005 requires a field the chain
# reads, and this path reads this one, so name what is missing and stand aside.
session = payload.get("sessionId")
if not isinstance(session, str) or not session:
    decision("missing-session-id", target=target)
    raise SystemExit(0)

unrouted["route_attempts"] = attempts + 1
# The first request time is the one worth keeping: with the attempt count it
# says how long this hop has been owed, not merely when it was last asked for.
# Keeping it means skipping an absent one rather than storing a null, which
# would claim the first slot and lose every later time the payload did carry.
requested_at = payload.get("timestamp")
if requested_at and not unrouted.get("route_requested_at"):
    unrouted["route_requested_at"] = requested_at
# Every session that asked is kept, not just the latest: each one is holding a
# forced turn that will arrive, and the first to arrive should confirm the hop
# rather than find its request taken over and ask again.
requesters = route_requesters(unrouted)
if session not in requesters:
    unrouted["route_requested_by"] = requesters + [session]
if not write_ledger(ledger_path, rows):
    decision("ledger-update-failed")
    raise SystemExit(0)

print(
    json.dumps(
        {"decision": "block", "reason": BLOCK_REASON, "target": target},
        separators=(",", ":"),
    )
)
