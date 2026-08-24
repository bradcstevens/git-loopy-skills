#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  chain.sh plan --route ROUTE --target TARGET --safety SAFETY \
    --agent AGENT --model MODEL --effort EFFORT --context-tier TIER \
    --worktree PATH [--ledger PATH]
  chain.sh plan --no-ready [--ledger PATH]
  chain.sh plan --all-collide [--ledger PATH]
  chain.sh reserve --route ROUTE --target TARGET --spawn-time TIMESTAMP \
    --worktree PATH --chain-depth N --parent-pid PID [--ledger PATH]
  chain.sh bind --worktree PATH --session-id ID --agent-id ID \
    --agent-type TYPE --agent-name NAME [--ledger PATH]
  chain.sh complete [--ledger PATH] < subagent-stop-payload.json
  chain.sh recover --stale-after-seconds N [--now TIMESTAMP] [--ledger PATH]
  chain.sh owner --worktree PATH
  chain.sh claim --worktree PATH --owner-pid PID [--create-branch BRANCH] [--ledger PATH]

A PID-less ledger lock is recoverable after CHAIN_LOCK_STALE_SECONDS (default: 300).
--parent-pid names the running process whose death orphans the reservation, which
is the session that will bind the run and never the shell that invokes this script.
Worktree ownership markers live at .git-loopy/worktree-owner and contain
"<pid>\t<process start time>\n"; compare both values to determine liveness. The
start time is that pid's `ps -o lstart=` output read under TZ=UTC, with runs of
whitespace collapsed to single spaces. Liveness compares the two strings, so a
marker recorded from local-time `ps` reports a live owner dead: every writer must
produce the value in UTC. Use `claim` to mark a worktree this script did not
create, rather than writing the file by hand; `claim --create-branch` makes the
worktree too, so creating and marking it cannot come apart.
Route repetition and chain depth count bound rows only. Reservations claim
capacity and a worktree, but do not represent a spawned hop.
The two --no-ready and --all-collide forms end a fan-out fill; they are mutually
exclusive, take no candidate, and record nothing.
EOF
  exit 2
}

ledger="${CHAIN_LEDGER:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claim_recovery="$script_dir/claim-recovery.py"
lock_dir=""
tmp=""
metadata=""
lock_acquired=0
pending=""
repo_root=""

