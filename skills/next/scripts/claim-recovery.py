#!/usr/bin/env python3
"""Shared liveness checks for ledger claims and their recovery locks."""

import argparse
from chain_ledger import claim_is_stale, owner_is_gone


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
