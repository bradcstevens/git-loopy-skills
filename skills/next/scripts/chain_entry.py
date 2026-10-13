#!/usr/bin/env python3
"""Python entry for the chain's incrementally ported subcommands."""

from __future__ import print_function

import sys


def main():
    # Keep this entry parseable on older interpreters so the floor fails clearly.
    if sys.version_info < (3, 9):
        print("error: chain.sh requires Python 3.9 or newer", file=sys.stderr)
        return 2
    if sys.argv[1:] == ["--check-python"]:
        return 0
    if sys.argv[1:] == ["reenter"]:
        from chain_reenter import main as reenter

        reenter()
        return 0
    print("usage: chain.sh reenter < agent-stop-payload.json", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