cleanup() {
  if [ -n "$pending" ]; then
    rollback_pending_worktree "$pending" || true
    pending=""
  fi
  if [ "$lock_acquired" -eq 1 ]; then
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$metadata" ] || rm -f "$metadata"
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

process_start() {
  TZ=UTC ps -o lstart= -p "$1" | xargs
}

remove_stale_lock() {
  local stale claim_dir recovery_dir
  recovery_dir="$lock_dir.recovery"
  mkdir "$recovery_dir" 2>/dev/null || return 0
  printf '%s\t%s\n' "$$" "$(process_start "$$")" > "$recovery_dir/pid"

  if ! stale="$(python3 "$claim_recovery" claim-stale "$lock_dir" "${CHAIN_LOCK_STALE_SECONDS:-300}")"; then
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
  stale="$(python3 "$claim_recovery" claim-stale "$recovery_dir" "${CHAIN_LOCK_STALE_SECONDS:-300}")"
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
      printf '%s\t%s\n' "$$" "$(process_start "$$")" > "$lock_dir/pid"
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

write_marker() {
  local worktree="$1" owner_pid="$2" owner_start="$3" marker_dir marker_tmp

  marker_dir="$worktree/.git-loopy"
  marker_tmp="$marker_dir/.worktree-owner.$$"
  if ! mkdir -p "$marker_dir" ||
    ! printf '%s\t%s\n' "$owner_pid" "$owner_start" > "$marker_tmp" ||
    ! mv "$marker_tmp" "$marker_dir/worktree-owner"
  then
    rm -f "$marker_tmp"
    return 1
  fi
}

# Decide the fate of a pending worktree record: exit 0 and print
# "<worktree>\t<branch>" when the worktree still needs undoing, exit 1 when its
# transaction finished, exit 2 when the record or the ledger cannot be read. The
# three are distinct because only a finished transaction is safe to forget —
# dropping a record we could not read would discard the last thing naming its
# worktree — so anything unexpected here must land on 2 rather than on Python's
# own exit 1. What counts as finishing differs by producer and the record says
# which: a reservation finishes when its own id reaches the ledger, so no retry
# reusing every argument and no later rewrite of that row can be mistaken for it;
# a claimed worktree finishes when its marker lands, because a claim has no row.
unfinished_worktree() {
  python3 - "$1" "$ledger" <<'PY'
import json
import os
import sys

pending_path, ledger_path = sys.argv[1:]


def unreadable():
    raise SystemExit(2)


try:
    with open(pending_path, encoding="utf-8") as pending:
        record = json.load(pending)
    if not isinstance(record, dict):
        unreadable()
    worktree = record.get("worktree")
    branch = record.get("branch") or ""
    commit = record.get("commit")
    if not isinstance(worktree, str) or not worktree:
        unreadable()
    if not isinstance(branch, str):
        unreadable()

    if commit == "marker":
        if os.path.exists(os.path.join(worktree, ".git-loopy", "worktree-owner")):
            raise SystemExit(1)
    elif commit == "row":
        reservation_id = record.get("reservation_id")
        if not isinstance(reservation_id, str) or not reservation_id:
            unreadable()
        if os.path.exists(ledger_path):
            with open(ledger_path, encoding="utf-8") as ledger:
                for line in ledger:
                    if not line.strip():
                        continue
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        unreadable()
                    if row.get("reservation_id") == reservation_id:
                        raise SystemExit(1)
    else:
        unreadable()
except SystemExit:
    raise
except Exception:
    unreadable()

print(worktree + "\t" + branch)
PY
}

# Roll a half-finished worktree forward or back. The pending record names the
# worktree before it exists and survives a SIGKILL that the EXIT trap cannot.
# Every command that takes the ledger lock runs this first. A rollback that cannot
# finish keeps its record and fails rather than dropping it, because the record is
# the last thing naming the worktree it left. Callers that own recovery — reserve
# and recover — refuse to continue on that failure; the rest sweep opportunistically
# and carry on, because an unrelated directory git cannot remove must not stop a
# finished run from being bound or closed.
rollback_pending_worktree() {
  local pending_path="$1" record verdict pending_worktree pending_branch

  [ -f "$pending_path" ] || return 0
  if record="$(unfinished_worktree "$pending_path")"; then
    IFS=$'\t' read -r pending_worktree pending_branch <<< "$record"
    if ! remove_worktree "$pending_worktree"; then
      echo "error: could not remove unrecorded worktree: $pending_worktree" >&2
      return 1
    fi
    if [ -n "$pending_branch" ] &&
      git -C "$(repository_root)" rev-parse --verify --quiet "refs/heads/$pending_branch" >/dev/null
    then
      git -C "$(repository_root)" branch -D "$pending_branch" >/dev/null 2>&1 ||
        echo "error: could not delete branch of removed worktree: $pending_branch" >&2
    fi
  else
    verdict=$?
    if [ "$verdict" -ne 1 ]; then
      echo "error: unreadable pending worktree record: $pending_path" >&2
      return 1
    fi
  fi
  rm -f "$pending_path"
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

ledger_has_open_target() {
  python3 - "$ledger" "$1" <<'PY'
import json
import os
import sys

ledger, target = sys.argv[1:]
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
        if row.get("target") == target and not row.get("finish_time"):
            raise SystemExit(0)

raise SystemExit(1)
PY
}

concurrency_limit() {
  local limit="${CHAIN_MAX_CONCURRENCY:-10}"

  [[ "$limit" =~ ^[1-9][0-9]*$ ]] && [ "$limit" -le 10 ] || {
    echo "error: CHAIN_MAX_CONCURRENCY must be an integer from 1 through 10" >&2
    return 2
  }
  printf '%s\n' "$limit"
}

allowlisted_route() {
  case "$1" in
    /implement|/code-review|/research|/push|/resolving-merge-conflicts) return 0 ;;
    *) return 1 ;;
  esac
}

evaluate_and_record_target_guard() {
  local route="$1" target="$2" requested_depth="${3:-}"

  python3 - "$ledger" "$route" "$target" "$requested_depth" <<'PY'
import datetime
import json
import os
import sys
import tempfile

ledger_path, route, target, requested_depth = sys.argv[1:]
requested_depth = int(requested_depth) if requested_depth else 0
if not os.path.exists(ledger_path):
    print(json.dumps({
        "reason": None,
        "target": target,
        "next_chain_depth": max(1, requested_depth),
    }, separators=(",", ":")))
    raise SystemExit

try:
    with open(ledger_path, encoding="utf-8") as ledger:
        rows = [json.loads(line) for line in ledger if line.strip()]
except json.JSONDecodeError as error:
    print(f"error: invalid spawn ledger: {error}", file=sys.stderr)
    raise SystemExit(2)

bound_rows = [
    (index, row)
    for index, row in enumerate(rows)
    if row.get("target") == target and row.get("agent_id")
]
recorded_depth = max(
    (
        row.get("chain_depth", 0)
        for _, row in bound_rows
        if isinstance(row.get("chain_depth"), int)
    ),
    default=0,
)
next_chain_depth = max(recorded_depth + 1, requested_depth, 1)

if not bound_rows:
    print(json.dumps({
        "reason": None,
        "target": target,
        "next_chain_depth": next_chain_depth,
    }, separators=(",", ":")))
    raise SystemExit

halt_reason = None
for _, row in reversed(bound_rows):
    if isinstance(row.get("halt_reason"), str) and row["halt_reason"]:
        halt_reason = row["halt_reason"]
        break

if halt_reason is None and any(
    row.get("outcome") == "no-evidence" for _, row in bound_rows
):
    halt_reason = "no-evidence"
elif halt_reason is None:
    normalized_route = route.lstrip("/")
    repetitions = sum(
        row.get("route", "").lstrip("/") == normalized_route
        for _, row in bound_rows
        if isinstance(row.get("route"), str)
    )
    if repetitions >= 3:
        halt_reason = "route-repetition-limit"
    else:
        if next_chain_depth > 8:
            halt_reason = "chain-depth-limit"

if halt_reason is None:
    print(json.dumps({
        "reason": None,
        "target": target,
        "next_chain_depth": next_chain_depth,
    }, separators=(",", ":")))
    raise SystemExit

_, halt_row = bound_rows[-1]
if halt_row.get("halt_reason") != halt_reason:
    halted_at = datetime.datetime.now(datetime.timezone.utc).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z")
    halt_row["halt_reason"] = halt_reason
    halt_row["halted_at"] = halted_at
    descriptor, temporary_path = tempfile.mkstemp(
        dir=os.path.dirname(ledger_path) or ".",
        prefix=".subagents.",
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            for row in rows:
                output.write(json.dumps(row, separators=(",", ":")) + "\n")
        os.replace(temporary_path, ledger_path)
    except BaseException:
        os.unlink(temporary_path)
        raise

print(json.dumps({
    "reason": halt_reason,
    "target": target,
    "next_chain_depth": next_chain_depth,
}, separators=(",", ":")))
PY
}

plan() {
  local route="" target="" safety="" agent="" model="" effort="" context_tier="" worktree=""
  local fill_terminal="" ledger_set=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) [ -z "$route" ] || usage; route="${2:?missing value for --route}"; shift 2 ;;
      --target) [ -z "$target" ] || usage; target="${2:?missing value for --target}"; shift 2 ;;
      --safety) [ -z "$safety" ] || usage; safety="${2:?missing value for --safety}"; shift 2 ;;
      --agent) [ -z "$agent" ] || usage; agent="${2:?missing value for --agent}"; shift 2 ;;
      --model) [ -z "$model" ] || usage; model="${2:?missing value for --model}"; shift 2 ;;
      --effort) [ -z "$effort" ] || usage; effort="${2:?missing value for --effort}"; shift 2 ;;
      --context-tier)
        [ -z "$context_tier" ] || usage
        context_tier="${2:?missing value for --context-tier}"; shift 2 ;;
      --worktree) [ -z "$worktree" ] || usage; worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --no-ready) [ -z "$fill_terminal" ] || usage; fill_terminal="no-ready-action"; shift ;;
      --all-collide) [ -z "$fill_terminal" ] || usage; fill_terminal="all-candidates-collide"; shift ;;
      --ledger)
        [ "$ledger_set" -eq 0 ] || usage
        ledger="${2:?missing value for --ledger}"; ledger_set=1; shift 2 ;;
      *) usage ;;
    esac
  done

  if [ -n "$fill_terminal" ]; then
    [ -z "$route" ] && [ -z "$target" ] && [ -z "$safety" ] && [ -z "$agent" ] &&
      [ -z "$model" ] && [ -z "$effort" ] && [ -z "$context_tier" ] &&
      [ -z "$worktree" ] || usage
    printf '{"decision":"exhausted","reason":"%s"}\n' "$fill_terminal"
    return
  fi

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$safety" ] && [ -n "$agent" ] &&
    [ -n "$model" ] && [ -n "$effort" ] && [ -n "$context_tier" ] &&
    [ -n "$worktree" ] || usage

  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi

  recover --ledger "$ledger" \
    --stale-after-seconds "${CHAIN_RESERVATION_STALE_SECONDS:-300}" >/dev/null

  local worktree_held=0 collision_status max_concurrency guard="" route_allowed=0
  max_concurrency="$(concurrency_limit)" || return $?
  if allowlisted_route "$route"; then
    route_allowed=1
  fi
  if ledger_has_open_worktree "$worktree"; then
    worktree_held=1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  if [ "$safety" = "AFK-safe" ] && [ "$route_allowed" -eq 1 ]; then
    mkdir -p "$(dirname "$ledger")"
    lock_dir="$ledger.lock"
    acquire_lock
    rollback_pending_worktree "$ledger.pending" || true
    guard="$(evaluate_and_record_target_guard "$route" "$target")"
    release_lock
  fi

  python3 - "$ledger" "$route" "$target" "$safety" "$agent" "$model" "$effort" "$context_tier" "$worktree" "$worktree_held" "$max_concurrency" "$route_allowed" "$guard" <<'PY'
