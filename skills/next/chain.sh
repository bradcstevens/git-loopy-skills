#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
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
    rm -f "$lock_dir/owner"
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  [ -z "$tmp" ] || rm -f "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

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
    if [ ! -e "$lock_dir/owner" ]; then
      rmdir "$lock_dir" 2>/dev/null || true
    elif ! kill -0 "$(cat "$lock_dir/owner")" 2>/dev/null; then
      rm -f "$lock_dir/owner"
      rmdir "$lock_dir" 2>/dev/null || true
    fi
    sleep 0.01
  done
  lock_acquired=1
  printf '%s\n' "$$" > "$lock_dir/owner"

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
  rm -f "$lock_dir/owner"
  lock_acquired=0
  rmdir "$lock_dir"
}

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  record) record "$@" ;;
  *) usage ;;
esac
