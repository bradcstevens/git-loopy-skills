#!/usr/bin/env python3
"""Python entry for the chain's incrementally ported subcommands."""

from __future__ import print_function

import sys


def usage():
    print(USAGE, file=sys.stderr)
    return 2


def completion_command(command, args):
    import json
    import os
    import re
    import subprocess

    from chain_completion import complete, recover
    from chain_ledger import LEDGER_RELATIVE_PATH, locked_ledger, repository_root
    from chain_worktree import rollback_pending_worktree

    options = {"--ledger": os.environ.get("CHAIN_LEDGER", "")}
    if command == "recover":
        options.update({"--stale-after-seconds": "", "--now": ""})
    while args:
        flag = args[0]
        if flag not in options:
            return usage()
        if len(args) < 2 or not args[1]:
            print("error: missing value for " + flag, file=sys.stderr)
            return 1
        options[flag] = args[1]
        args = args[2:]
    if command == "recover":
        stale = options["--stale-after-seconds"]
        if not stale:
            return usage()
        if not re.fullmatch("[0-9]+", stale):
            print("error: --stale-after-seconds must be a non-negative integer", file=sys.stderr)
            return 2
    try:
        ledger = options["--ledger"] or os.path.join(
            repository_root(os.getcwd()), LEDGER_RELATIVE_PATH,
        )
        if command == "recover" and not any(
            os.path.exists(path) for path in (ledger, ledger + ".pending")
        ):
            result, status = {"recovered": 0, "targets": []}, 0
        else:
            with locked_ledger(ledger):
                rollback_pending_worktree(ledger + ".pending", ledger)
                if command == "complete":
                    result, status = complete(ledger, os.environ.get("CHAIN_TRACKER_BIN") or "gh")
                else:
                    result, status = recover(ledger, int(stale), options["--now"])
    except json.JSONDecodeError as error:
        print("error: invalid spawn ledger: " + str(error), file=sys.stderr)
        return 2
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, separators=(",", ":")))
    return status


USAGE = r"""usage:
  chain.sh plan --route ROUTE --target TARGET --safety SAFETY \
    --agent AGENT --model MODEL --effort EFFORT --context-tier TIER \
    --worktree PATH [--ledger PATH]
  chain.sh plan --no-ready [--ledger PATH]
  chain.sh plan --all-collide [--ledger PATH]
  chain.sh gate --pull-request NUMBER --ticket NUMBER [--repo OWNER/REPO]
  chain.sh reserve --route ROUTE --target TARGET --spawn-time TIMESTAMP \
    --worktree PATH --chain-depth N --parent-pid PID [--session-id ID] [--in-place] \
    [--ledger PATH]
  chain.sh bind --worktree PATH --session-id ID --agent-id ID \
    --agent-type TYPE --agent-name NAME [--ledger PATH]
  chain.sh complete [--ledger PATH] < subagent-stop-payload.json
  chain.sh reenter < agent-stop-payload.json
  chain.sh recover --stale-after-seconds N [--now TIMESTAMP] [--ledger PATH]
  chain.sh owner --worktree PATH
  chain.sh claim --worktree PATH --owner-pid PID [--create-branch BRANCH] [--ledger PATH]

A PID-less ledger lock is recoverable after CHAIN_LOCK_STALE_SECONDS (default: 300).
ROUTE is a slash-command name and carries its leading slash. The allowlist is
/implement, /code-review, /research, and /push; a bare
name such as "implement" is not a route and plan declines it as
route-not-allowlisted.
--parent-pid names the running process whose death orphans the reservation, which
is the session that will bind the run and never the shell that invokes this script.
Worktree ownership markers live at .git-loopy/worktree-owner and contain
"<pid>\t<process start time>\n"; compare both values to determine liveness. The
start time is that pid's `ps -o lstart=` output read under TZ=UTC, with runs of
whitespace collapsed to single spaces. Liveness compares the two start times as parsed
timestamps, so a marker recorded from local-time `ps` reports a live owner dead: every writer must
produce the value in UTC. A start time that does not parse reads as a live owner, never a dead
one. Use `claim` to mark a worktree this script did not
create, rather than writing the file by hand; `claim --create-branch` makes the
worktree too, so creating and marking it cannot come apart.
Route repetition and chain depth count bound rows only. Reservations claim
capacity and a worktree, but do not represent a spawned hop.
The two --no-ready and --all-collide forms end a fan-out fill; they are mutually
exclusive, take no candidate, and record nothing.
`bind --agent-name` is recorded for readability only; `complete` matches a row on
session id, agent id and agent type. `bind --session-id` is the routing session
that launches the run, never the agent id that launch returns, because
`subagentStop` reports a run under the session that launched it."""


def main():
    # Keep this entry parseable on older interpreters so the floor fails clearly.
    if sys.version_info < (3, 9):
        print("error: chain.sh requires Python 3.9 or newer", file=sys.stderr)
        return 2
    if sys.argv[1:] == ["--check-python"]:
        return 0
    if sys.argv[1:] == ["--usage"]:
        return usage()
    if sys.argv[1:2] in (["complete"], ["recover"]):
        return completion_command(sys.argv[1], sys.argv[2:])
    if sys.argv[1:] == ["reenter"]:
        from chain_reenter import main as reenter

        reenter()
        return 0
    print("usage: chain.sh reenter < agent-stop-payload.json", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
