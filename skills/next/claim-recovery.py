#!/usr/bin/env python3
"""Shared liveness checks for ledger claims and their recovery locks."""

import argparse
import datetime
import os
import subprocess
import sys
import time
from typing import Optional


def parse_process_start(value: str) -> Optional[datetime.datetime]:
    normalized = " ".join(value.split())
    try:
        parsed = datetime.datetime.strptime(
            normalized,
            "%a %b %d %H:%M:%S %Y",
        )
    except ValueError:
        return None
    if normalized.split()[0] != parsed.strftime("%a"):
        return None
    return parsed


def owner_is_gone(pid: int, owner_start: str) -> bool:
    try:
        if pid <= 0:
            raise ProcessLookupError
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False

    process = subprocess.run(
        ["ps", "-o", "lstart=", "-p", str(pid)],
        capture_output=True,
        text=True,
        env={**os.environ, "TZ": "UTC"},
    )
    current_start = " ".join(process.stdout.split())
    if process.returncode:
        return False
    recorded_start_at = parse_process_start(owner_start)
    current_start_at = parse_process_start(current_start)
    if recorded_start_at is None or current_start_at is None:
        return False
    return current_start_at != recorded_start_at


def claim_is_stale(claim_dir: str, stale_after_seconds: int) -> bool:
    try:
        with open(os.path.join(claim_dir, "pid"), encoding="utf-8") as owner:
            pid_text, owner_start = owner.read().rstrip("\n").split("\t", 1)
            pid = int(pid_text)
    except (FileNotFoundError, ValueError):
        try:
            return time.time() - os.stat(claim_dir).st_mtime >= stale_after_seconds
        except FileNotFoundError:
            return False
    return owner_is_gone(pid, owner_start)


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    owner_gone = commands.add_parser("owner-gone")
    owner_gone.add_argument("pid", type=int)
    owner_gone.add_argument("start")

    stale = commands.add_parser("claim-stale")
    stale.add_argument("claim_dir")
    stale.add_argument("stale_after_seconds", type=int)

    arguments = parser.parse_args()
    if arguments.command == "owner-gone":
        result = owner_is_gone(arguments.pid, arguments.start)
    else:
        if arguments.stale_after_seconds < 0:
            parser.error("stale_after_seconds must be non-negative")
        result = claim_is_stale(arguments.claim_dir, arguments.stale_after_seconds)
    print("true" if result else "false")


if __name__ == "__main__":
    main()
