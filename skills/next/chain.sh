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
  chain.sh gate --pull-request NUMBER --ticket NUMBER [--repo OWNER/REPO]
  chain.sh reserve --route ROUTE --target TARGET --spawn-time TIMESTAMP \
    --worktree PATH --chain-depth N --parent-pid PID [--ledger PATH]
  chain.sh bind --worktree PATH --session-id ID --agent-id ID \
    --agent-type TYPE --agent-name NAME [--ledger PATH]
  chain.sh complete [--ledger PATH] < subagent-stop-payload.json
  chain.sh recover --stale-after-seconds N [--now TIMESTAMP] [--ledger PATH]

A PID-less ledger lock is recoverable after CHAIN_LOCK_STALE_SECONDS (default: 300).
ROUTE is a slash-command name and carries its leading slash. The allowlist is
/implement, /code-review, /research, /push, and /resolving-merge-conflicts; a bare
name such as "implement" is not a route and plan declines it as
route-not-allowlisted.
--parent-pid names the running process whose death orphans the reservation, which
is the session that will bind the run and never the shell that invokes this script.
Route repetition and chain depth count bound rows only. Reservations claim
capacity and a worktree, but do not represent a spawned hop.
The two --no-ready and --all-collide forms end a fan-out fill; they are mutually
exclusive, take no candidate, and record nothing.
`bind --agent-name` is recorded for readability only; `complete` matches a row on
session id, agent id and agent type. `bind --session-id` is the routing session
that launches the run, never the agent id that launch returns, because
`subagentStop` reports a run under the session that launched it.
EOF
  exit 2
}

ledger="${CHAIN_LEDGER:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claim_recovery="$script_dir/claim-recovery.py"
target_identity="$script_dir/target-identity.py"
review_clean_record="$script_dir/../../scripts/review-clean-record.py"
tracker_failure="$script_dir/tracker_failure.py"
tracker_bin="${CHAIN_TRACKER_BIN:-gh}"
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
  local main_worktree common_dir git_dir current_worktree
  local root_anchor recorded_root recorded_common_dir

  main_worktree="$(
    git worktree list --porcelain |
      awk '/^worktree / { sub(/^worktree /, ""); print; exit }'
  )"

  # When the main worktree's .git points to an out-of-tree gitdir, Git cannot
  # name that worktree and reports the common gitdir itself. Record the main
  # working tree once so linked worktrees resolve the same repository ledger.
  common_dir="$(git rev-parse --git-common-dir)"
  common_dir="$(cd "$common_dir" 2>/dev/null && pwd -P)" || common_dir=""
  if [ -n "$main_worktree" ] && [ -n "$common_dir" ] &&
    [ "$(cd "$main_worktree" 2>/dev/null && pwd -P)" = "$common_dir" ]; then
    git_dir="$(git rev-parse --git-dir)"
    git_dir="$(cd "$git_dir" 2>/dev/null && pwd -P)" || git_dir=""
    current_worktree="$(git rev-parse --show-toplevel)"
    current_worktree="$(cd "$current_worktree" 2>/dev/null && pwd -P)" || current_worktree=""
    [ -n "$git_dir" ] && [ -n "$current_worktree" ] || {
      echo "error: could not resolve repository metadata for the working tree" >&2
      return 1
    }

    root_anchor="$common_dir/git-loopy-worktree-root"
    if [ ! -e "$root_anchor" ] && [ ! -L "$root_anchor" ]; then
      [ "$git_dir" = "$common_dir" ] || {
        echo "error: repository root is not recorded for this separate-git-dir repository" >&2
        return 1
      }
      if ! ln -s "$current_worktree" "$root_anchor" 2>/dev/null &&
        [ ! -L "$root_anchor" ]; then
        echo "error: could not record repository root: $root_anchor" >&2
        return 1
      fi
    fi

    if [ ! -L "$root_anchor" ] ||
      ! recorded_root="$(readlink "$root_anchor")" ||
      [ -z "$recorded_root" ]; then
      echo "error: could not read repository root: $root_anchor" >&2
      return 1
    fi
    if ! recorded_common_dir="$(
      git -C "$recorded_root" rev-parse --git-common-dir |
        while IFS= read -r dir; do
          cd "$recorded_root"
          cd "$dir"
          pwd -P
        done
    )"; then
      echo "error: recorded repository root is unavailable: $recorded_root" >&2
      return 1
    fi
    [ "$recorded_common_dir" = "$common_dir" ] || {
      echo "error: recorded repository root belongs to a different repository: $recorded_root" >&2
      return 1
    }
    printf '%s\n' "$recorded_root"
    return
  fi

  if [ -n "$main_worktree" ]; then
    printf '%s\n' "$main_worktree"
    return
  fi
  echo "error: could not resolve repository root" >&2
  return 1
}

