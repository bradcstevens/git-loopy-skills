#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  chain.sh plan --route ROUTE --target TARGET --safety SAFETY \
    --agent AGENT --model MODEL --effort EFFORT --context-tier TIER \
    --worktree PATH [--ledger PATH]
  chain.sh record --route ROUTE --target TARGET --session-id ID --agent-id ID \
    --agent-type TYPE --agent-name NAME --spawn-time TIMESTAMP --worktree PATH \
    --chain-depth N [--ledger PATH]
  chain.sh complete [--ledger PATH] < subagent-stop-payload.json
  chain.sh recover --stale-after-seconds N [--now TIMESTAMP] [--ledger PATH]

A PID-less ledger lock is recoverable after CHAIN_LOCK_STALE_SECONDS (default: 300).
EOF
  exit 2
}

ledger="${CHAIN_LEDGER:-}"
lock_dir=""
tmp=""
metadata=""
lock_acquired=0
created_worktree=0
created_worktree_path=""
repo_root=""

cleanup() {
  if [ "$lock_acquired" -eq 1 ]; then
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$metadata" ] || rm -f "$metadata"
  if [ "$created_worktree" -eq 1 ]; then
    if ! git -C "$repo_root" worktree remove --force "$created_worktree_path"; then
      echo "error: could not remove unrecorded worktree: $created_worktree_path" >&2
    fi
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

release_lock() {
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir"
  lock_acquired=0
}

repository_root() {
  git worktree list --porcelain |
    awk '/^worktree / { sub(/^worktree /, ""); print; exit }'
}

remove_stale_lock() {
  local stale claim_dir recovery_dir
  recovery_dir="$lock_dir.recovery"
  mkdir "$recovery_dir" 2>/dev/null || return 0
  printf '%s\t%s\n' "$$" "$(ps -o lstart= -p "$$" | xargs)" > "$recovery_dir/pid"

  if ! stale="$(python3 - "$lock_dir" "${CHAIN_LOCK_STALE_SECONDS:-300}" <<'PY'
import os
import subprocess
import sys
import time

lock_dir, stale_after = sys.argv[1:]
try:
    stale_after_seconds = int(stale_after)
except ValueError:
    print("error: CHAIN_LOCK_STALE_SECONDS must be a non-negative integer", file=sys.stderr)
    raise SystemExit(2)
if stale_after_seconds < 0:
    print("error: CHAIN_LOCK_STALE_SECONDS must be a non-negative integer", file=sys.stderr)
    raise SystemExit(2)

pid_path = os.path.join(lock_dir, "pid")
try:
    with open(pid_path, encoding="utf-8") as owner:
        pid_text, owner_start = owner.read().rstrip("\n").split("\t", 1)
        pid = int(pid_text)
except (FileNotFoundError, ValueError):
    try:
        stale = time.time() - os.stat(lock_dir).st_mtime >= stale_after_seconds
    except FileNotFoundError:
        stale = False
else:
    try:
        if pid <= 0:
            raise ProcessLookupError
        os.kill(pid, 0)
    except ProcessLookupError:
        stale = True
    except PermissionError:
        stale = False
    else:
        current_start = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
        ).stdout.split()
        current_start = " ".join(current_start)
        stale = current_start != owner_start

print("true" if stale else "false")
PY
  )"; then
    rm -f "$recovery_dir/pid"
    rmdir "$recovery_dir"
    return 2
  fi

  if [ "$stale" = "true" ]; then
    claim_dir="$lock_dir.reclaim.$$.$RANDOM"
    if mv "$lock_dir" "$claim_dir" 2>/dev/null; then
      rm -f "$claim_dir/pid"
      rmdir "$claim_dir"
    fi
  fi
  rm -f "$recovery_dir/pid"
  rmdir "$recovery_dir"
}

