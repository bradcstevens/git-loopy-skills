#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  chain.sh plan --route ROUTE --target TARGET --safety SAFETY \
    --agent AGENT --model MODEL --effort EFFORT --context-tier TIER [--ledger PATH]
  chain.sh record --route ROUTE --target TARGET --session-id ID --agent-id ID \
    --agent-type TYPE --agent-name NAME --spawn-time TIMESTAMP --worktree PATH \
    --chain-depth N [--ledger PATH]
  chain.sh complete [--ledger PATH] < subagent-stop-payload.json
EOF
  exit 2
}

ledger="${CHAIN_LEDGER:-}"
lock_dir=""
tmp=""
lock_acquired=0

cleanup() {
  if [ "$lock_acquired" -eq 1 ]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  [ -z "$tmp" ] || rm -f "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

plan() {
  local route="" target="" safety="" agent="" model="" effort="" context_tier=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="${2:?missing value for --route}"; shift 2 ;;
      --target) target="${2:?missing value for --target}"; shift 2 ;;
      --safety) safety="${2:?missing value for --safety}"; shift 2 ;;
      --agent) agent="${2:?missing value for --agent}"; shift 2 ;;
      --model) model="${2:?missing value for --model}"; shift 2 ;;
      --effort) effort="${2:?missing value for --effort}"; shift 2 ;;
      --context-tier) context_tier="${2:?missing value for --context-tier}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$safety" ] && [ -n "$agent" ] &&
    [ -n "$model" ] && [ -n "$effort" ] && [ -n "$context_tier" ] || usage

  if [ -z "$ledger" ]; then
    ledger="$(git rev-parse --show-toplevel)/.git-loopy/subagents.jsonl"
  fi

  python3 - "$ledger" "$route" "$target" "$safety" "$agent" "$model" "$effort" "$context_tier" <<'PY'
import json
import os
import sys

ledger, route, target, safety, agent, model, effort, context_tier = sys.argv[1:]
allowlisted_routes = {
    "/implement",
    "/code-review",
    "/research",
    "/push",
    "/resolving-merge-conflicts",
}

if route not in allowlisted_routes:
    decision = {
        "decision": "decline",
        "reason": "route-not-allowlisted",
        "route": route,
        "target": target,
    }
elif safety != "AFK-safe":
    decision = {
        "decision": "decline",
        "reason": "action-not-afk-safe",
        "route": route,
        "target": target,
    }
else:
    in_flight = False
    if os.path.exists(ledger):
        with open(ledger, encoding="utf-8") as ledger_file:
            for raw_line in ledger_file:
                line = raw_line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row["target"] == target and not row.get("finish_time"):
                    in_flight = True
                    break

    if in_flight:
        decision = {
            "decision": "decline",
            "reason": "target-in-flight",
            "route": route,
            "target": target,
        }
    else:
        decision = {
            "decision": "spawn",
            "route": route,
            "target": target,
            "agent": agent,
            "model": model,
            "effort": effort,
            "context_tier": context_tier,
        }

print(json.dumps(decision, separators=(",", ":")))
PY
}

record() {
  local route="" target="" session_id="" agent_id="" agent_type="" agent_name=""
  local spawn_time="" worktree="" chain_depth=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="${2:?missing value for --route}"; shift 2 ;;
      --target) target="${2:?missing value for --target}"; shift 2 ;;
      --session-id) session_id="${2:?missing value for --session-id}"; shift 2 ;;
      --agent-id) agent_id="${2:?missing value for --agent-id}"; shift 2 ;;
      --agent-type) agent_type="${2:?missing value for --agent-type}"; shift 2 ;;
      --agent-name) agent_name="${2:?missing value for --agent-name}"; shift 2 ;;
      --spawn-time) spawn_time="${2:?missing value for --spawn-time}"; shift 2 ;;
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --chain-depth) chain_depth="${2:?missing value for --chain-depth}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$session_id" ] &&
    [ -n "$agent_id" ] && [ -n "$agent_type" ] && [ -n "$agent_name" ] &&
    [ -n "$spawn_time" ] && [ -n "$worktree" ] && [ -n "$chain_depth" ] || usage
  [[ "$chain_depth" =~ ^[0-9]+$ ]] || {
    echo "error: --chain-depth must be a non-negative integer" >&2
    exit 2
  }
  local ledger_dir row
  if [ -z "$ledger" ]; then
    ledger="$(git rev-parse --show-toplevel)/.git-loopy/subagents.jsonl"
  fi
  ledger_dir="$(dirname "$ledger")"
  lock_dir="$ledger.lock"
  mkdir -p "$ledger_dir"

  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.01
  done
  lock_acquired=1

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  row="$(python3 - "$route" "$target" "$session_id" "$agent_id" "$agent_type" "$agent_name" "$spawn_time" "$worktree" "$chain_depth" <<'PY'
import json
import sys