resolve_target_context() {
  python3 "$target_identity" "$ledger" "$1"
}

target_context_field() {
  python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]] or "")' "$1" <<< "$2"
}

process_start() {
  TZ=UTC ps -o lstart= -p "$1" | xargs
}

target_resolution() {
  local target="$1" workdir="$2"

  python3 - "$target" "$workdir" "$tracker_failure" "$tracker_bin" <<'PY'
import json
import os
import sys

target, workdir, tracker_failure, tracker_bin = sys.argv[1:]
sys.path.insert(0, os.path.dirname(tracker_failure))
from tracker_failure import run_tracker

tracker_output, error, _, failure_kind = run_tracker(
    [tracker_bin, "issue", "view", target, "--json", "number"],
    workdir,
)
if error is not None:
    print(json.dumps({
        "resolved": False,
        "failure_kind": failure_kind,
        "error": error,
    }, separators=(",", ":")))
    raise SystemExit(1)

try:
    response = json.loads(tracker_output)
except json.JSONDecodeError as error:
    print(json.dumps({
        "resolved": False,
        "failure_kind": "transient",
        "error": f"tracker returned invalid target data: {error}",
    }, separators=(",", ":")))
    raise SystemExit(1)

number = response.get("number") if isinstance(response, dict) else None
if isinstance(number, bool) or not isinstance(number, int) or number <= 0:
    print(json.dumps({
        "resolved": False,
        "failure_kind": "transient",
        "error": "tracker returned target data without a positive integer number",
    }, separators=(",", ":")))
    raise SystemExit(1)

print('{"resolved":true}')
PY
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
    git -C "$worktree" worktree remove "$worktree"
  else
    ledger_root="$(repository_root)"
    git -C "$ledger_root" worktree prune
  fi
}

worktree_can_be_removed() {
  local worktree="$1" status

  [ -e "$worktree" ] || return 0
  if ! status="$(git -C "$worktree" status --porcelain=v1 --untracked-files=all)"; then
    echo "error: could not inspect worktree; retaining it: $worktree" >&2
    return 1
  fi
  if [ -n "$status" ]; then
    echo "warning: worktree has uncommitted changes and was retained: $worktree" >&2
    return 1
  fi
  return 0
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

ledger, target_context = sys.argv[1:]
equivalent_targets = set(json.loads(target_context)["equivalent_targets"])
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
        if row.get("target") in equivalent_targets and not row.get("finish_time"):
            raise SystemExit(0)

raise SystemExit(1)
PY
}

