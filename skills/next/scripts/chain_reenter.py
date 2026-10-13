#!/usr/bin/env python3
"""Implement the route-request contract described by ADR-0008."""
import atexit
import json
import os
import subprocess
import sys
from typing import Optional

from chain_ledger import (
    LEDGER_RELATIVE_PATH,
    acquire_lock,
    cleanup_replacements,
    is_open,
    read_ledger,
    release_lock,
    repository_root,
    write_ledger,
)

# Re-blocking an unconfirmed request has to stop somewhere. The runtime permits
# 8 consecutive blocks and then exits without saying why, so the chain's own cap
# trips first and names what it abandoned — see ADR-0004.
MAX_ROUTE_ATTEMPTS = 3

def decision(reason: str, **details: object) -> None:
    print(json.dumps({"decision": "allow", "reason": reason, **details}, separators=(",", ":")))


def owed_a_route(row: object) -> bool:
    """A finished run the chain still owes a route.

    Neither a routed row nor an abandoned one is owed anything: the first was
    confirmed, and the second gave up under a reason that named it.
    """
    return (
        isinstance(row, dict)
        and not is_open(row)
        and row.get("outcome") != "reclaimed"
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


def awaiting_confirmation(row: object) -> bool:
    return owed_a_route(row) and route_attempts(row) > 0


def requested_by(row: dict) -> list:
    sessions = row.get("route_requested_by")
    if not isinstance(sessions, list):
        return []
    return [session for session in sessions if isinstance(session, str) and session]


def confirm_route_request(payload: dict, ledger_path: Optional[str]) -> None:
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
    cleanup_replacements(ledger_path)

    rows = read_ledger(ledger_path)
    if rows is None:
        decision("stop-hook-active")
        return

    session = payload.get("sessionId")
    requested = [
        row
        for row in rows
        if awaiting_confirmation(row)
        and isinstance(row.get("target"), str)
        and row["target"]
        and (
            not isinstance(session, str)
            or not session
            or not requested_by(row)
            or session in requested_by(row)
        )
    ]
    if not requested:
        decision("stop-hook-active")
        return

    for row in requested:
        row["routed"] = True
        row["routed_at"] = payload.get("timestamp")
    if not write_ledger(ledger_path, rows):
        decision("stop-hook-active")
        return

    targets = [
        row["target"]
        for row in requested
        if isinstance(row.get("target"), str) and row["target"]
    ]
    if len(targets) == 1:
        decision("stop-hook-active", confirmed=targets[0])
    else:
        decision("stop-hook-active", confirmed=targets)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        decision("invalid-agent-stop-payload")
        return

    if not isinstance(payload, dict):
        decision("invalid-agent-stop-payload")
        return

    root = None
    cwd = payload.get("cwd")
    if isinstance(cwd, str) and cwd:
        try:
            root = repository_root(cwd)
        except (OSError, subprocess.CalledProcessError, ValueError) as error:
            print(f"error: could not resolve repository root: {error}", file=sys.stderr)
    ledger_path = None
    if root is not None:
        candidate = os.path.join(root, LEDGER_RELATIVE_PATH)
        if os.path.exists(candidate):
            ledger_path = candidate

    if payload.get("stop_hook_active") is True:
        confirm_route_request(payload, ledger_path)
        return

    if root is None:
        decision("repository-not-found")
        return

    if ledger_path is None:
        decision("no-ledger")
        return

    lock_dir = ledger_path + ".lock"
    if not acquire_lock(lock_dir):
        decision("ledger-busy")
        return
    atexit.register(release_lock, lock_dir)
    cleanup_replacements(ledger_path)

    rows = read_ledger(ledger_path)
    if rows is None:
        decision("invalid-ledger")
        return

    unrouted = [row for row in rows if owed_a_route(row)]
    if not unrouted:
        decision("no-unrouted-completion")
        return

    targets = [
        row["target"]
        for row in unrouted
        if isinstance(row.get("target"), str) and row["target"]
    ]
    if not targets:
        decision("invalid-completed-row")
        return

    abandoned = [
        row for row in unrouted
        if isinstance(row.get("target"), str)
        and row["target"]
        and route_attempts(row) >= MAX_ROUTE_ATTEMPTS
    ]
    for row in abandoned:
        row["route_abandoned"] = True
        row["route_abandoned_at"] = payload.get("timestamp")

    pending = [
        row
        for row in unrouted
        if row not in abandoned
        and isinstance(row.get("target"), str)
        and row["target"]
    ]
    if not pending:
        if not write_ledger(ledger_path, rows):
            decision("ledger-update-failed")
            return
        abandoned_targets = [row["target"] for row in abandoned]
        if len(abandoned_targets) == 1:
            decision("route-abandoned", target=abandoned_targets[0])
        else:
            decision("route-abandoned", targets=abandoned_targets)
        return

    for row in pending:
        row["route_attempts"] = route_attempts(row) + 1
        # Timestamp is provenance only; the attempt count makes it confirmable.
        requested_at = payload.get("timestamp")
        if requested_at and not row.get("route_requested_at"):
            row["route_requested_at"] = requested_at
        session = payload.get("sessionId")
        if isinstance(session, str) and session and session not in requested_by(row):
            row["route_requested_by"] = requested_by(row) + [session]
    if not write_ledger(ledger_path, rows):
        decision("ledger-update-failed")
        return

    requested_targets = [row["target"] for row in pending]
    abandoned_targets = [row["target"] for row in abandoned]
    if abandoned_targets:
        abandoned_text = ", ".join(abandoned_targets)
        reason = f"Route abandoned for {abandoned_text}. "
    else:
        reason = ""
    if len(requested_targets) == 1:
        reason += "A completed run is unrouted. Run /next now."
    else:
        reason += (
            f"{len(requested_targets)} completed runs are unrouted. "
            "Run /next now and refill every freed slot."
        )
    print(
        json.dumps(
            {"decision": "block", "reason": reason, "targets": requested_targets},
            separators=(",", ":"),
        )
    )