import json
import os
import sys

ledger, route, target, safety, agent, model, effort, context_tier, worktree, worktree_held, max_concurrency, route_allowed, guard = sys.argv[1:]
worktree = os.path.realpath(os.path.abspath(worktree))
worktree_held = worktree_held == "1"
max_concurrency = int(max_concurrency)
route_allowed = route_allowed == "1"
guard = json.loads(guard) if guard else None

if not route_allowed:
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
    open_reservations = 0
    if os.path.exists(ledger):
        with open(ledger, encoding="utf-8") as ledger_file:
            for raw_line in ledger_file:
                line = raw_line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if not row.get("finish_time"):
                    open_reservations += 1
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
    elif guard and guard["reason"]:
        decision = {
            "decision": "decline",
            "reason": "target-halted",
            "halt_reason": guard["reason"],
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
    elif open_reservations >= max_concurrency:
        decision = {
            "decision": "decline",
            "reason": "concurrency-limit",
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
            "worktree": worktree,
        }

print(json.dumps(decision, separators=(",", ":")))
PY
}

reserve() {
  local route="" target="" spawn_time="" worktree="" chain_depth="" parent_pid=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="${2:?missing value for --route}"; shift 2 ;;
      --target) target="${2:?missing value for --target}"; shift 2 ;;
      --spawn-time) spawn_time="${2:?missing value for --spawn-time}"; shift 2 ;;
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --chain-depth) chain_depth="${2:?missing value for --chain-depth}"; shift 2 ;;
      --parent-pid) parent_pid="${2:?missing value for --parent-pid}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$route" ] && [ -n "$target" ] && [ -n "$spawn_time" ] &&
    [ -n "$worktree" ] && [ -n "$chain_depth" ] && [ -n "$parent_pid" ] || usage
  [[ "$chain_depth" =~ ^[0-9]+$ ]] || {
    echo "error: --chain-depth must be a non-negative integer" >&2
    exit 2
  }
  local ledger_dir row reservation spawn_commit worktree_branch max_concurrency open_reservations
  local parent_start
  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi
  ledger_dir="$(dirname "$ledger")"
  lock_dir="$ledger.lock"
  spawn_commit="$(git rev-parse HEAD)"
  repo_root="$(repository_root)"
  worktree_branch="git-loopy/reservation-${$}-${RANDOM}"
  worktree="$(python3 -c 'import os; import sys; print(os.path.realpath(os.path.abspath(sys.argv[1])))' "$worktree")"
  [[ "$parent_pid" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: --parent-pid must be a process id" >&2
    exit 2
  }
  parent_start="$(process_start "$parent_pid")"
  [ -n "$parent_start" ] || {
    echo "error: reserving parent is not running: $parent_pid" >&2
    exit 2
  }
  mkdir -p "$ledger_dir"
  max_concurrency="$(concurrency_limit)" || return $?

  acquire_lock
  rollback_pending_worktree "$ledger.pending"

  local collision_status guard
  if ledger_has_open_worktree "$worktree"; then
    echo "error: worktree-in-flight: $worktree" >&2
    exit 1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  if ledger_has_open_target "$target"; then
    echo "error: target-in-flight: $target" >&2
    exit 1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  guard="$(evaluate_and_record_target_guard "$route" "$target" "$chain_depth")"
  if [ "$(python3 -c 'import json; import sys; print(json.load(sys.stdin)["reason"] or "")' <<< "$guard")" ]; then
    echo "error: target-halted: $(python3 -c 'import json; import sys; print(json.load(sys.stdin)["reason"])' <<< "$guard")" >&2
    exit 1
  fi
  chain_depth="$(python3 -c 'import json; import sys; print(json.load(sys.stdin)["next_chain_depth"])' <<< "$guard")"

  open_reservations="$(python3 - "$ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
if not os.path.exists(ledger_path):
    print(0)
    raise SystemExit

with open(ledger_path, encoding="utf-8") as ledger:
    print(sum(
        1
        for line in ledger
        if line.strip() and not json.loads(line).get("finish_time")
    ))
PY
)"
  if [ "$open_reservations" -ge "$max_concurrency" ]; then
    echo "error: concurrency-limit: $max_concurrency" >&2
    exit 1
  fi

  # One reservation, one transaction. The pending record holds the row this
  # reserve is about to commit and names its worktree before that worktree
  # exists, so a hard kill anywhere below is undone by whoever takes this lock
  # next; appending the row to the ledger commits it. Refuse a path that already
  # exists first: rollback tells what this transaction made only by what was
  # absent when it started.
  if [ -e "$worktree" ]; then
    echo "error: worktree path already exists: $worktree" >&2
    exit 1
  fi
  reservation="$(python3 - "$route" "$target" "$spawn_time" "$worktree" "$chain_depth" "$parent_pid" "$parent_start" "$worktree_branch" <<'PY'
