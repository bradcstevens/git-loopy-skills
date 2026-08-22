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
subagent_stop = hooks.get("subagentStop") if isinstance(hooks, dict) else None
if not isinstance(subagent_stop, list) or not subagent_stop:
    error(f"{path} must define a non-empty subagentStop hook")

for entry in subagent_stop:
    command = entry.get("bash") if isinstance(entry, dict) and entry.get("type") == "command" else None
    if not isinstance(command, str):
        error(f"{path} has a subagentStop hook without a command")
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        error(f"{path} has an invalid command: {exc}")
    if len(argv) != 2 or argv[1] != "complete" or not os.path.isfile(argv[0]):
        error(f"{path} must invoke an existing chain script with complete")