route, target, session_id, agent_id, agent_type, agent_name, spawn_time, worktree, chain_depth = sys.argv[1:]
row = {
    "route": route,
    "target": target,
    "session_id": session_id,
    "spawn_time": spawn_time,
    "worktree": worktree,
    "chain_depth": int(chain_depth),
    "finish_time": "",
    "outcome": "",
}
row["agent_id"] = agent_id
row["agent_type"] = agent_type
row["agent_name"] = agent_name
print(json.dumps(row, separators=(",", ":")))
PY
)"

  if [ -f "$ledger" ]; then
    cat "$ledger" > "$tmp"
  fi
  printf '%s\n' "$row" >> "$tmp"

  if [ -n "${CHAIN_RECORD_PAUSE_BEFORE_COMMIT:-}" ]; then
    sleep "$CHAIN_RECORD_PAUSE_BEFORE_COMMIT"
  fi
  mv "$tmp" "$ledger"
  tmp=""
  lock_acquired=0
  rmdir "$lock_dir"
}

complete() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  if [ -z "$ledger" ]; then
    ledger="$(git rev-parse --show-toplevel)/.git-loopy/subagents.jsonl"
  fi

  local ledger_dir result
  ledger_dir="$(dirname "$ledger")"
  mkdir -p "$ledger_dir"
  lock_dir="$ledger.lock"

  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.01
  done
  lock_acquired=1

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  result="$(
    python3 -c '
import datetime
import json
import os
import subprocess
import sys