recover_stale_recovery_lock() {
  local recovery_dir="$lock_dir.recovery" stale claim_dir

  [ -d "$recovery_dir" ] || return 0
  stale="$(python3 - "$recovery_dir" "${CHAIN_LOCK_STALE_SECONDS:-300}" <<'PY'
import os
import subprocess
import sys
import time

lock_dir, stale_after = sys.argv[1:]
stale_after_seconds = int(stale_after)
pid_path = os.path.join(lock_dir, "pid")
try:
    with open(pid_path, encoding="utf-8") as owner:
        pid_text, owner_start = owner.read().rstrip("\n").split("\t", 1)
        pid = int(pid_text)
except (FileNotFoundError, ValueError):
    try:
        stale = time.time() - os.stat(lock_dir).st_mtime >= stale_after_seconds
    except FileNotFoundError:
        stale = False
else:
    try:
        if pid <= 0:
            raise ProcessLookupError
        os.kill(pid, 0)
    except ProcessLookupError:
        stale = True
    except PermissionError:
        stale = False
    else:
        current_start = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
        ).stdout.split()
        stale = " ".join(current_start) != owner_start

print("true" if stale else "false")
PY
)"
  if [ "$stale" = "true" ]; then
  claim_dir="$recovery_dir.reclaim.$$.$RANDOM"
  if mv "$recovery_dir" "$claim_dir" 2>/dev/null; then
    rm -f "$claim_dir/pid"
    rmdir "$claim_dir" 2>/dev/null || true
  fi
fi
}

acquire_lock() {
  while :; do
    while [ -d "$lock_dir.recovery" ]; do
      recover_stale_recovery_lock
      sleep 0.01
    done
    if mkdir "$lock_dir" 2>/dev/null; then
      lock_acquired=1
      printf '%s\t%s\n' "$$" "$(ps -o lstart= -p "$$" | xargs)" > "$lock_dir/pid"
      return
    fi
    remove_stale_lock
    sleep 0.01
  done
}

remove_worktree() {
  local worktree="$1"
  local ledger_root

  if [ -e "$worktree" ]; then
    git -C "$worktree" worktree remove --force "$worktree"
  else
    ledger_root="$(repository_root)"
    git -C "$ledger_root" worktree prune
  fi
}

ledger_has_open_worktree() {
  python3 - "$ledger" "$1" <<'PY'
import json
import os
import sys

ledger, worktree = sys.argv[1:]
worktree = os.path.realpath(os.path.abspath(worktree))
if not os.path.exists(ledger):
    raise SystemExit(1)

with open(ledger, encoding="utf-8") as ledger_file:
    for raw_line in ledger_file:
        line = raw_line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            print(f"error: invalid spawn ledger: {error}", file=sys.stderr)
            raise SystemExit(2)
        row_worktree = row.get("worktree")
        if (
            isinstance(row_worktree, str)
            and row_worktree
            and os.path.realpath(os.path.abspath(row_worktree)) == worktree
            and not row.get("finish_time")
        ):
            raise SystemExit(0)

raise SystemExit(1)
PY
}

mark_record_failed() {
  local session_id="$1" agent_id="$2"

  tmp="$(mktemp "$(dirname "$ledger")/.subagents.XXXXXX")"
  python3 - "$ledger" "$tmp" "$session_id" "$agent_id" <<'PY'
import datetime
import json
import sys

ledger_path, output_path, session_id, agent_id = sys.argv[1:]
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

matches = [
    row
    for row in rows
    if (
        row.get("session_id") == session_id
        and row.get("agent_id") == agent_id
        and not row.get("finish_time")
    )
]
if len(matches) != 1:
    print("error: could not close failed worktree reservation", file=sys.stderr)
    raise SystemExit(2)

matches[0]["finish_time"] = (
    datetime.datetime.now(datetime.timezone.utc)
    .isoformat(timespec="seconds")
    .replace("+00:00", "Z")
)
matches[0]["outcome"] = "failed"

with open(output_path, "w", encoding="utf-8") as output:
    for row in rows:
        output.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
  mv "$tmp" "$ledger"
  tmp=""
}