mark_record_failed() {
  local worktree="$1"

  tmp="$(mktemp "$(dirname "$ledger")/.subagents.XXXXXX")"
  python3 - "$ledger" "$tmp" "$worktree" <<'PY'
import datetime
import json
import os
import sys

ledger_path, output_path, worktree = sys.argv[1:]
worktree = os.path.realpath(os.path.abspath(worktree))
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

matches = [
    row
    for row in rows
    if (
        isinstance(row.get("worktree"), str)
        and os.path.realpath(os.path.abspath(row["worktree"])) == worktree
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
  local route="$1" target_context="$2" requested_depth="${3:-}"

  python3 - "$ledger" "$route" "$target_context" "$requested_depth" <<'PY'
import datetime
import json
import os
import sys
import tempfile

ledger_path, route, target_context, requested_depth = sys.argv[1:]
target_context = json.loads(target_context)
target = target_context["canonical_target"]
equivalent_targets = set(target_context["equivalent_targets"])
requested_depth = int(requested_depth) if requested_depth else 0
if not os.path.exists(ledger_path):
    print(json.dumps({
        "failed": False,
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

target_rows = [
    (index, row)
    for index, row in enumerate(rows)
    if row.get("target") in equivalent_targets
]
target_failed = any(
    row.get("outcome") in {"failed", "no-evidence"}
    for _, row in target_rows
)
bound_rows = [
    (index, row)
    for index, row in target_rows
    if row.get("agent_id")
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
        "failed": target_failed,
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
        "failed": target_failed,
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
    "failed": target_failed,
    "reason": halt_reason,
    "target": target,
    "next_chain_depth": next_chain_depth,
}, separators=(",", ":")))
PY
}

plan() {
  local route="" target="" safety="" agent="" model="" effort="" context_tier="" worktree=""
  local fill_terminal="" ledger_set=0 target_state="" target_resolved=0

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

  repo_root="$(repository_root)"
  if [ -z "$ledger" ]; then
    ledger="$repo_root/.git-loopy/subagents.jsonl"
  fi

  recover --ledger "$ledger" \
    --stale-after-seconds "${CHAIN_RESERVATION_STALE_SECONDS:-300}" >/dev/null

  local worktree_held=0 collision_status max_concurrency guard="" route_allowed=0
  local target_context=""
  max_concurrency="$(concurrency_limit)" || return $?
  if allowlisted_route "$route"; then
    route_allowed=1
  fi
  if [ "$safety" = "AFK-safe" ] && [ "$route_allowed" -eq 1 ]; then
    target_context="$(resolve_target_context "$target")" || return $?
    if [ -z "$(target_context_field error "$target_context")" ] &&
      target_state="$(target_resolution \
        "$(target_context_field tracker_target "$target_context")" \
        "$repo_root")"
    then
      target_resolved=1
    fi
  fi
  if ledger_has_open_worktree "$worktree"; then
    worktree_held=1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  if [ "$safety" = "AFK-safe" ] && [ "$route_allowed" -eq 1 ] &&
    [ "$target_resolved" -eq 1 ]
  then
    mkdir -p "$(dirname "$ledger")"
    lock_dir="$ledger.lock"
    acquire_lock
    guard="$(evaluate_and_record_target_guard "$route" "$target_context")"
    release_lock
  fi

  python3 - "$ledger" "$route" "$target" "$safety" "$agent" "$model" "$effort" "$context_tier" "$worktree" "$worktree_held" "$max_concurrency" "$route_allowed" "$guard" "$target_state" "$target_context" <<'PY'
import json
import os
import sys

ledger, route, target, safety, agent, model, effort, context_tier, worktree, worktree_held, max_concurrency, route_allowed, guard, target_state, target_context = sys.argv[1:]
worktree = os.path.realpath(os.path.abspath(worktree))
worktree_held = worktree_held == "1"
max_concurrency = int(max_concurrency)
route_allowed = route_allowed == "1"
guard = json.loads(guard) if guard else None
target_state = json.loads(target_state) if target_state else None
target_context = json.loads(target_context) if target_context else None

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
elif target_context and target_context["error"]:
    decision = {
        "decision": "decline",
        "reason": target_context["error"],
        "route": route,
        "target": target,
        "error": target_context["detail"],
    }
elif target_state is None:
    decision = {
        "decision": "decline",
        "reason": "tracker-unavailable",
        "route": route,
        "target": target,
        "error": "tracker target resolution failed without a result",
    }
elif target_state and not target_state["resolved"]:
    decision = {
        "decision": "decline",
        "reason": (
            "target-unresolvable"
            if target_state["failure_kind"] == "permanent"
            else "tracker-unavailable"
        ),
        "route": route,
        "target": target,
        "error": target_state["error"],
    }
else:
    equivalent_targets = set(target_context["equivalent_targets"])
    in_flight = False
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
                if row.get("target") in equivalent_targets and not row.get("finish_time"):
                    in_flight = True
                    break

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
    elif guard and guard["failed"]:
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

gate() {
  local pull_request="" ticket="" repo=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pull-request|--pr)
        [ -z "$pull_request" ] || usage
        pull_request="${2:?missing value for $1}"; shift 2 ;;
      --ticket|--target)
        [ -z "$ticket" ] || usage
        ticket="${2:?missing value for $1}"; shift 2 ;;
      --repo)
        [ -z "$repo" ] || usage
        repo="${2:?missing value for --repo}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [ -n "$pull_request" ] && [ -n "$ticket" ] || usage
  [[ "$pull_request" =~ ^[1-9][0-9]*$ ]] && [[ "$ticket" =~ ^[1-9][0-9]*$ ]] || usage

  local -a gh_args=(pr view "$pull_request")
  [ -z "$repo" ] || gh_args+=(--repo "$repo")
  gh_args+=(--json mergeable,isDraft,headRefOid,statusCheckRollup)

  local evidence
  if ! evidence="$(gh "${gh_args[@]}")"; then
    printf '{"decision":"refuse","pull_request":"%s","reason":"pull-request-evidence-unavailable"}\n' \
      "$pull_request"
    return 2
  fi

  local comments ticket_available=1
  local -a issue_args=(issue view "$ticket")
  [ -z "$repo" ] || issue_args+=(--repo "$repo")
  issue_args+=(--json comments)
  if ! comments="$(gh "${issue_args[@]}")"; then
    comments=""
    ticket_available=0
  fi

  python3 - "$pull_request" "$evidence" "$comments" "$ticket_available" \
    "$review_clean_record" <<'PY'
import json
import subprocess
import sys

pull_request, raw, raw_comments, ticket_available, review_clean_record = sys.argv[1:]


def refuse(reason, status, *, head=None, missing=None):
    decision = {
        "decision": "refuse",
        "pull_request": pull_request,
    }
    if head is not None:
        decision["headRefOid"] = head
    if missing:
        decision["missing"] = missing
    decision["reason"] = reason
    print(json.dumps(decision, separators=(",", ":")))
    raise SystemExit(status)


def match_review_record(body, head):
    return subprocess.run(
        [sys.executable, review_clean_record, "match", head],
        input=body,
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode


try:
    view = json.loads(raw)
except json.JSONDecodeError:
    refuse("pull-request-evidence-invalid", 2)
if not isinstance(view, dict):
    refuse("pull-request-evidence-invalid", 2)

head_sha = view.get("headRefOid")
if (
    not isinstance(head_sha, str)
    or not head_sha
    or match_review_record("", head_sha) not in {0, 1}
):
    refuse("pull-request-evidence-invalid", 2)

if ticket_available != "1":
    refuse("ticket-evidence-unavailable", 2, head=head_sha)

try:
    ticket_view = json.loads(raw_comments)
except json.JSONDecodeError:
    refuse("ticket-evidence-invalid", 2, head=head_sha)
if not isinstance(ticket_view, dict):
    refuse("ticket-evidence-invalid", 2, head=head_sha)

comments = ticket_view.get("comments")
if not isinstance(comments, list) or any(
    not isinstance(comment, dict) or not isinstance(comment.get("body"), str)
    for comment in comments
):
    refuse("ticket-evidence-invalid", 2, head=head_sha)

missing = []
if view.get("isDraft") is not False:
    missing.append("pull-request-not-draft")
if view.get("mergeable") != "MERGEABLE":
    missing.append("pull-request-mergeable")

review_clean = False
for comment in comments:
    match_status = match_review_record(comment["body"], head_sha)
    if match_status == 0:
        review_clean = True
        break
    if match_status != 1:
        refuse("review-clean-matcher-unavailable", 2, head=head_sha)
if not review_clean:
    missing.append("review-clean-evidence-comment")

red_checks = []
pending_checks = []
if (
    "statusCheckRollup" not in view
    or view["statusCheckRollup"] is None
    or view["statusCheckRollup"] == []
):
    missing.append("checks-present")
elif not isinstance(view["statusCheckRollup"], list):
    missing.append("checks-valid")
else:
    checks_valid = True
    for check in view["statusCheckRollup"]:
        if not isinstance(check, dict) or any(
            key in check
            and check[key] is not None
            and not isinstance(check[key], str)
            for key in ("state", "status", "conclusion")
        ):
            checks_valid = False
            break

        state = (check.get("state") or "").upper()
        status = (check.get("status") or "").upper()
        conclusion = (check.get("conclusion") or "").upper()
        if not state and not status and not conclusion:
            checks_valid = False
            break

        name = check.get("name") or check.get("context") or "unknown"
        if (
            state in {"FAILURE", "ERROR", "CANCELLED", "TIMED_OUT"}
            or conclusion in {"FAILURE", "ERROR", "CANCELLED", "TIMED_OUT"}
        ):
            red_checks.append(name)
        elif state in {"PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED"} or status in {
            "PENDING",
            "QUEUED",
            "IN_PROGRESS",
            "REQUESTED",
            "WAITING",
            "EXPECTED",
        }:
            pending_checks.append(name)
        elif conclusion != "SUCCESS" and state != "SUCCESS":
            red_checks.append(name)

    if not checks_valid:
        missing.append("checks-valid")
    else:
        if red_checks:
            missing.append("checks-green")
        if pending_checks:
            missing.append("checks-complete")

decision = {
    "decision": "allow" if not missing else "refuse",
    "pull_request": pull_request,
    "headRefOid": head_sha,
}
if missing:
    decision["missing"] = missing
    decision["reason"] = ",".join(missing)
else:
    decision["reason"] = "merge-evidence-complete"
print(json.dumps(decision, separators=(",", ":")))
raise SystemExit(0 if not missing else 1)
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
  local ledger_dir row spawn_commit worktree_branch max_concurrency open_reservations
  local parent_start target_state target_error target_failure_kind target_context canonical_target
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
  target_context="$(resolve_target_context "$target")" || return $?
  target_error="$(target_context_field error "$target_context")"
  if [ -n "$target_error" ]; then
    echo "error: $target_error: $target: $(target_context_field detail "$target_context")" >&2
    exit 1
  fi
  canonical_target="$(target_context_field canonical_target "$target_context")"
  if ! target_state="$(target_resolution "$(target_context_field tracker_target "$target_context")" "$repo_root")"; then
    if [ -z "$target_state" ]; then
      echo "error: tracker-unavailable: $target: tracker target resolution failed without a result" >&2
      exit 1
    fi
    target_error="$(python3 -c '
import json
import sys

print(json.load(sys.stdin)["error"])
' <<< "$target_state")"
    target_failure_kind="$(python3 -c '
import json
import sys

print(json.load(sys.stdin)["failure_kind"])
' <<< "$target_state")"
    if [ "$target_failure_kind" = "permanent" ]; then
      echo "error: target-unresolvable: $target: $target_error" >&2
    else
      echo "error: tracker-unavailable: $target: $target_error" >&2
    fi
    exit 1
  fi
  mkdir -p "$ledger_dir"
  max_concurrency="$(concurrency_limit)" || return $?

  acquire_lock

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

  if ledger_has_open_target "$target_context"; then
    echo "error: target-in-flight: $target" >&2
    exit 1
  else
    collision_status=$?
    if [ "$collision_status" -ne 1 ]; then
      return "$collision_status"
    fi
  fi

  guard="$(evaluate_and_record_target_guard "$route" "$target_context" "$chain_depth")"
  if [ "$(python3 -c 'import json; import sys; print(json.load(sys.stdin)["reason"] or "")' <<< "$guard")" ]; then
    echo "error: target-halted: $(python3 -c 'import json; import sys; print(json.load(sys.stdin)["reason"])' <<< "$guard")" >&2
    exit 1
  fi
  if [ "$(python3 -c 'import json; import sys; print("true" if json.load(sys.stdin)["failed"] else "false")' <<< "$guard")" = "true" ]; then
    echo "error: target-failed: $target" >&2
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

  tmp="$(mktemp "$ledger_dir/.subagents.XXXXXX")"
  row="$(python3 - "$route" "$canonical_target" "$spawn_time" "$worktree" "$chain_depth" "$parent_pid" "$parent_start" <<'PY'
import json
import sys

route, target, spawn_time, worktree, chain_depth, parent_pid, parent_start = sys.argv[1:]
row = {
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
PY
)"

  if [ -f "$ledger" ]; then
    cat "$ledger" > "$tmp"
  fi
  printf '%s\n' "$row" >> "$tmp"

  if [ -n "${CHAIN_RESERVE_PAUSE_BEFORE_COMMIT:-}" ]; then
    sleep "$CHAIN_RESERVE_PAUSE_BEFORE_COMMIT"
  fi
  mv "$tmp" "$ledger"
  tmp=""
  if [ -n "${CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE:-}" ]; then
    sleep "$CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE"
  fi
  if ! git -C "$repo_root" worktree add -b "$worktree_branch" "$worktree" "$spawn_commit"; then
    mark_record_failed "$worktree"
    exit 1
  fi
  created_worktree=1
  created_worktree_path="$worktree"
  created_worktree=0
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

  local ledger_dir result exit_status retained_worktree worktree
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

ledger_path, output_path, metadata_path, target_identity, tracker_failure, tracker_bin = sys.argv[1:]
sys.path.insert(0, os.path.dirname(tracker_failure))
from tracker_failure import run_tracker
# Required because `complete` reads them, and for no other reason. sessionId,
# agentId and agentType find the ledger row; cwd locates the repository and the
# worktree; timestamp closes the row. Everything else the runtime sends —
# transcriptPath, agentName, agentDisplayName, response, stopReason, and
# whatever a later release adds — is optional, because a field that is required
# and never read rejects real payloads and silences the whole chain (#41).
required_fields = (
    "sessionId",
    "timestamp",
    "cwd",
    "agentId",
    "agentType",
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

# agentId identifies the run on its own; sessionId and agentType stop a payload
# from another session or another agent type reaching this row. The bound
# agent_name is deliberately not read: the runtime sets agentName to the agent
# type and sends no field carrying the descriptive name a caller binds, so
# matching on it left every descriptively named row open forever (#67).
matches = [
    index
    for index, row in enumerate(rows)
    if (
        row.get("session_id") == payload["sessionId"]
        and row.get("agent_id") == agent_id
        and row.get("agent_type") == payload["agentType"]
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

def resolve_tracker_target():
    # A target that cannot be resolved is a tracker failure like any other: the
    # caller closes the row instead of leaving it open with its worktree on disk.
    try:
        resolution = subprocess.run(
            [sys.executable, target_identity, ledger_path, target],
            capture_output=True,
            cwd=payload["cwd"],
            encoding="utf-8",
            timeout=30,
        )
    except (OSError, UnicodeDecodeError, subprocess.TimeoutExpired) as error:
        return None, f"could not resolve target: {error}"
    if resolution.returncode:
        message = resolution.stderr.strip().splitlines()
        return None, (
            message[-1]
            if message
            else f"target resolver exited with status {resolution.returncode}"
        )
    try:
        canonical = json.loads(resolution.stdout)
    except json.JSONDecodeError as error:
        return None, f"target resolver returned invalid data: {error}"
    if not isinstance(canonical, dict):
        return None, "target resolver returned invalid data"
    if canonical.get("error"):
        failure = canonical["error"]
        detail = canonical.get("detail")
        return None, f"{failure}: {detail}" if detail else str(failure)
    tracker_target = canonical.get("tracker_target")
    if not isinstance(tracker_target, str) or not tracker_target:
        return None, "target resolver returned no tracker target"
    return tracker_target, None


tracker_target, resolution_error = resolve_tracker_target()
if resolution_error is not None:
    tracker_output, tracker_error, exit_status, tracker_failure_kind = (
        "",
        resolution_error,
        1,
        "transient",
    )
else:
    tracker_output, tracker_error, exit_status, tracker_failure_kind = run_tracker(
        [tracker_bin, "issue", "view", tracker_target, "--json", "comments"],
        payload["cwd"],
    )
if tracker_error is not None:
    comments = []
else:
    try:
        tracker_response = json.loads(tracker_output)
    except json.JSONDecodeError as error:
        tracker_error = f"tracker returned invalid comment data: {error}"
        tracker_failure_kind = "transient"
        exit_status = 2
        comments = []
    else:
        comments = (
            tracker_response.get("comments")
            if isinstance(tracker_response, dict)
            else None
        )
        if not isinstance(comments, list):
            tracker_error = "tracker returned comments in an invalid format"
            tracker_failure_kind = "transient"
            exit_status = 2
            comments = []

has_evidence = False
if tracker_error is None:
    comment_times = []
    for index, comment in enumerate(comments):
        if not isinstance(comment, dict):
            tracker_error = f"tracker returned invalid comment data at index {index}"
            break
        created_at = comment.get("createdAt")
        if not isinstance(created_at, str):
            tracker_error = (
                f"tracker returned comment data without createdAt at index {index}"
            )
            break
        try:
            comment_at = datetime.datetime.fromisoformat(
                created_at.replace("Z", "+00:00")
            )
        except ValueError as error:
            tracker_error = (
                f"tracker returned invalid comment timestamp at index {index}: {error}"
            )
            break
        if comment_at.tzinfo is None:
            tracker_error = (
                f"tracker returned comment timestamp without timezone at index {index}"
            )
            break
        comment_times.append(comment_at)

    if tracker_error is not None:
        tracker_failure_kind = "transient"
        exit_status = 2
    else:
        has_evidence = any(
            spawn_at <= comment_at <= finish_at
            for comment_at in comment_times
        )

outcome = (
    "tracker-failed"
    if tracker_error is not None
    else "published" if has_evidence else "no-evidence"
)
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
elif outcome == "tracker-failed":
    row["tracker_error"] = tracker_error
    row["tracker_failure_kind"] = tracker_failure_kind
    if tracker_failure_kind == "permanent":
        row["halt_reason"] = "tracker-failed"
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

result = {
    "continue": has_evidence and "halt_reason" not in row,
    "outcome": outcome,
    "target": target,
}
if tracker_error is not None:
    result["failure_kind"] = tracker_failure_kind
    result["error"] = tracker_error
    result["exit_status"] = exit_status
print(json.dumps(result, separators=(",", ":")))
if tracker_error is not None:
    print(
        f"error: tracker lookup failed for {target}: {tracker_error}",
        file=sys.stderr,
    )
' "$ledger" "$tmp" "$metadata" "$target_identity" "$tracker_failure" "$tracker_bin"
  )"
  exit_status="$(python3 -c '
import json
import sys

print(json.load(sys.stdin).get("exit_status", 0))
' <<< "$result")"

  if python3 -c '
import json
import sys

raise SystemExit(0 if json.load(sys.stdin).get("reason") is None else 1)
' <<< "$result"; then
  retained_worktree=""
  worktree="$(cat "$metadata")"
  if worktree_can_be_removed "$worktree"; then
    if ! remove_worktree "$worktree"; then
      echo "warning: could not remove clean worktree; retaining it: $worktree" >&2
      retained_worktree="$worktree"
    fi
  else
    retained_worktree="$worktree"
  fi
  if [ -n "$retained_worktree" ]; then
    result="$(python3 - "$result" "$retained_worktree" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
result["retained_worktree"] = sys.argv[2]
print(json.dumps(result, separators=(",", ":")))
PY
)"
  fi
  mv "$tmp" "$ledger"
  else
    rm -f "$tmp"
  fi
  tmp=""
  rm -f "$metadata"
  metadata=""
  release_lock
  printf '%s\n' "$result"
  return "$exit_status"
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

  [ -e "$ledger" ] || {
    printf '{"recovered":0,"targets":[]}\n'
    return
  }

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
    if row.get("finish_time"):
        continue
    is_bound = bool(row.get("agent_id"))
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

    timed_out = (
        recovered_at - spawned_at
    ).total_seconds() >= stale_after_seconds
    if parent_is_gone or (not is_bound and timed_out):
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
  local -a retained_worktrees=()
  while IFS= read -r worktree; do
    if worktree_can_be_removed "$worktree"; then
      if ! remove_worktree "$worktree"; then
        echo "warning: could not remove clean worktree; retaining it: $worktree" >&2
        retained_worktrees+=("$worktree")
      fi
    else
      retained_worktrees+=("$worktree")
    fi
  done < "$metadata"
  mv "$tmp" "$ledger"
  tmp=""
  rm -f "$metadata"
  metadata=""
  release_lock
  if [ "${#retained_worktrees[@]}" -gt 0 ]; then
    result="$(python3 - "$result" "${retained_worktrees[@]}" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
result["retained_worktrees"] = sys.argv[2:]
print(json.dumps(result, separators=(",", ":")))
PY
)"
  fi
  printf '%s\n' "$result"
}

[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
  plan) plan "$@" ;;
  gate) gate "$@" ;;
  reserve) reserve "$@" ;;
  bind) bind "$@" ;;
  complete) complete "$@" ;;
  recover) recover "$@" ;;
  *) usage ;;
esac