ledger_path, output_path = sys.argv[1:]
required_fields = (
    "sessionId",
    "timestamp",
    "cwd",
    "transcriptPath",
    "agentId",
    "agentType",
    "agentName",
    "agentDisplayName",
    "response",
    "stopReason",
)

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as error:
    print(f"error: invalid subagent-stop payload: {error}", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(payload, dict):
    print("error: subagent-stop payload must be a JSON object", file=sys.stderr)
    raise SystemExit(2)

missing = [field for field in required_fields if field not in payload]
if missing:
    print(
        "error: subagent-stop payload is missing " + ", ".join(missing),
        file=sys.stderr,
    )
    raise SystemExit(2)

invalid = [
    field
    for field in required_fields
    if field != "timestamp" and not isinstance(payload[field], str)
]
if invalid:
    print(
        "error: subagent-stop payload has non-string " + ", ".join(invalid),
        file=sys.stderr,
    )
    raise SystemExit(2)
if isinstance(payload["timestamp"], bool) or not isinstance(
    payload["timestamp"],
    (str, int, float),
):
    print("error: subagent-stop payload has non-string timestamp", file=sys.stderr)
    raise SystemExit(2)

agent_id = payload["agentId"]
if not agent_id:
    print("error: subagent-stop payload has an empty agentId", file=sys.stderr)
    raise SystemExit(2)

rows = []
if os.path.exists(ledger_path):
    try:
        with open(ledger_path, encoding="utf-8") as ledger:
            rows = [json.loads(line) for line in ledger if line.strip()]
    except json.JSONDecodeError as error:
        print(f"error: invalid spawn ledger: {error}", file=sys.stderr)
        raise SystemExit(2)

matches = [
    index
    for index, row in enumerate(rows)
    if (
        row.get("session_id") == payload["sessionId"]
        and row.get("agent_id") == agent_id
        and row.get("agent_type") == payload["agentType"]
        and row.get("agent_name") == payload["agentName"]
        and not row.get("finish_time")
    )
]

if not matches:
    print(json.dumps({
        "continue": False,
        "reason": "unmatched-payload",
        "agent_id": agent_id,
    }, separators=(",", ":")))
    raise SystemExit(0)

if len(matches) > 1:
    print(json.dumps({
        "continue": False,
        "reason": "ambiguous-payload",
        "agent_id": agent_id,
    }, separators=(",", ":")))
    raise SystemExit(0)

row = rows[matches[0]]
target = row.get("target")
spawn_time = row.get("spawn_time")
if not isinstance(target, str) or not target:
    print("error: matching spawn ledger row has no target", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(spawn_time, str) or not spawn_time:
    print("error: matching spawn ledger row has no spawn_time", file=sys.stderr)
    raise SystemExit(2)

try:
    spawn_at = datetime.datetime.fromisoformat(spawn_time.replace("Z", "+00:00"))
except ValueError as error:
    print(f"error: matching spawn ledger row has invalid spawn_time: {error}", file=sys.stderr)
    raise SystemExit(2)
timestamp = payload["timestamp"]
try:
    if isinstance(timestamp, str):
        finish_at = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    else:
        finish_at = datetime.datetime.fromtimestamp(
            timestamp / 1000,
            tz=datetime.timezone.utc,
        )
except (TypeError, ValueError, OverflowError) as error:
    print(f"error: subagent-stop payload has invalid timestamp: {error}", file=sys.stderr)
    raise SystemExit(2)
if finish_at.tzinfo is None:
    print("error: subagent-stop payload timestamp must include a timezone", file=sys.stderr)
    raise SystemExit(2)

tracker = subprocess.run(
    ["gh", "issue", "view", target, "--json", "comments"],
    capture_output=True,
    cwd=payload["cwd"],
    text=True,
)
if tracker.returncode:
    sys.stderr.write(tracker.stderr)
    raise SystemExit(tracker.returncode)

try:
    comments = json.loads(tracker.stdout).get("comments", [])
except json.JSONDecodeError as error:
    print(f"error: tracker returned invalid comment data: {error}", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(comments, list):
    print("error: tracker returned comments in an invalid format", file=sys.stderr)
    raise SystemExit(2)

has_evidence = False
for comment in comments:
    created_at = comment.get("createdAt") if isinstance(comment, dict) else None
    if not isinstance(created_at, str):
        continue
    try:
        comment_at = datetime.datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError:
        continue
    if spawn_at <= comment_at <= finish_at:
        has_evidence = True
        break

outcome = "published" if has_evidence else "no-evidence"
row["finish_time"] = (
    finish_at.astimezone(datetime.timezone.utc)
    .isoformat(timespec="seconds")
    .replace("+00:00", "Z")
)
row["outcome"] = outcome

with open(output_path, "w", encoding="utf-8") as output:
    for updated_row in rows:
        output.write(json.dumps(updated_row, separators=(",", ":")) + "\n")

print(json.dumps({
    "continue": has_evidence,
    "outcome": outcome,
    "target": target,
}, separators=(",", ":")))
' "$ledger" "$tmp"
  )"

  if python3 -c '
import json
import sys

raise SystemExit(0 if json.load(sys.stdin).get("reason") is None else 1)
' <<< "$result"; then
    mv "$tmp" "$ledger"
  else
    rm -f "$tmp"
  fi
  tmp=""
  lock_acquired=0
  rmdir "$lock_dir"
  printf '%s\n' "$result"
}

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  plan) plan "$@" ;;
  record) record "$@" ;;
  complete) complete "$@" ;;
  *) usage ;;
esac