import json
import sys
import uuid

(
    route, target, spawn_time, worktree, chain_depth, parent_pid, parent_start, branch
) = sys.argv[1:]
row = {
    "reservation_id": uuid.uuid4().hex,
    "route": route,
    "target": target,
    "spawn_time": spawn_time,
    "worktree": worktree,
    "chain_depth": int(chain_depth),
    "parent_pid": int(parent_pid),
    "parent_start": parent_start,
    "finish_time": "",
    "outcome": "",
}
print(json.dumps(row, separators=(",", ":")))
print(json.dumps({
    "worktree": worktree,
    "branch": branch,
    "commit": "row",
    "reservation_id": row["reservation_id"],
}, separators=(",", ":")))
PY
)"
  row="${reservation%%$'\n'*}"

  pending="$ledger.pending"
  printf '%s\n' "${reservation#*$'\n'}" > "$pending.$$"
  mv "$pending.$$" "$pending"

  if [ -n "${CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE:-}" ]; then
    sleep "$CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE"
  fi
  git -C "$repo_root" worktree add -b "$worktree_branch" "$worktree" "$spawn_commit" || exit 1
  write_marker "$worktree" "$parent_pid" "$parent_start" || exit 1

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"

  if [ -f "$ledger" ]; then
    cat "$ledger" > "$tmp"
  fi
  printf '%s\n' "$row" >> "$tmp"

  if [ -n "${CHAIN_RESERVE_PAUSE_BEFORE_COMMIT:-}" ]; then
    sleep "$CHAIN_RESERVE_PAUSE_BEFORE_COMMIT"
  fi
  mv "$tmp" "$ledger"
  tmp=""
  rm -f "$pending"
  pending=""
  release_lock
}

