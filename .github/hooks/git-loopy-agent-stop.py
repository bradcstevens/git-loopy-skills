#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile


def decision(reason: str, **details: object) -> None:
    print(json.dumps({"decision": "allow", "reason": reason, **details}, separators=(",", ":")))


def repository_root(cwd: object) -> str | None:
    if not isinstance(cwd, str) or not cwd:
        return None

    result = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        return None
    return result.stdout.strip()


try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

if not isinstance(payload, dict):
    decision("invalid-agent-stop-payload")
    raise SystemExit(0)

if payload.get("stop_hook_active") is True:
    decision("stop-hook-active")
    raise SystemExit(0)

root = repository_root(payload.get("cwd"))
if root is None:
    decision("repository-not-found")
    raise SystemExit(0)

ledger_path = os.path.join(root, ".git-loopy", "subagents.jsonl")
if not os.path.exists(ledger_path):
    decision("no-ledger")
    raise SystemExit(0)

try:
    with open(ledger_path, encoding="utf-8") as ledger:
        rows = [json.loads(line) for line in ledger if line.strip()]
except (OSError, json.JSONDecodeError):
    decision("invalid-ledger")
    raise SystemExit(0)

unrouted = next(
    (
        row
        for row in rows
        if isinstance(row, dict) and row.get("finish_time") and not row.get("routed")
    ),
    None,
)
if unrouted is None:
    decision("no-unrouted-completion")
    raise SystemExit(0)

target = unrouted.get("target")
if not isinstance(target, str) or not target:
    decision("invalid-completed-row")
    raise SystemExit(0)

unrouted["routed"] = True
unrouted["routed_at"] = payload.get("timestamp")
ledger_dir = os.path.dirname(ledger_path)
try:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=ledger_dir,
        prefix=".subagents.",
        delete=False,
    ) as temporary:
        for row in rows:
            temporary.write(json.dumps(row, separators=(",", ":")) + "\n")
        temporary_path = temporary.name
    os.replace(temporary_path, ledger_path)
except OSError:
    if "temporary_path" in locals():
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
    decision("ledger-update-failed")
    raise SystemExit(0)

print(
    json.dumps(
        {
            "decision": "block",
            "reason": "completed-run-unrouted",
            "target": target,
        },
        separators=(",", ":"),
    )
)
