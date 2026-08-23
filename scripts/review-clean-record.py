#!/usr/bin/env python3
"""Create and match the review-clean evidence record.

The record is deliberately one line so a ticket comment can carry prose and a
machine-matchable verdict without relying on comment timing:

    review-clean: head=<40 lowercase hexadecimal characters>

This module is the single source of truth for that shape. Skills cite it
rather than copying its regular expression.
"""

from __future__ import annotations

import argparse
import re
import sys


RECORD_RE = re.compile(r"^review-clean: head=([0-9a-f]{40})$")


def record(head: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("head must be a 40-character lowercase SHA-1")
    return f"review-clean: head={head}"


def matching_record(comment: str, head: str) -> bool:
    return any(
        (match := RECORD_RE.fullmatch(line.strip())) is not None
        and match.group(1) == head
        for line in comment.splitlines()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    emit = subparsers.add_parser("emit", help="emit a clean-review record")
    emit.add_argument("head")

    match = subparsers.add_parser("match", help="match a comment against a head")
    match.add_argument("head")

    args = parser.parse_args()
    if args.command == "emit":
        try:
            print(record(args.head))
        except ValueError as error:
            parser.error(str(error))
        return 0

    if not re.fullmatch(r"[0-9a-f]{40}", args.head):
        parser.error("head must be a 40-character lowercase SHA-1")
    return 0 if matching_record(sys.stdin.read(), args.head) else 1


if __name__ == "__main__":
    raise SystemExit(main())