bind() {
  local session_id="" agent_id="" agent_type="" agent_name="" worktree=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session-id) session_id="${2:?missing value for --session-id}"; shift 2 ;;
      --agent-id) agent_id="${2:?missing value for --agent-id}"; shift 2 ;;
      --agent-type) agent_type="${2:?missing value for --agent-type}"; shift 2 ;;
      --agent-name) agent_name="${2:?missing value for --agent-name}"; shift 2 ;;
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$session_id" ] && [ -n "$agent_id" ] && [ -n "$agent_type" ] &&
    [ -n "$agent_name" ] && [ -n "$worktree" ] || usage

  local ledger_dir
  if [ -z "$ledger" ]; then
    ledger="$(repository_root)/.git-loopy/subagents.jsonl"
  fi
  ledger_dir="$(dirname "$ledger")"
  lock_dir="$ledger.lock"
  worktree="$(python3 -c 'import os; import sys; print(os.path.realpath(os.path.abspath(sys.argv[1])))' "$worktree")"
  mkdir -p "$ledger_dir"
  acquire_lock
  rollback_pending_worktree "$ledger.pending" || true

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  if ! python3 - "$ledger" "$tmp" "$worktree" "$session_id" "$agent_id" "$agent_type" "$agent_name" <<'PY'
import json
import os
import sys

