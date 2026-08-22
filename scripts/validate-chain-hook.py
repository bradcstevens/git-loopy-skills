#!/usr/bin/env python3
import json
import os
import shlex
import sys


def error(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    error(f"usage: {sys.argv[0]} HOOK_PATH")

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as hook_file:
        hook = json.load(hook_file)
except (OSError, json.JSONDecodeError) as exc:
    error(f"{path} is not valid JSON: {exc}")

if not isinstance(hook, dict) or hook.get("version") != 1:
    error(f"{path} must have hook version 1")

hooks = hook.get("hooks")
if not isinstance(hooks, dict):
    error(f"{path} must define hook events")

for event, subcommand in (
    ("subagentStop", "complete"),
    ("agentStop", "reenter"),
):
    entries = hooks.get(event)
    if not isinstance(entries, list) or not entries:
        error(f"{path} must define a non-empty {event} hook")

    for entry in entries:
        command = entry.get("bash") if isinstance(entry, dict) and entry.get("type") == "command" else None
        if not isinstance(command, str):
            error(f"{path} has an {event} hook without a command")
        try:
            argv = shlex.split(command)
        except ValueError as exc:
            error(f"{path} has an invalid command: {exc}")
        if (
            len(argv) != 2
            or argv[0] != ".github/hooks/git-loopy-chain.sh"
            or argv[1] != subcommand
            or not os.path.isfile(argv[0])
        ):
            error(f"{path} must invoke the repository chain resolver with {subcommand}")