plan() {
  local route="" target="" safety="" agent="" model="" effort="" context_tier="" worktree=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="${2:?missing value for --route}"; shift 2 ;;
      --target) target="${2:?missing value for --target}"; shift 2 ;;
      --safety) safety="${2:?missing value for --safety}"; shift 2 ;;
      --agent) agent="${2:?missing value for --agent}"; shift 2 ;;
      --model) model="${2:?missing value for --model}"; shift 2 ;;
      --effort) effort="${2:?missing value for --effort}"; shift 2 ;;
      --context-tier) context_tier="${2:?missing value for --context-tier}"; shift 2 ;;
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$safety" ] && [ -n "$agent" ] &&
    [ -n "$model" ] && [ -n "$effort" ] && [ -n "$context_tier" ] &&
    [ -n "$worktree" ] || usage

  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi

  local worktree_held=0 collision_status
  if ledger_has_open_worktree "$worktree"; then
    worktree_held=1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  python3 - "$ledger" "$route" "$target" "$safety" "$agent" "$model" "$effort" "$context_tier" "$worktree" "$worktree_held" <<'PY'
import json
import os
import sys

ledger, route, target, safety, agent, model, effort, context_tier, worktree, worktree_held = sys.argv[1:]
worktree = os.path.realpath(os.path.abspath(worktree))
worktree_held = worktree_held == "1"
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
    target_failed = False
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
                if row["target"] == target and row.get("outcome") in {"failed", "no-evidence"}:
                    target_failed = True

    if in_flight:
        decision = {
            "decision": "decline",
            "reason": "target-in-flight",
            "route": route,
            "target": target,
        }
    elif target_failed:
        decision = {
            "decision": "decline",
            "reason": "target-failed",
            "route": route,
            "target": target,
        }
    elif worktree_held:
        decision = {
            "decision": "decline",
            "reason": "worktree-in-flight",
            "route": route,
            "target": target,
            "worktree": worktree,
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
            "worktree": worktree,
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
  local ledger_dir row spawn_commit worktree_branch
  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi
  ledger_dir="$(dirname "$ledger")"
  lock_dir="$ledger.lock"
  spawn_commit="$(git rev-parse HEAD)"
  repo_root="$(repository_root)"
  worktree_branch="git-loopy/${session_id//[![:alnum:]._-]/-}"
  worktree="$(python3 -c 'import os; import sys; print(os.path.realpath(os.path.abspath(sys.argv[1])))' "$worktree")"
  mkdir -p "$ledger_dir"

  acquire_lock

  local collision_status
  if ledger_has_open_worktree "$worktree"; then
    echo "error: worktree-in-flight: $worktree" >&2
    exit 1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

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
  if [ -n "${CHAIN_RECORD_PAUSE_BEFORE_WORKTREE:-}" ]; then
    sleep "$CHAIN_RECORD_PAUSE_BEFORE_WORKTREE"
  fi
  if ! git -C "$repo_root" worktree add -b "$worktree_branch" "$worktree" "$spawn_commit"; then
    mark_record_failed "$session_id" "$agent_id"
    exit 1
  fi
  created_worktree=1
  created_worktree_path="$worktree"
  created_worktree=0
  release_lock
}

complete() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi

  local ledger_dir result
  ledger_dir="$(dirname "$ledger")"
  mkdir -p "$ledger_dir"
  lock_dir="$ledger.lock"

  acquire_lock

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  metadata="$tmp.worktree"
  result="$(
    python3 -c '
import datetime
import json
import os
import subprocess
import sys

ledger_path, output_path, metadata_path = sys.argv[1:]
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
worktree = row.get("worktree")
if not isinstance(target, str) or not target:
    print("error: matching spawn ledger row has no target", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(spawn_time, str) or not spawn_time:
    print("error: matching spawn ledger row has no spawn_time", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(worktree, str) or not worktree:
    print("error: matching spawn ledger row has no worktree", file=sys.stderr)
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
with open(metadata_path, "w", encoding="utf-8") as metadata:
    metadata.write(worktree + "\n")

print(json.dumps({
    "continue": has_evidence,
    "outcome": outcome,
    "target": target,
}, separators=(",", ":")))
' "$ledger" "$tmp" "$metadata"
  )"

  if python3 -c '
import json
import sys

raise SystemExit(0 if json.load(sys.stdin).get("reason") is None else 1)
' <<< "$result"; then
    remove_worktree "$(cat "$metadata")"
    mv "$tmp" "$ledger"
  else
    rm -f "$tmp"
  fi
  tmp=""
  rm -f "$metadata"
  metadata=""
  release_lock
  printf '%s\n' "$result"
}

