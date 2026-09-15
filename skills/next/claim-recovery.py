#!/usr/bin/env python3
"""Shared liveness checks for ledger claims and their recovery locks."""

import argparse
import os
import subprocess
import sys
import time


def normalize_start(value: str) -> str:
    return " ".join(value.split())


def owner_is_gone(pid: int, owner_start: str) -> bool:
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
        env={**os.environ, "TZ": "UTC"},
    ).stdout
    return normalize_start(current_start) != normalize_start(owner_start)


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