ledger_path, output_path, worktree, session_id, agent_id, agent_type, agent_name = sys.argv[1:]
rows = []
if os.path.exists(ledger_path):
    with open(ledger_path, encoding="utf-8") as ledger:
        rows = [json.loads(line) for line in ledger if line.strip()]

reservations = [
    index
    for index, row in enumerate(rows)
    if (
        isinstance(row.get("worktree"), str)
        and os.path.realpath(os.path.abspath(row["worktree"])) == worktree
        and not row.get("finish_time")
        and not row.get("agent_id")
    )
]
if not reservations:
    print(f"error: reservation not found for worktree: {worktree}", file=sys.stderr)
    raise SystemExit(1)
if len(reservations) > 1:
    print(f"error: ambiguous reservation for worktree: {worktree}", file=sys.stderr)
    raise SystemExit(1)
if any(row.get("agent_id") == agent_id for row in rows):
    print(f"error: agent identity already bound: {agent_id}", file=sys.stderr)
    raise SystemExit(1)

row = rows[reservations[0]]
row["session_id"] = session_id
row["agent_id"] = agent_id
row["agent_type"] = agent_type
row["agent_name"] = agent_name

with open(output_path, "w", encoding="utf-8") as output:
    for row in rows:
        output.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
  then
    rm -f "$tmp"
    tmp=""
    release_lock
    return 1
  fi

  mv "$tmp" "$ledger"
  tmp=""
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
  rollback_pending_worktree "$ledger.pending" || true

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
# Required because `complete` reads them, and for no other reason. sessionId,
# agentId, agentType and agentName find the ledger row; cwd locates the
# repository and the worktree; timestamp closes the row. Everything else the
# runtime sends — transcriptPath, agentDisplayName, response, stopReason, and
# whatever a later release adds — is optional, because a field that is required
# and never read rejects real payloads and silences the whole chain (#41).
required_fields = (
    "sessionId",
    "timestamp",
    "cwd",
    "agentId",
    "agentType",
    "agentName",
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
    payload_worktree = os.path.realpath(os.path.abspath(payload["cwd"]))
    unbound_matches = [
        index
        for index, row in enumerate(rows)
        if (
            isinstance(row.get("worktree"), str)
            and os.path.realpath(os.path.abspath(row["worktree"])) == payload_worktree
            and not row.get("finish_time")
            and not row.get("agent_id")
        )
    ]
    if len(unbound_matches) == 1:
        print(json.dumps({
            "continue": False,
            "reason": "unbound-reservation",
            "worktree": payload_worktree,
        }, separators=(",", ":")))
        raise SystemExit(0)
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
finish_time = (
    finish_at.astimezone(datetime.timezone.utc)
    .isoformat(timespec="seconds")
    .replace("+00:00", "Z")
)
row["finish_time"] = finish_time
row["outcome"] = outcome
if outcome == "no-evidence":
    row["halt_reason"] = "no-evidence"
    row["halted_at"] = finish_time
elif isinstance(row.get("chain_depth"), int) and row["chain_depth"] >= 8:
    # Record the next-hop stop before agentStop reaches its own eight-block limit.
    row["halt_reason"] = "chain-depth-limit"
    row["halted_at"] = finish_time

with open(output_path, "w", encoding="utf-8") as output:
    for updated_row in rows:
        output.write(json.dumps(updated_row, separators=(",", ":")) + "\n")
with open(metadata_path, "w", encoding="utf-8") as metadata:
    metadata.write(worktree + "\n")

print(json.dumps({
    "continue": has_evidence and "halt_reason" not in row,
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

  [ -e "$ledger" ] || [ -e "$ledger.pending" ] || {
    printf '{"recovered":0,"targets":[]}\n'
    return
  }

  local ledger_dir result
  ledger_dir="$(dirname "$ledger")"
  mkdir -p "$ledger_dir"
  lock_dir="$ledger.lock"
  acquire_lock
  rollback_pending_worktree "$ledger.pending"

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  metadata="$tmp.worktrees"
  result="$(
    python3 -c '
import datetime
import json
import os
import subprocess
import sys

ledger_path, output_path, metadata_path, stale_after, now, claim_recovery = sys.argv[1:]

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
    if row.get("finish_time") or row.get("agent_id"):
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
    parent_pid = row.get("parent_pid")
    parent_start = row.get("parent_start")
    parent_is_gone = False
    if isinstance(parent_pid, int) and isinstance(parent_start, str) and parent_start:
        liveness = subprocess.run(
            [
                sys.executable,
                claim_recovery,
                "owner-gone",
                str(parent_pid),
                parent_start,
            ],
            capture_output=True,
            text=True,
        )
        parent_is_gone = liveness.returncode == 0 and liveness.stdout.strip() == "true"

    if parent_is_gone or (
        recovered_at - spawned_at
    ).total_seconds() >= stale_after_seconds:
        row["finish_time"] = (
            recovered_at.astimezone(datetime.timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z")
        )
        row["outcome"] = "reclaimed"
        row["reclaimed_at"] = row["finish_time"]
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
' "$ledger" "$tmp" "$metadata" "$stale_after" "$now" "$claim_recovery"
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

owner() {
  local worktree="" marker
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$worktree" ] || usage
  marker="$worktree/.git-loopy/worktree-owner"
  python3 - "$marker" "$claim_recovery" <<'PY'
import subprocess
import sys

marker, claim_recovery = sys.argv[1:]
try:
    pid_text, owner_start = open(marker, encoding="utf-8").read().rstrip("\n").split("\t", 1)
    pid = int(pid_text)
except (FileNotFoundError, ValueError):
    print('{"alive":false,"reason":"invalid-marker"}')
    raise SystemExit
if pid <= 0 or not owner_start.strip():
    print('{"alive":false,"reason":"invalid-marker"}')
    raise SystemExit
liveness = subprocess.run(
    [sys.executable, claim_recovery, "owner-gone", str(pid), owner_start],
    capture_output=True,
    text=True,
)
if liveness.returncode != 0:
    print('{"alive":false,"reason":"liveness-check-failed"}')
    raise SystemExit
print('{"alive":' + ("false" if liveness.stdout.strip() == "true" else "true") + '}')
PY
}

# The second producer of an ownership marker: a worktree an agent made for itself
# on a /next prompt, which never passes through reserve and would otherwise be
# indistinguishable from abandoned clutter. With --create-branch the worktree is
# made here rather than by the caller, so creating and marking it is one journaled
# transaction and no interruption can leave a worktree nothing vouches for.
claim() {
  local worktree="" owner_pid="" create_branch="" owner_start ledger_dir spawn_commit

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worktree) worktree="${2:?missing value for --worktree}"; shift 2 ;;
      --owner-pid) owner_pid="${2:?missing value for --owner-pid}"; shift 2 ;;
      --create-branch) create_branch="${2:?missing value for --create-branch}"; shift 2 ;;
      --ledger) ledger="${2:?missing value for --ledger}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$worktree" ] && [ -n "$owner_pid" ] || usage
  [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: --owner-pid must be a process id" >&2
    exit 2
  }
  owner_start="$(process_start "$owner_pid")"
  [ -n "$owner_start" ] || {
    echo "error: claiming owner is not running: $owner_pid" >&2
    exit 2
  }

  if [ -z "$create_branch" ]; then
    [ -d "$worktree" ] || {
      echo "error: worktree does not exist: $worktree" >&2
      exit 2
    }
    write_marker "$worktree" "$owner_pid" "$owner_start" || {
      echo "error: could not write ownership marker: $worktree" >&2
      exit 1
    }
    return
  fi

  repo_root="$(repository_root)"
  spawn_commit="$(git rev-parse HEAD)"
  worktree="$(python3 -c 'import os; import sys; print(os.path.realpath(os.path.abspath(sys.argv[1])))' "$worktree")"
  if [ -z "$ledger" ]; then
    ledger="$repo_root/.git-loopy/subagents.jsonl"
  fi
  ledger_dir="$(dirname "$ledger")"
  lock_dir="$ledger.lock"
  mkdir -p "$ledger_dir"
  acquire_lock
  rollback_pending_worktree "$ledger.pending"

  # Refuse a path or branch that already exists, before anything claims the right
  # to undo them. Rollback tells what this transaction made only by what was
  # absent when it started, so publishing over a collision would licence deleting
  # someone else's worktree or branch.
  if [ -e "$worktree" ]; then
    echo "error: worktree path already exists: $worktree" >&2
    exit 1
  fi
  if git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$create_branch" >/dev/null; then
    echo "error: branch already exists: $create_branch" >&2
    exit 1
  fi

  pending="$ledger.pending"
  python3 - "$worktree" "$create_branch" > "$pending.$$" <<'PY'
import json
import sys

worktree, branch = sys.argv[1:]
print(json.dumps({
    "worktree": worktree,
    "branch": branch,
    "commit": "marker",
}, separators=(",", ":")))
PY
  mv "$pending.$$" "$pending"

  git -C "$repo_root" worktree add -b "$create_branch" "$worktree" "$spawn_commit" || exit 1
  write_marker "$worktree" "$owner_pid" "$owner_start" || {
    echo "error: could not write ownership marker: $worktree" >&2
    exit 1
  }
  rm -f "$pending"
  pending=""
  release_lock
}

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  plan) plan "$@" ;;
  reserve) reserve "$@" ;;
  bind) bind "$@" ;;
  complete) complete "$@" ;;
  recover) recover "$@" ;;
  owner) owner "$@" ;;
  claim) claim "$@" ;;
  *) usage ;;
esac