recover() {
  local stale_after="" now=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stale-after-seconds) stale_after="${2:?missing value for --stale-after-seconds}"; shift 2 ;;
      --now) now="${2:?missing value for --now}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$stale_after" ] || usage
  [[ "$stale_after" =~ ^[0-9]+$ ]] || {
    echo "error: --stale-after-seconds must be a non-negative integer" >&2
    exit 2
  }

  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi

  local ledger_dir result
  ledger_dir="$(dirname "$ledger")"
  mkdir -p "$ledger_dir"
  lock_dir="$ledger.lock"
  acquire_lock

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  metadata="$tmp.worktrees"
  result="$(
    python3 -c '
import datetime
import json
import os
import sys

ledger_path, output_path, metadata_path, stale_after, now = sys.argv[1:]

try:
    stale_after_seconds = int(stale_after)
except ValueError:
    print("error: --stale-after-seconds must be a non-negative integer", file=sys.stderr)
    raise SystemExit(2)

if now:
    try:
        recovered_at = datetime.datetime.fromisoformat(now.replace("Z", "+00:00"))
    except ValueError as error:
        print(f"error: --now must be an ISO-8601 timestamp: {error}", file=sys.stderr)
        raise SystemExit(2)
    if recovered_at.tzinfo is None:
        print("error: --now must include a timezone", file=sys.stderr)
        raise SystemExit(2)
else:
    recovered_at = datetime.datetime.now(datetime.timezone.utc)

rows = []
if os.path.exists(ledger_path):
    try:
        with open(ledger_path, encoding="utf-8") as ledger:
            rows = [json.loads(line) for line in ledger if line.strip()]
    except json.JSONDecodeError as error:
        print(f"error: invalid spawn ledger: {error}", file=sys.stderr)
        raise SystemExit(2)

recovered_worktrees = []
recovered_targets = []
for row in rows:
    if row.get("finish_time"):
        continue
    spawn_time = row.get("spawn_time")
    worktree = row.get("worktree")
    target = row.get("target")
    if not isinstance(spawn_time, str) or not spawn_time:
        print("error: open spawn ledger row has no spawn_time", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(worktree, str) or not worktree:
        print("error: open spawn ledger row has no worktree", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(target, str) or not target:
        print("error: open spawn ledger row has no target", file=sys.stderr)
        raise SystemExit(2)
    try:
        spawned_at = datetime.datetime.fromisoformat(spawn_time.replace("Z", "+00:00"))
    except ValueError as error:
        print(f"error: open spawn ledger row has invalid spawn_time: {error}", file=sys.stderr)
        raise SystemExit(2)
    if spawned_at.tzinfo is None:
        print("error: open spawn ledger row spawn_time must include a timezone", file=sys.stderr)
        raise SystemExit(2)
    if (recovered_at - spawned_at).total_seconds() >= stale_after_seconds:
        row["finish_time"] = (
            recovered_at.astimezone(datetime.timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z")
        )
        row["outcome"] = "failed"
        recovered_worktrees.append(worktree)
        recovered_targets.append(target)

with open(output_path, "w", encoding="utf-8") as output:
    for row in rows:
        output.write(json.dumps(row, separators=(",", ":")) + "\n")
with open(metadata_path, "w", encoding="utf-8") as metadata:
    for worktree in recovered_worktrees:
        metadata.write(worktree + "\n")

print(json.dumps({
    "recovered": len(recovered_targets),
    "targets": recovered_targets,
}, separators=(",", ":")))
' "$ledger" "$tmp" "$metadata" "$stale_after" "$now"
  )"

  local worktree
  while IFS= read -r worktree; do
    remove_worktree "$worktree"
  done < "$metadata"
  mv "$tmp" "$ledger"
  tmp=""
  rm -f "$metadata"
  metadata=""
  release_lock
  printf '%s\n' "$result"
}

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  plan) plan "$@" ;;
  record) record "$@" ;;
  complete) complete "$@" ;;
  recover) recover "$@" ;;
  *) usage ;;
esac
