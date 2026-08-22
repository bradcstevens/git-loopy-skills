#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  chain.sh plan --route ROUTE --target TARGET --safety SAFETY \
    --agent AGENT --model MODEL --effort EFFORT --context-tier TIER [--ledger PATH]
  chain.sh record --route ROUTE --target TARGET --session-id ID \
    --spawn-time TIMESTAMP --worktree PATH --chain-depth N [--ledger PATH]
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
  local route="" target="" session_id="" spawn_time="" worktree="" chain_depth=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="${2:?missing value for --route}"; shift 2 ;;
      --target) target="${2:?missing value for --target}"; shift 2 ;;
      --session-id) session_id="${2:?missing value for --session-id}"; shift 2 ;;
      --spawn-time) spawn_time="${2:?missing value for --spawn-time}"; shift 2 ;;
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --chain-depth) chain_depth="${2:?missing value for --chain-depth}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$session_id" ] &&
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
  row="$(python3 - "$route" "$target" "$session_id" "$spawn_time" "$worktree" "$chain_depth" <<'PY'
import json
import sys

route, target, session_id, spawn_time, worktree, chain_depth = sys.argv[1:]
print(json.dumps({
    "route": route,
    "target": target,
    "session_id": session_id,
    "spawn_time": spawn_time,
    "worktree": worktree,
    "chain_depth": int(chain_depth),
    "finish_time": "",
    "outcome": "",
}, separators=(",", ":")))
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

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  plan) plan "$@" ;;
  record) record "$@" ;;
  *) usage ;;
esac
