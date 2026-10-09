#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHAIN="$REPO/skills/next/chain.sh"
RECORD="$REPO/scripts/review-clean-record.py"
tmp_dir="$(python3 -c 'import os; import sys; print(os.path.realpath(sys.argv[1]))' "$(mktemp -d)")"
fail=0

err() {
  echo "error: $1" >&2
  fail=1
}

worktree_count() {
  git -C "$1" worktree list --porcelain |
    awk '/^worktree / { count += 1 } END { print count + 0 }'
}

cleanup() {
  cd "$REPO"
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

parent_worktrees_before="$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /')"
git -C "$tmp_dir" init --quiet
git -C "$tmp_dir" -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty -m initial
ledger="$tmp_dir/.git-loopy/subagents.jsonl"
export CHAIN_RESERVATION_STALE_SECONDS=999999999

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  if [ "${CHAIN_TARGET_LOOKUP:-}" = "rate-limited" ]; then
    echo "API rate limit exceeded" >&2
    exit 1
  fi
  if [ "${CHAIN_TARGET_LOOKUP:-}" = "unavailable" ]; then
    echo "gh unavailable" >&2
    exit 127
  fi
  if [ "${CHAIN_TARGET_LOOKUP:-}" = "non-utf8" ]; then
    printf '{"data":"\xff"}\n'
    exit
  fi

  query=""
  for argument in "$@"; do
    case "$argument" in
      query=*) query="${argument#query=}" ;;
    esac
  done
  if [ -n "${CHAIN_GH_LOG:-}" ]; then
    printf '%s\n' "$query" >> "$CHAIN_GH_LOG"
  fi

  python3 - "$query" <<'PY'
import json
import re
import sys

repository = {}
for alias, number_text in re.findall(
    r"(target\d+):issueOrPullRequest\(number:(\d+)\)",
    sys.argv[1],
):
    number = int(number_text)
    if number in {15, 16}:
        repository[alias] = {"__typename": "Issue", "number": number}
    elif number == 60:
        repository[alias] = {
            "__typename": "PullRequest",
            "closingIssuesReferences": {"nodes": [{"number": 15}]},
        }
    elif number == 7:
        repository[alias] = {
            "__typename": "PullRequest",
            "closingIssuesReferences": {"nodes": []},
        }
    else:
        repository[alias] = None

print(json.dumps({"data": {"repository": repository}}, separators=(",", ":")))
PY
  exit
fi

if [ "$1" != "issue" ] || [ "$2" != "view" ] || [ "$4" != "--json" ]; then
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi
if [ -n "${CHAIN_EXPECT_ISSUE:-}" ] && [ "$3" != "$CHAIN_EXPECT_ISSUE" ]; then
  echo "expected issue $CHAIN_EXPECT_ISSUE, got $3" >&2
  exit 1
fi

case "${CHAIN_TRACKER_MODE:-resolved}" in
  resolved) ;;
  unresolvable)
    echo "GraphQL: Could not resolve to an issue or pull request with the number of $3. (repository.issue)" >&2
    exit 1
    ;;
  not-found)
    echo "GraphQL: Could not resolve to an issue or pull request with the number of $3. (repository.issue)" >&2
    exit 1
    ;;
  ambiguous-404)
    echo "HTTP 404: resource not found" >&2
    exit 1
    ;;
  malformed-target)
    echo "malformed target: $3" >&2
    exit 1
    ;;
  rate-limit)
    echo "HTTP 403: API rate limit exceeded for user." >&2
    exit 1
    ;;
  http-429)
    echo "HTTP 429: too many requests" >&2
    exit 1
    ;;
  server-failure)
    echo "HTTP 503: service unavailable" >&2
    exit 1
    ;;
  transport-failure)
    echo "tracker transport failed for $3" >&2
    exit 23
    ;;
  hang)
    exec sleep 120
    ;;
  timeout)
    echo "request timed out while resolving $3" >&2
    exit 1
    ;;
  *)
    echo "unexpected tracker mode: $CHAIN_TRACKER_MODE" >&2
    exit 1
    ;;
esac

case "$5" in
  number)
    case "${CHAIN_TARGET_RESPONSE:-valid}" in
      valid) printf '{"number":1}\n' ;;
      string-number) printf '{"number":"1"}\n' ;;
      malformed-json) printf '{not-json}\n' ;;
      non-utf8) printf '{"number":1,"title":"\xff"}\n' ;;
      *)
        echo "unexpected target response: $CHAIN_TARGET_RESPONSE" >&2
        exit 1
        ;;
    esac
    ;;
  comments)
    case "${CHAIN_COMMENT_RESPONSE:-valid}" in
      valid)
        if [ "${CHAIN_EVIDENCE:-}" = "published" ]; then
          printf '%s\n' '{"comments":[{"createdAt":"2026-08-22T00:10:00Z","body":"Evidence comment"}]}'
        else
          printf '%s\n' '{"comments":[]}'
        fi
        ;;
      invalid-entry) printf '%s\n' '{"comments":["not-an-object"]}' ;;
      invalid-timestamp) printf '%s\n' '{"comments":[{"createdAt":"not-a-time"}]}' ;;
      non-utf8) printf '{"comments":[{"createdAt":"2026-08-22T00:10:00Z","body":"\xff"}]}\n' ;;
      *)
        echo "unexpected comment response: $CHAIN_COMMENT_RESPONSE" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
SH
chmod +x "$fake_bin/gh"
export PATH="$fake_bin:$PATH"

PYTHONPATH="$REPO/skills/next" python3 - <<'PY'
import subprocess
from unittest.mock import patch

from tracker_failure import classify_tracker_failure, run_tracker

for message in (
    "HTTP 403: API rate limit exceeded for user.",
    "HTTP 429: too many requests",
    "HTTP 503: service unavailable",
    "HTTP 404: resource not found",
    "dial tcp: lookup github.com: no such host",
    "request timed out",
):
    assert classify_tracker_failure(message) == "transient", message

for message in (
    "GraphQL: Could not resolve to an issue or pull request with the number of 99999. (repository.issue)",
    "malformed target: issue-?",
):
    assert classify_tracker_failure(message) == "permanent", message

_, error, exit_status, failure_kind = run_tracker(
    ["/definitely-missing-git-loopy-tracker"],
    "/",
)
assert error and error.startswith("could not run tracker:")
assert exit_status == 1
assert failure_kind == "transient"

with patch(
    "tracker_failure.subprocess.run",
    side_effect=subprocess.TimeoutExpired("gh", 30),
) as tracker_run:
    _, error, exit_status, failure_kind = run_tracker(["gh"], "/")
assert error == "tracker timed out after 30 seconds"
assert exit_status == 124
assert failure_kind == "transient"
assert tracker_run.call_args.kwargs["timeout"] == 30
PY

timezone_stable_start="$(TZ=UTC ps -o lstart= -p "$$" | xargs)"
if [ "$(TZ=America/Denver python3 "$REPO/skills/next/claim-recovery.py" owner-gone "$$" "$timezone_stable_start")" != "false" ]; then
  err "claim recovery treated a live parent as gone after a timezone change"
fi

claim_ps_bin="$tmp_dir/claim-ps-bin"
mkdir -p "$claim_ps_bin"
cat > "$claim_ps_bin/ps" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$CLAIM_PS_MODE" in
  failure) exit 1 ;;
  empty) exit 0 ;;
  malformed) echo "not a valid process start" ;;
  impossible) echo "Foo Bar 99 99:99:99 9999" ;;
  inconsistent) echo "Tue Jan 01 00:00:00 2001" ;;
  *)
    echo "unexpected ps mode: $CLAIM_PS_MODE" >&2
    exit 2
    ;;
esac
SH
chmod +x "$claim_ps_bin/ps"

for claim_ps_mode in failure empty malformed impossible inconsistent; do
  if [ "$(
    PATH="$claim_ps_bin:$PATH" CLAIM_PS_MODE="$claim_ps_mode" \
      python3 "$REPO/skills/next/claim-recovery.py" \
        owner-gone "$$" "$timezone_stable_start"
  )" != "false" ]; then
    err "claim recovery treated a live parent as gone after a $claim_ps_mode ps result"
  fi
done

if [ "$(
  python3 "$REPO/skills/next/claim-recovery.py" \
    owner-gone "$$" "not a recorded process start"
)" != "false" ]; then
  err "claim recovery treated a malformed recorded parent identity as pid reuse"
fi

if [ "$(
  python3 "$REPO/skills/next/claim-recovery.py" \
    owner-gone "$$" "Tue Jan 01 00:00:00 2001"
)" != "false" ]; then
  err "claim recovery treated an inconsistent recorded parent identity as pid reuse"
fi

# The routing agent owns the background `task` call between these two commands.
# This exercises chain.sh's durable CLI seam: reserve happens before launch and
# bind accepts the runtime identity the launch returns.
reserve_and_bind() {
  local route="" target="" session_id="" agent_id="" agent_type="" agent_name=""
  local spawn_time="" worktree="" chain_depth="" ledger_path=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --route) route="$2"; shift 2 ;;
      --target) target="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --agent-id) agent_id="$2"; shift 2 ;;
      --agent-type) agent_type="$2"; shift 2 ;;
      --agent-name) agent_name="$2"; shift 2 ;;
      --spawn-time) spawn_time="$2"; shift 2 ;;
      --worktree) worktree="$2"; shift 2 ;;
      --chain-depth) chain_depth="$2"; shift 2 ;;
      --ledger) ledger_path="$2"; shift 2 ;;
      *) err "reserve_and_bind received unexpected argument: $1"; return 2 ;;
    esac
  done

  local -a ledger_args=()
  [ -z "$ledger_path" ] || ledger_args=(--ledger "$ledger_path")
  "$CHAIN" reserve --parent-pid "$$" "${ledger_args[@]}" \
    --route "$route" \
    --target "$target" \
    --spawn-time "$spawn_time" \
    --worktree "$worktree" \
    --chain-depth "$chain_depth"
  "$CHAIN" bind "${ledger_args[@]}" \
    --worktree "$worktree" \
    --session-id "$session_id" \
    --agent-id "$agent_id" \
    --agent-type "$agent_type" \
    --agent-name "$agent_name"
}

if [ -e "$ledger" ]; then
  err "ledger exists before the first record"
fi

unresolvable_reserve_ledger="$tmp_dir/.git-loopy/unresolvable-reserve.jsonl"
unresolvable_reserve_worktree="$tmp_dir/worktree-unresolvable-reserve"
unresolvable_reserve_error="$tmp_dir/unresolvable-reserve.err"
if (
  cd "$tmp_dir"
  CHAIN_TRACKER_MODE=unresolvable "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$unresolvable_reserve_ledger" \
    --route implement \
    --target issue-unresolvable-reserve \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$unresolvable_reserve_worktree" \
    --chain-depth 1 \
    2>"$unresolvable_reserve_error"
)
then
  err "reserve accepted an unresolvable target"
fi
if ! grep -q \
  "target-unresolvable: issue-unresolvable-reserve: GraphQL: Could not resolve to an issue or pull request with the number of issue-unresolvable-reserve. (repository.issue)" \
  "$unresolvable_reserve_error"
then
  err "reserve did not report the rejected target and cause"
fi
if [ -e "$unresolvable_reserve_ledger" ]; then
  err "reserve wrote a ledger row for an unresolvable target"
fi
if [ -e "$unresolvable_reserve_worktree" ]; then
  err "reserve created a worktree for an unresolvable target"
fi

rate_limit_reserve_ledger="$tmp_dir/.git-loopy/rate-limit-reserve.jsonl"
rate_limit_reserve_worktree="$tmp_dir/worktree-rate-limit-reserve"
rate_limit_reserve_error="$tmp_dir/rate-limit-reserve.err"
if (
  cd "$tmp_dir"
  CHAIN_TRACKER_MODE=rate-limit "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$rate_limit_reserve_ledger" \
    --route implement \
    --target issue-rate-limit-reserve \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$rate_limit_reserve_worktree" \
    --chain-depth 1 \
    2>"$rate_limit_reserve_error"
)
then
  err "reserve accepted a target while the tracker was unavailable"
fi
if ! grep -q \
  "tracker-unavailable: issue-rate-limit-reserve: HTTP 403: API rate limit exceeded for user." \
  "$rate_limit_reserve_error"
then
  err "reserve misclassified a rate limit as an unresolvable target"
fi
if [ -e "$rate_limit_reserve_ledger" ]; then
  err "reserve wrote a ledger row while the tracker was unavailable"
fi
if [ -e "$rate_limit_reserve_worktree" ]; then
  err "reserve created a worktree while the tracker was unavailable"
fi

missing_tracker_reserve_ledger="$tmp_dir/.git-loopy/missing-tracker-reserve.jsonl"
missing_tracker_reserve_worktree="$tmp_dir/worktree-missing-tracker-reserve"
missing_tracker_reserve_error="$tmp_dir/missing-tracker-reserve.err"
if (
  cd "$tmp_dir"
  CHAIN_TRACKER_BIN=/definitely-missing-git-loopy-tracker \
    "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$missing_tracker_reserve_ledger" \
    --route implement \
    --target issue-missing-tracker-reserve \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$missing_tracker_reserve_worktree" \
    --chain-depth 1 \
    2>"$missing_tracker_reserve_error"
)
then
  err "reserve accepted a target when the tracker executable was missing"
fi
if ! grep -q \
  "tracker-unavailable: issue-missing-tracker-reserve: could not run tracker:" \
  "$missing_tracker_reserve_error"
then
  err "reserve did not classify a missing tracker executable as transient"
fi
if [ -e "$missing_tracker_reserve_ledger" ]; then
  err "reserve wrote a ledger row when the tracker executable was missing"
fi
if [ -e "$missing_tracker_reserve_worktree" ]; then
  err "reserve created a worktree when the tracker executable was missing"
fi

malformed_target_reserve_ledger="$tmp_dir/.git-loopy/malformed-target-reserve.jsonl"
malformed_target_reserve_worktree="$tmp_dir/worktree-malformed-target-reserve"
malformed_target_reserve_error="$tmp_dir/malformed-target-reserve.err"
if (
  cd "$tmp_dir"
  CHAIN_TARGET_RESPONSE=string-number "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$malformed_target_reserve_ledger" \
    --route implement \
    --target issue-malformed-target-reserve \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$malformed_target_reserve_worktree" \
    --chain-depth 1 \
    2>"$malformed_target_reserve_error"
)
then
  err "reserve accepted malformed successful target data"
fi
if ! grep -q \
  "tracker-unavailable: issue-malformed-target-reserve: tracker returned target data without a positive integer number" \
  "$malformed_target_reserve_error"
then
  err "reserve did not classify malformed successful target data as transient"
fi
if [ -e "$malformed_target_reserve_ledger" ]; then
  err "reserve wrote a ledger row for malformed successful target data"
fi
if [ -e "$malformed_target_reserve_worktree" ]; then
  err "reserve created a worktree for malformed successful target data"
fi

non_utf8_reserve_ledger="$tmp_dir/.git-loopy/non-utf8-reserve.jsonl"
non_utf8_reserve_worktree="$tmp_dir/worktree-non-utf8-reserve"
non_utf8_reserve_error="$tmp_dir/non-utf8-reserve.err"
if (
  cd "$tmp_dir"
  CHAIN_TARGET_RESPONSE=non-utf8 "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$non_utf8_reserve_ledger" \
    --route implement \
    --target issue-non-utf8-reserve \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$non_utf8_reserve_worktree" \
    --chain-depth 1 \
    2>"$non_utf8_reserve_error"
)
then
  err "reserve accepted non-UTF-8 tracker output"
fi
if ! grep -q \
  "tracker-unavailable: issue-non-utf8-reserve: tracker output was not valid UTF-8" \
  "$non_utf8_reserve_error"
then
  err "reserve did not report non-UTF-8 tracker output as a transient failure"
fi
if [ -e "$non_utf8_reserve_ledger" ] || [ -e "$non_utf8_reserve_worktree" ]; then
  err "reserve consumed a ledger row or worktree for non-UTF-8 tracker output"
fi

(
  cd "$tmp_dir"
  "$CHAIN" reserve --parent-pid "$$" \
  --route implement \
  --target issue-4 \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-1" \
  --chain-depth 1
)

cd "$tmp_dir"

if [ ! -f "$ledger" ]; then
  err "reserve did not create the ledger"
else
  python3 - "$ledger" "$$" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]
assert len(rows) == 1
assert {
    key: rows[0][key]
    for key in ("route", "target", "spawn_time", "worktree", "chain_depth", "finish_time", "outcome")
} == {
    "route": "implement",
    "target": "issue-4",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": sys.argv[1].replace("/.git-loopy/subagents.jsonl", "/worktree-1"),
    "chain_depth": 1,
    "finish_time": "",
    "outcome": "",
}
assert rows[0]["parent_pid"] == int(sys.argv[2])
assert isinstance(rows[0]["parent_start"], str) and rows[0]["parent_start"]
PY
fi

if [ ! -d "$tmp_dir/worktree-1/.git" ] && [ ! -f "$tmp_dir/worktree-1/.git" ]; then
  err "reserve did not create the worktree before the agent existed"
fi
if [ "$(git -C "$tmp_dir/worktree-1" rev-parse HEAD)" != "$(git -C "$tmp_dir" rev-parse HEAD)" ]; then
  err "reserve did not create the worktree at the spawning commit"
fi
if [[ "$(git -C "$tmp_dir/worktree-1" branch --show-current)" != git-loopy/reservation-* ]]; then
  err "reserve did not create a branch for the reserved worktree"
fi
if [ ! -f "$tmp_dir/worktree-1/.git-loopy/worktree-owner" ]; then
  err "reserve did not create a worktree ownership marker"
else
  python3 - "$tmp_dir/worktree-1/.git-loopy/worktree-owner" <<'PY' || exit 1
import subprocess
import sys
import os

pid_text, start_time = open(sys.argv[1], encoding="utf-8").read().rstrip("\n").split("\t", 1)
assert int(pid_text) > 0
assert int(pid_text) == os.getppid()
assert start_time
assert " ".join(
    subprocess.run(
        ["ps", "-o", "lstart=", "-p", pid_text],
        capture_output=True,
        text=True,
        check=True,
        env={**os.environ, "TZ": "UTC"},
    ).stdout.split()
) == start_time
PY
fi

if [ "$("$CHAIN" owner --worktree "$tmp_dir/worktree-1")" != '{"alive":true}' ]; then
  err "owner did not read a live owner from the marker reserve wrote"
fi

# The second producer: a worktree an agent makes for itself on a /next prompt.
claim_ledger="$tmp_dir/.git-loopy/claim.jsonl"
prompt_worktree="$tmp_dir/worktree-prompt-made"
"$CHAIN" claim --ledger "$claim_ledger" --worktree "$prompt_worktree" \
  --create-branch prompt-made --owner-pid "$$"
if [ ! -d "$prompt_worktree/.git" ] && [ ! -f "$prompt_worktree/.git" ]; then
  err "claim --create-branch did not create the worktree"
fi
if [ ! -f "$prompt_worktree/.git-loopy/worktree-owner" ]; then
  err "claim --create-branch did not mark the worktree it made"
elif [ "$(cat "$prompt_worktree/.git-loopy/worktree-owner")" != "$(cat "$tmp_dir/worktree-1/.git-loopy/worktree-owner")" ]; then
  err "claim and reserve wrote different markers for the same owner"
fi
if [ "$("$CHAIN" owner --worktree "$prompt_worktree")" != '{"alive":true}' ]; then
  err "owner did not read a live owner from a claimed worktree"
fi
if [ -e "$claim_ledger.pending" ] || [ -e "$claim_ledger.lock" ]; then
  err "claim --create-branch left its pending worktree record or lock behind"
fi
if "$CHAIN" claim --ledger "$claim_ledger" --worktree "$prompt_worktree" \
  --create-branch prompt-made-again --owner-pid "$$" 2>/dev/null
then
  err "claim --create-branch overwrote an existing worktree"
fi
if [ ! -f "$prompt_worktree/.git-loopy/worktree-owner" ]; then
  err "a failed claim --create-branch destroyed the worktree already there"
fi
if [ -e "$claim_ledger.pending" ]; then
  err "a failed claim --create-branch left its pending worktree record behind"
fi

# A collision must be refused before anything claims the right to undo it: an
# unmarked worktree and a pre-existing branch both belong to somebody else.
bystander_worktree="$tmp_dir/worktree-bystander"
git -C "$tmp_dir" worktree add --quiet -b bystander "$bystander_worktree" >/dev/null
if "$CHAIN" claim --ledger "$claim_ledger" --worktree "$bystander_worktree" \
  --create-branch bystander-new --owner-pid "$$" 2>/dev/null
then
  err "claim --create-branch took over an unmarked worktree"
fi
if [ ! -d "$bystander_worktree" ]; then
  err "a failed claim --create-branch destroyed an unmarked worktree it did not make"
fi
if "$CHAIN" claim --ledger "$claim_ledger" --worktree "$tmp_dir/worktree-branch-taken" \
  --create-branch bystander --owner-pid "$$" 2>/dev/null
then
  err "claim --create-branch reused a branch that already existed"
fi
if ! git -C "$tmp_dir" rev-parse --verify --quiet bystander >/dev/null; then
  err "a failed claim --create-branch deleted a branch it did not make"
fi
if [ -e "$claim_ledger.pending" ]; then
  err "a refused claim --create-branch left its pending worktree record behind"
fi
git -C "$tmp_dir" worktree remove --force "$bystander_worktree"
git -C "$tmp_dir" branch -D bystander >/dev/null

# Claims on different ledgers share a path and a branch, so one must lose cleanly
# without rolling back the worktree the winner is still marking.
race_worktree="$tmp_dir/worktree-race"
race_before_worktree="$tmp_dir/race-before-worktree"
race_before_marker="$tmp_dir/race-before-marker"
touch "$race_before_worktree" "$race_before_marker"
CHAIN_CLAIM_PAUSE_BEFORE_WORKTREE="$race_before_worktree" \
  "$CHAIN" claim --ledger "$tmp_dir/race-b.jsonl" --worktree "$race_worktree" \
  --create-branch race-branch --owner-pid "$$" >"$tmp_dir/race-b.log" 2>&1 &
race_b=$!
for _ in $(seq 1 500); do
  [ -f "$race_before_worktree.ready" ] && break
  sleep 0.01
done
if [ ! -f "$race_before_worktree.ready" ]; then
  err "race fixture did not pause the first claim after its precondition checks"
fi
CHAIN_CLAIM_PAUSE_BEFORE_MARKER="$race_before_marker" \
  "$CHAIN" claim --ledger "$tmp_dir/race-a.jsonl" --worktree "$race_worktree" \
  --create-branch race-branch --owner-pid "$$" >"$tmp_dir/race-a.log" 2>&1 &
race_a=$!
# With the repository lock, a cannot add until b finishes. Without it, a adds
# while b is paused; b then loses its add and rolls a back before its marker.
for _ in $(seq 1 500); do
  [ -f "$race_before_marker.ready" ] && break
  sleep 0.01
done
race_wins=0
rm -f "$race_before_worktree"
wait "$race_b" && race_wins=$((race_wins + 1))
rm -f "$race_before_marker"
wait "$race_a" && race_wins=$((race_wins + 1))
if [ "$race_wins" -ne 1 ]; then
  err "exactly one claim on a shared path and branch should win, got $race_wins"
fi
if [ ! -f "$race_worktree/.git-loopy/worktree-owner" ] ||
  [ ! -f "$race_worktree/.git" ] ||
  ! git -C "$tmp_dir" worktree list --porcelain | grep -qxF "worktree $race_worktree"
then
  err "a losing claim on another ledger destroyed the winner's worktree"
fi
if [ -e "$tmp_dir/race-a.jsonl.pending" ] || [ -e "$tmp_dir/race-b.jsonl.pending" ] ||
  [ -e "$tmp_dir/.git-loopy/worktree.lock" ]
then
  err "racing claims left a pending worktree record or lock behind"
fi
if [ -f "$race_worktree/.git" ]; then
  git -C "$tmp_dir" worktree remove --force "$race_worktree"
fi
if git -C "$tmp_dir" rev-parse --verify --quiet race-branch >/dev/null; then
  git -C "$tmp_dir" branch -D race-branch >/dev/null
fi

# Interrupt after selecting the repository lock, before acquiring it: cleanup
# must release the ledger lock but leave another claimer's repository lock alone.
signal_repo_lock="$tmp_dir/.git-loopy/worktree.lock"
mkdir "$signal_repo_lock"
printf '%s\t%s\n' "$$" "$timezone_stable_start" > "$signal_repo_lock/pid"
cp "$signal_repo_lock/pid" "$tmp_dir/held-repository-lock-pid"
cat > "$tmp_dir/claim-signal-env" <<'ENV'
set -T
trap 'if [ "${repository_lock_dir:-${lock_dir:-}}" = "$signal_repo_lock" ]; then trap - DEBUG; kill -"$signal_kind" "$$"; fi' DEBUG
ENV
for signal_kind in TERM INT; do
  signal_status=0
  signal_repo_lock="$signal_repo_lock" signal_kind="$signal_kind" \
    BASH_ENV="$tmp_dir/claim-signal-env" bash "$CHAIN" claim \
    --ledger "$tmp_dir/signal.jsonl" --worktree "$tmp_dir/worktree-signal" \
    --create-branch signal --owner-pid "$$" || signal_status=$?
  if [ "$signal_status" -ne 130 ]; then
    err "claim did not stop on $signal_kind before acquiring the repository lock"
  fi
  if ! cmp -s "$tmp_dir/held-repository-lock-pid" "$signal_repo_lock/pid"; then
    err "claim interrupted by $signal_kind removed another claimer's repository lock"
  fi
  if [ -e "$tmp_dir/signal.jsonl.lock" ]; then
    err "claim interrupted by $signal_kind left its ledger lock behind"
  fi
done
rm -f "$signal_repo_lock/pid"
rmdir "$signal_repo_lock"

# The new worktree starts from the caller's HEAD, not the main checkout's.
caller_worktree="$tmp_dir/worktree-caller"
git -C "$tmp_dir" worktree add --quiet -b caller-base "$caller_worktree" >/dev/null
git -C "$caller_worktree" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m "ahead of the main checkout"
caller_head="$(git -C "$caller_worktree" rev-parse HEAD)"
(cd "$caller_worktree" && "$CHAIN" claim --ledger "$claim_ledger" \
  --worktree "$tmp_dir/worktree-from-caller" --create-branch from-caller --owner-pid "$$")
if [ "$(git -C "$tmp_dir/worktree-from-caller" rev-parse HEAD)" != "$caller_head" ]; then
  err "claim --create-branch based the new worktree on the wrong commit"
fi
git -C "$tmp_dir" worktree remove --force "$tmp_dir/worktree-from-caller"
git -C "$tmp_dir" branch -D from-caller >/dev/null
git -C "$tmp_dir" worktree remove --force "$caller_worktree"
git -C "$tmp_dir" branch -D caller-base >/dev/null

# An interrupted claim leaves an unmarked worktree; the marker is its commit, so
# recovery must undo it exactly as it undoes an uncommitted reservation.
unmarked_worktree="$tmp_dir/worktree-claim-crash"
git -C "$tmp_dir" worktree add --quiet -b claim-crash "$unmarked_worktree" >/dev/null
python3 - "$unmarked_worktree" > "$claim_ledger.pending" <<'PY'
import json
import sys

print(json.dumps({
    "worktree": sys.argv[1],
    "branch": "claim-crash",
    "commit": "marker",
}, separators=(",", ":")))
PY
"$CHAIN" recover --ledger "$claim_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T00:00:00Z >/dev/null
if [ -e "$unmarked_worktree" ]; then
  err "recovery kept the unmarked worktree of an interrupted claim"
fi
if git -C "$tmp_dir" rev-parse --verify --quiet claim-crash >/dev/null; then
  err "rolling back an interrupted claim left its branch behind"
fi
printf '{"worktree":"%s","branch":"prompt-made","commit":"marker"}\n' "$prompt_worktree" \
  > "$claim_ledger.pending"
"$CHAIN" recover --ledger "$claim_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T00:00:00Z >/dev/null
if [ ! -f "$prompt_worktree/.git-loopy/worktree-owner" ]; then
  err "recovery rolled back a claim whose marker had already landed"
fi
if [ -e "$claim_ledger.pending" ]; then
  err "recovery left the pending record of a committed claim behind"
fi

# A bystander that won the race between the guard and the creation is not this
# transaction's to remove: the proof of ownership is the branch, not the path.
race_worktree="$tmp_dir/worktree-race-loser"
git -C "$tmp_dir" worktree add --quiet -b race-winner "$race_worktree" >/dev/null
printf '{"worktree":"%s","branch":"race-loser","commit":"marker"}\n' "$race_worktree" \
  > "$claim_ledger.pending"
if "$CHAIN" recover --ledger "$claim_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T00:00:00Z >/dev/null 2>&1
then
  err "recovery reported success after refusing to remove a bystander worktree"
fi
if [ ! -d "$race_worktree" ]; then
  err "rollback removed a worktree created by somebody else at its recorded path"
fi
if ! git -C "$tmp_dir" rev-parse --verify --quiet race-winner >/dev/null; then
  err "rollback deleted the branch of a worktree it did not create"
fi
if ! git -C "$tmp_dir" worktree list --porcelain | grep -qxF "worktree $race_worktree"; then
  err "rollback unregistered a worktree it did not create"
fi
if [ ! -f "$claim_ledger.pending" ]; then
  err "rollback dropped the record of a worktree it refused to remove"
fi
rm -f "$claim_ledger.pending"
git -C "$tmp_dir" worktree remove --force "$race_worktree"
git -C "$tmp_dir" branch -D race-winner >/dev/null

if "$CHAIN" claim --ledger "$claim_ledger" --worktree "$tmp_dir/worktree-absent" --owner-pid "$$" 2>/dev/null; then
  err "claim marked a worktree that does not exist"
fi
if "$CHAIN" claim --worktree "$prompt_worktree" --owner-pid 999999999 2>/dev/null; then
  err "claim marked a worktree for an owner that is not running"
fi
git -C "$tmp_dir" worktree remove --force "$prompt_worktree"
git -C "$tmp_dir" branch -D prompt-made >/dev/null
rm -f "$claim_ledger" "$claim_ledger.pending"

"$CHAIN" bind \
  --ledger "$ledger" \
  --worktree "$tmp_dir/worktree-1" \
  --session-id session-1 \
  --agent-id agent-1 \
  --agent-type implement-agent \
  --agent-name implement-agent

if ! python3 - "$ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

assert rows[0]["session_id"] == "session-1"
assert rows[0]["agent_id"] == "agent-1"
assert rows[0]["agent_type"] == "implement-agent"
assert rows[0]["agent_name"] == "implement-agent"
PY
then
  err "bind did not attach the runtime identity to the reservation"
fi

missing_session_ledger="$tmp_dir/.git-loopy/missing-session-subagents.jsonl"
if (
  cd "$tmp_dir"
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$missing_session_ledger" \
    --route code-review \
    --target issue-missing-session \
    --spawn-time 2026-08-22T00:02:00Z \
    --worktree "$tmp_dir" \
    --chain-depth 1 \
    --in-place \
    2>/dev/null
)
then
  err "in-place reserve accepted a missing deterministic session"
fi
if [ -e "$missing_session_ledger" ]; then
  err "in-place reserve wrote a row without a deterministic session"
fi

in_place_ledger="$tmp_dir/.git-loopy/in-place-subagents.jsonl"
worktree_count_before_in_place="$(
  worktree_count "$tmp_dir"
)"
(
  cd "$tmp_dir"
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$in_place_ledger" \
    --route code-review \
    --target issue-serial-hop \
    --spawn-time 2026-08-22T00:02:00Z \
    --worktree "$tmp_dir" \
    --chain-depth 1 \
    --session-id session-serial-hop \
    --in-place
)
if ! python3 - "$in_place_ledger" "$$" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

# The reserving parent's identity and the reservation id are recorded on every reservation; their values vary by run.
assert len(rows) == 1
assert rows[0].pop("parent_pid") == int(sys.argv[2])
assert rows[0].pop("parent_start")
assert rows[0].pop("reservation_id")
assert rows == [{
    "route": "code-review",
    "target": "issue-serial-hop",
    "spawn_time": "2026-08-22T00:02:00Z",
    "worktree": sys.argv[1].replace("/.git-loopy/in-place-subagents.jsonl", ""),
    "chain_depth": 1,
    "finish_time": "",
    "outcome": "",
    "session_id": "session-serial-hop",
    "in_place": True,
}]
PY
then
  err "in-place reserve did not persist the deterministic session before spawn"
fi
if [ "$(worktree_count "$tmp_dir")" -ne "$worktree_count_before_in_place" ]; then
  err "in-place reserve created a linked worktree"
fi
cp "$in_place_ledger" "$in_place_ledger.before-mismatched-bind"
if "$CHAIN" bind \
  --ledger "$in_place_ledger" \
  --worktree "$tmp_dir" \
  --session-id session-wrong \
  --agent-id agent-serial-hop \
  --agent-type code-review-agent \
  --agent-name code-review-agent \
  2>/dev/null
then
  err "bind accepted a session identity different from the reservation"
fi
if ! cmp -s "$in_place_ledger.before-mismatched-bind" "$in_place_ledger"; then
  err "mismatched session binding modified the reservation"
fi
"$CHAIN" bind \
  --ledger "$in_place_ledger" \
  --worktree "$tmp_dir" \
  --session-id session-serial-hop \
  --agent-id agent-serial-hop \
  --agent-type code-review-agent \
  --agent-name code-review-agent

reserve_and_bind \
  --ledger "$ledger" \
  --route code-review \
  --target issue-4-review \
  --session-id session-2 \
  --agent-id agent-2 \
  --agent-type code-review-agent \
  --agent-name code-review-agent \
  --spawn-time 2026-08-22T00:01:00Z \
  --worktree "$tmp_dir/worktree-2" \
  --chain-depth 2

if [ "$(wc -l < "$ledger" | tr -d ' ')" -ne 2 ]; then
  err "reserve and bind did not append a second row"
fi

CHAIN_RESERVE_PAUSE_BEFORE_COMMIT=1 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$ledger" \
  --route push \
  --target issue-interrupted \
  --spawn-time 2026-08-22T00:02:00Z \
  --worktree "$tmp_dir/worktree-3" \
  --chain-depth 3 &
record_pid=$!
for _ in $(seq 1 100); do
  if grep -q worktree-3 "$tmp_dir/.git-loopy"/.subagents.* 2>/dev/null; then
    break
  fi
  sleep 0.01
done
kill -TERM "$record_pid" 2>/dev/null || true
wait "$record_pid" 2>/dev/null || true

if [ "$(wc -l < "$ledger" | tr -d ' ')" -ne 2 ]; then
  err "interrupted append left a partial row"
fi
if grep -q interrupted "$ledger"; then
  err "interrupted append committed an incomplete record"
fi

duplicate_worktree="$tmp_dir/worktree-duplicate-identity"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$ledger" \
  --route research \
  --target issue-duplicate-identity \
  --spawn-time 2026-08-22T00:03:00Z \
  --worktree "$duplicate_worktree" \
  --chain-depth 1
cp "$ledger" "$ledger.before-duplicate-bind"
if "$CHAIN" bind \
  --ledger "$ledger" \
  --worktree "$duplicate_worktree" \
  --session-id session-duplicate \
  --agent-id agent-1 \
  --agent-type research-agent \
  --agent-name research-agent \
  2>/dev/null
then
  err "bind accepted an agent identity that was already bound"
fi
if ! cmp -s "$ledger.before-duplicate-bind" "$ledger"; then
  err "duplicate agent binding modified the ledger"
fi

cp "$ledger" "$ledger.before-duplicate-target"
if "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$ledger" \
  --route code-review \
  --target issue-4 \
  --spawn-time 2026-08-22T00:04:00Z \
  --worktree "$tmp_dir/worktree-duplicate-target" \
  --chain-depth 2 \
  2>/dev/null
then
  err "reserve accepted a target that was already in flight"
fi
if ! cmp -s "$ledger.before-duplicate-target" "$ledger"; then
  err "duplicate target reservation modified the ledger"
fi

cp "$ledger" "$ledger.before-missing-bind"
missing_bind_error="$tmp_dir/missing-bind.err"
if "$CHAIN" bind \
  --ledger "$ledger" \
  --worktree "$tmp_dir/worktree-missing-reservation" \
  --session-id session-missing \
  --agent-id agent-missing \
  --agent-type research-agent \
  --agent-name research-agent \
  2>"$missing_bind_error"
then
  err "bind accepted a missing reservation"
fi
if ! grep -q "reservation not found for worktree" "$missing_bind_error"; then
  err "bind did not report the missing reservation"
fi
if ! cmp -s "$ledger.before-missing-bind" "$ledger"; then
  err "missing reservation binding modified the ledger"
fi

plan_ledger="$tmp_dir/.git-loopy/plan-subagents.jsonl"
plan() {
  "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route "$1" \
    --target "$2" \
    --safety "$3" \
    --agent "$4" \
    --model "$5" \
    --effort "$6" \
    --context-tier "$7" \
    --worktree "$8"
}

assert_plan() {
  local case_name="$1" output="$2" expected="$3"

  if ! python3 - "$output" "$expected" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == json.loads(sys.argv[2])
PY
  then
    err "$case_name decision did not match"
  fi
}

exhausted_ledger="$tmp_dir/.git-loopy/exhausted-subagents.jsonl"
exhausted_output="$("$CHAIN" plan --ledger "$exhausted_ledger" --no-ready)"
assert_plan "no ready action" "$exhausted_output" \
  '{"decision":"exhausted","reason":"no-ready-action"}'
if [ -e "$exhausted_ledger" ]; then
  err "no ready action created a ledger or retried a route"
fi

unresolvable_plan_worktree="$tmp_dir/worktree-unresolvable-plan"
unresolvable_plan="$(
  CHAIN_TRACKER_MODE=unresolvable "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route /implement \
    --target issue-unresolvable-plan \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$unresolvable_plan_worktree"
)"
assert_plan "unresolvable target" "$unresolvable_plan" \
  '{"decision":"decline","reason":"target-unresolvable","route":"/implement","target":"issue-unresolvable-plan","error":"GraphQL: Could not resolve to an issue or pull request with the number of issue-unresolvable-plan. (repository.issue)"}'
if [ -e "$plan_ledger" ]; then
  err "plan wrote a ledger row for an unresolvable target"
fi
if [ -e "$unresolvable_plan_worktree" ]; then
  err "plan created a worktree for an unresolvable target"
fi

ambiguous_404_plan="$(
  CHAIN_TRACKER_MODE=ambiguous-404 "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route /implement \
    --target issue-ambiguous-404 \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-ambiguous-404"
)"
assert_plan "ambiguous 404" "$ambiguous_404_plan" \
  '{"decision":"decline","reason":"tracker-unavailable","route":"/implement","target":"issue-ambiguous-404","error":"HTTP 404: resource not found"}'

rate_limit_plan_worktree="$tmp_dir/worktree-rate-limit-plan"
rate_limit_plan="$(
  CHAIN_TRACKER_MODE=rate-limit "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route /implement \
    --target issue-rate-limit-plan \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$rate_limit_plan_worktree"
)"
assert_plan "tracker-unavailable target" "$rate_limit_plan" \
  '{"decision":"decline","reason":"tracker-unavailable","route":"/implement","target":"issue-rate-limit-plan","error":"HTTP 403: API rate limit exceeded for user."}'
if [ -e "$plan_ledger" ]; then
  err "plan wrote a ledger row while the tracker was unavailable"
fi
if [ -e "$rate_limit_plan_worktree" ]; then
  err "plan created a worktree while the tracker was unavailable"
fi

missing_tracker_plan_worktree="$tmp_dir/worktree-missing-tracker-plan"
missing_tracker_plan="$(
  CHAIN_TRACKER_BIN=/definitely-missing-git-loopy-tracker "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route /implement \
    --target issue-missing-tracker-plan \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$missing_tracker_plan_worktree"
)"
if ! python3 - "$missing_tracker_plan" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
assert decision["decision"] == "decline"
assert decision["reason"] == "tracker-unavailable"
assert decision["target"] == "issue-missing-tracker-plan"
assert decision["error"].startswith("could not run tracker:")
PY
then
  err "plan did not fail closed when the tracker executable was missing"
fi
if [ -e "$plan_ledger" ]; then
  err "plan wrote a ledger row when the tracker executable was missing"
fi
if [ -e "$missing_tracker_plan_worktree" ]; then
  err "plan created a worktree when the tracker executable was missing"
fi

malformed_target_plan_worktree="$tmp_dir/worktree-malformed-target-plan"
malformed_target_plan="$(
  CHAIN_TARGET_RESPONSE=malformed-json "$CHAIN" plan \
    --ledger "$plan_ledger" \
    --route /implement \
    --target issue-malformed-target-plan \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$malformed_target_plan_worktree"
)"
if ! python3 - "$malformed_target_plan" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
assert decision["decision"] == "decline"
assert decision["reason"] == "tracker-unavailable"
assert decision["target"] == "issue-malformed-target-plan"
assert decision["error"].startswith("tracker returned invalid target data:")
PY
then
  err "plan did not classify malformed successful target JSON as transient"
fi
if [ -e "$plan_ledger" ]; then
  err "plan wrote a ledger row for malformed successful target JSON"
fi
if [ -e "$malformed_target_plan_worktree" ]; then
  err "plan created a worktree for malformed successful target JSON"
fi

collision_ledger="$tmp_dir/.git-loopy/collision-subagents.jsonl"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$collision_ledger" \
  --route implement \
  --target issue-collision-holder \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-collision-holder" \
  --chain-depth 1
all_collide="$(
  "$CHAIN" plan \
    --ledger "$collision_ledger" \
    --route /code-review \
    --target issue-collision-candidate \
    --safety AFK-safe \
    --agent code-review-agent \
    --model gpt-5.6-sol \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-collision-holder"
)"
assert_plan "all remaining candidates collide" "$all_collide" \
  '{"decision":"decline","reason":"worktree-in-flight","route":"/code-review","target":"issue-collision-candidate","worktree":"'"$tmp_dir"'/worktree-collision-holder"}'
cp "$collision_ledger" "$collision_ledger.before-terminal"
all_collide_terminal="$("$CHAIN" plan --ledger "$collision_ledger" --all-collide)"
assert_plan "every remaining candidate collides" "$all_collide_terminal" \
  '{"decision":"exhausted","reason":"all-candidates-collide"}'
if ! cmp -s "$collision_ledger.before-terminal" "$collision_ledger"; then
  err "ending the fill on collisions modified the ledger"
fi
if "$CHAIN" plan --ledger "$collision_ledger" --no-ready --all-collide 2>/dev/null; then
  err "plan accepted two fill terminals at once"
fi

fan_out_ledger="$tmp_dir/.git-loopy/fan-out-subagents.jsonl"
list_ledger="$tmp_dir/.git-loopy/list-subagents.jsonl"
if "$CHAIN" plan \
  --ledger "$list_ledger" \
  --route /implement \
  --route /code-review \
  --target issue-fill-list \
  --safety AFK-safe \
  --agent implement-agent \
  --model gpt-5.6-terra \
  --effort high \
  --context-tier default \
  --worktree "$tmp_dir/worktree-fill-list" \
  2>/dev/null
then
  err "plan accepted a list of routes"
fi
if "$CHAIN" plan \
  --ledger "$list_ledger" \
  --route /implement \
  --target issue-fill-list-one \
  --target issue-fill-list-two \
  --safety AFK-safe \
  --agent implement-agent \
  --model gpt-5.6-terra \
  --effort high \
  --context-tier default \
  --worktree "$tmp_dir/worktree-fill-list" \
  2>/dev/null
then
  err "plan accepted a list of targets"
fi
if "$CHAIN" plan \
  --ledger "$list_ledger" \
  --route /implement \
  --target issue-fill-list \
  --safety AFK-safe \
  --agent implement-agent \
  --model gpt-5.6-terra \
  --effort high \
  --context-tier default \
  --worktree "$tmp_dir/worktree-fill-list-one" \
  --worktree "$tmp_dir/worktree-fill-list-two" \
  2>/dev/null
then
  err "plan accepted a list of worktrees"
fi
if [ -e "$list_ledger" ]; then
  err "a rejected list of candidates reached the ledger"
fi

for slot in $(seq 1 10); do
  fan_out_worktree="$tmp_dir/worktree-fan-out-$slot"
  fan_out_decision="$(
    "$CHAIN" plan \
      --ledger "$fan_out_ledger" \
      --route /implement \
      --target "issue-fan-out-$slot" \
      --safety AFK-safe \
      --agent implement-agent \
      --model gpt-5.6-terra \
      --effort high \
      --context-tier default \
      --worktree "$fan_out_worktree"
  )"
  assert_plan "fan-out slot $slot" "$fan_out_decision" \
    '{"decision":"spawn","route":"/implement","target":"issue-fan-out-'"$slot"'","agent":"implement-agent","model":"gpt-5.6-terra","effort":"high","context_tier":"default","worktree":"'"$fan_out_worktree"'"}'
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$fan_out_ledger" \
    --route implement \
    --target "issue-fan-out-$slot" \
    --spawn-time "2026-08-22T00:$(printf '%02d' "$slot"):00Z" \
    --worktree "$fan_out_worktree" \
    --chain-depth 1
done

if ! python3 - "$fan_out_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

assert len(rows) == 10, rows
assert len({row["worktree"] for row in rows}) == 10, rows
assert all(not row["finish_time"] for row in rows), rows
PY
then
  err "fan-out did not reserve ten distinct in-flight worktrees"
fi

fan_out_worktrees="$(git -C "$tmp_dir" worktree list --porcelain | awk '/^worktree /')"
for slot in $(seq 1 10); do
  if [ ! -e "$tmp_dir/worktree-fan-out-$slot/.git" ]; then
    err "fan-out slot $slot has no working tree of its own"
  fi
  if ! grep -qxF "worktree $tmp_dir/worktree-fan-out-$slot" <<< "$fan_out_worktrees"; then
    err "fan-out slot $slot is not a registered worktree"
  fi
done

ceiling_decision="$(
  "$CHAIN" plan \
    --ledger "$fan_out_ledger" \
    --route /implement \
    --target issue-fan-out-eleven \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-fan-out-eleven"
)"
assert_plan "fan-out ceiling" "$ceiling_decision" \
  '{"decision":"decline","reason":"concurrency-limit","route":"/implement","target":"issue-fan-out-eleven"}'

concurrency_ledger="$tmp_dir/.git-loopy/concurrency-subagents.jsonl"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$concurrency_ledger" \
  --route implement \
  --target issue-concurrency-holder \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-concurrency-holder" \
  --chain-depth 1
cp "$concurrency_ledger" "$concurrency_ledger.before-limit"
if CHAIN_MAX_CONCURRENCY=1 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$concurrency_ledger" \
  --route implement \
  --target issue-concurrency-rejected \
  --spawn-time 2026-08-22T00:01:00Z \
  --worktree "$tmp_dir/worktree-concurrency-rejected" \
  --chain-depth 1 \
  2>/dev/null
then
  err "reserve exceeded the concurrency ceiling"
fi
if ! cmp -s "$concurrency_ledger.before-limit" "$concurrency_ledger"; then
  err "rejected reservation modified the ledger"
fi
concurrency_limit="$(
  CHAIN_MAX_CONCURRENCY=1 "$CHAIN" plan \
    --ledger "$concurrency_ledger" \
    --route /implement \
    --target issue-concurrency-candidate \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-concurrency-candidate"
)"
assert_plan "unbound reservation concurrency" "$concurrency_limit" \
  '{"decision":"decline","reason":"concurrency-limit","route":"/implement","target":"issue-concurrency-candidate"}'
if CHAIN_MAX_CONCURRENCY=11 "$CHAIN" plan \
  --ledger "$concurrency_ledger" \
  --route /implement \
  --target issue-invalid-concurrency \
  --safety AFK-safe \
  --agent implement-agent \
  --model gpt-5.6-terra \
  --effort high \
  --context-tier default \
  --worktree "$tmp_dir/worktree-invalid-concurrency" \
  2>/dev/null
then
  err "plan accepted a concurrency ceiling above ten"
fi

outside_route="$(plan /triage issue-6 AFK-safe triage-agent gpt-5.6-terra high default "$tmp_dir/plan-outside")"
assert_plan "outside route" "$outside_route" \
  '{"decision":"decline","reason":"route-not-allowlisted","route":"/triage","target":"issue-6"}'

hitl_route="$(plan /implement issue-6 HITL implement-agent gpt-5.6-terra high default "$tmp_dir/plan-hitl")"
assert_plan "HITL route" "$hitl_route" \
  '{"decision":"decline","reason":"action-not-afk-safe","route":"/implement","target":"issue-6"}'

afk_worktree="$tmp_dir/plan-afk"
afk_safe_route="$(plan /implement issue-6 AFK-safe implement-agent gpt-5.6-terra xhigh long_context "$afk_worktree")"
assert_plan "AFK-safe route" "$afk_safe_route" \
  '{"decision":"spawn","route":"/implement","target":"issue-6","agent":"implement-agent","model":"gpt-5.6-terra","effort":"xhigh","context_tier":"long_context","worktree":"'"$afk_worktree"'"}'

if [ -e "$plan_ledger" ]; then
  err "plan created a ledger"
fi

reserve_and_bind \
  --ledger "$plan_ledger" \
  --route implement \
  --target issue-6 \
  --session-id session-3 \
  --agent-id agent-3 \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:03:00Z \
  --worktree "$tmp_dir/worktree-4" \
  --chain-depth 1
cp "$plan_ledger" "$plan_ledger.before"

in_flight_target="$(plan /code-review issue-6 AFK-safe code-review-agent gpt-5.6-sol xhigh default "$tmp_dir/plan-in-flight-target")"
assert_plan "in-flight target" "$in_flight_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/code-review","target":"issue-6"}'

if ! cmp -s "$plan_ledger.before" "$plan_ledger"; then
  err "plan modified the ledger"
fi

held_worktree="$(plan /code-review issue-7 AFK-safe code-review-agent gpt-5.6-sol xhigh default "$tmp_dir/worktree-4")"
assert_plan "held worktree" "$held_worktree" \
  '{"decision":"decline","reason":"worktree-in-flight","route":"/code-review","target":"issue-7","worktree":"'"$tmp_dir"'/worktree-4"}'

other_candidate="$(plan /code-review issue-7 AFK-safe code-review-agent gpt-5.6-sol xhigh default "$tmp_dir/plan-other-candidate")"
assert_plan "other candidate after collision" "$other_candidate" \
  '{"decision":"spawn","route":"/code-review","target":"issue-7","agent":"code-review-agent","model":"gpt-5.6-sol","effort":"xhigh","context_tier":"default","worktree":"'"$tmp_dir"'/plan-other-candidate"}'

gate_bin="$tmp_dir/gate-bin"
mkdir -p "$gate_bin"
gate_head="0123456789abcdef0123456789abcdef01234567"
stale_gate_head="fedcba9876543210fedcba9876543210fedcba98"
cat > "$gate_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "${CHAIN_GATE_CASE:-allow}" in
    allow|no-review|malformed-review|stale-review|malformed-ticket-json|non-object-ticket|malformed-ticket-schema|ticket-unavailable)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    draft)
      printf '{"mergeable":"MERGEABLE","isDraft":true,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    missing-draft)
      printf '{"mergeable":"MERGEABLE","headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    null-draft)
      printf '{"mergeable":"MERGEABLE","isDraft":null,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    not-mergeable)
      printf '{"mergeable":"CONFLICTING","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    red-check)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"FAILURE"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    red-state)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"FAILURE"}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    pending-check)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","state":"IN_PROGRESS","conclusion":""}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    requested-check)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","status":"REQUESTED","conclusion":""}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    waiting-check)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[{"name":"tests","status":"WAITING","conclusion":""}]}\n' "$CHAIN_GATE_HEAD"
      ;;
    missing-checks)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s"}\n' "$CHAIN_GATE_HEAD"
      ;;
    null-checks)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":null}\n' "$CHAIN_GATE_HEAD"
      ;;
    empty-checks)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":[]}\n' "$CHAIN_GATE_HEAD"
      ;;
    malformed-checks)
      printf '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"%s","statusCheckRollup":{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}}\n' "$CHAIN_GATE_HEAD"
      ;;
    malformed-pr-json)
      printf '%s\n' '{'
      ;;
    non-object-pr)
      printf '%s\n' '[]'
      ;;
    missing-head)
      printf '%s\n' '{"mergeable":"MERGEABLE","isDraft":false,"statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}'
      ;;
    invalid-head)
      printf '%s\n' '{"mergeable":"MERGEABLE","isDraft":false,"headRefOid":"not-a-sha","statusCheckRollup":[{"name":"tests","state":"COMPLETED","conclusion":"SUCCESS"}]}'
      ;;
    *)
      echo "unknown gate case" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [ "$1" = "issue" ] && [ "$2" = "view" ] && [ "${CHAIN_GATE_CASE:-}" != "" ]; then
  case "${CHAIN_GATE_CASE}" in
    ticket-unavailable)
      exit 1
      ;;
    malformed-ticket-json)
      printf '%s\n' '{'
      ;;
    non-object-ticket)
      printf '%s\n' '[]'
      ;;
    malformed-ticket-schema)
      printf '%s\n' '{"comments":{}}'
      ;;
    no-review)
      printf '%s\n' '{"comments":[]}'
      ;;
    malformed-review)
      printf '%s\n' '{"comments":[{"body":"Review evidence is malformed.\nSuccessor: /merge"}]}'
      ;;
    *)
      evidence_head="$CHAIN_GATE_HEAD"
      [ "${CHAIN_GATE_CASE}" != "stale-review" ] || evidence_head="$CHAIN_STALE_GATE_HEAD"
      record="$(python3 "$CHAIN_REVIEW_RECORD" emit "$evidence_head")"
      python3 - "$record" <<'PY'
import json
import sys

print(json.dumps({
    "comments": [{
        "body": "Review passed for this candidate.\nSuccessor: /merge\n" + sys.argv[1],
    }],
}, separators=(",", ":")))
PY
      ;;
  esac
  exit 0
fi

if [ "$1" != "issue" ] || [ "$2" != "view" ] || [ "$4" != "--json" ] || [ "$5" != "comments" ]; then
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi

if [ "${CHAIN_EVIDENCE:-}" = "published" ]; then
  printf '%s\n' '{"comments":[{"createdAt":"2026-08-22T00:10:00Z","body":"Evidence comment"}]}'
else
  printf '%s\n' '{"comments":[]}'
fi
SH
chmod +x "$gate_bin/gh"

assert_gate() {
  local case_name="$1" gate_case="$2" expected_status="$3" expected_json="$4"
  local output status
  set +e
  output="$(
    PATH="$gate_bin:$PATH" \
      CHAIN_GATE_CASE="$gate_case" \
      CHAIN_GATE_HEAD="$gate_head" \
      CHAIN_STALE_GATE_HEAD="$stale_gate_head" \
      CHAIN_REVIEW_RECORD="$RECORD" \
      "$CHAIN" gate --pull-request 50 --ticket 50 2>/dev/null
  )"
  status=$?
  set -e
  if [ "$status" -ne "$expected_status" ]; then
    err "$case_name returned status $status instead of $expected_status"
  fi
  assert_plan "$case_name" "$output" "$expected_json"
}

assert_gate "merge gate allows complete evidence" allow 0 \
  '{"decision":"allow","pull_request":"50","headRefOid":"'"$gate_head"'","reason":"merge-evidence-complete"}'
assert_gate "merge gate refuses draft pull request" draft 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["pull-request-not-draft"],"reason":"pull-request-not-draft"}'
assert_gate "merge gate refuses missing draft evidence" missing-draft 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["pull-request-not-draft"],"reason":"pull-request-not-draft"}'
assert_gate "merge gate refuses null draft evidence" null-draft 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["pull-request-not-draft"],"reason":"pull-request-not-draft"}'
assert_gate "merge gate refuses non-mergeable pull request" not-mergeable 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["pull-request-mergeable"],"reason":"pull-request-mergeable"}'
assert_gate "merge gate refuses missing review evidence" no-review 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["review-clean-evidence-comment"],"reason":"review-clean-evidence-comment"}'
assert_gate "merge gate refuses malformed review evidence" malformed-review 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["review-clean-evidence-comment"],"reason":"review-clean-evidence-comment"}'
assert_gate "merge gate refuses review evidence for an earlier head" stale-review 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["review-clean-evidence-comment"],"reason":"review-clean-evidence-comment"}'
assert_gate "merge gate refuses red check" red-check 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-green"],"reason":"checks-green"}'
assert_gate "merge gate refuses state-based red check" red-state 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-green"],"reason":"checks-green"}'
assert_gate "merge gate refuses pending check" pending-check 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-complete"],"reason":"checks-complete"}'
assert_gate "merge gate refuses requested check as pending" requested-check 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-complete"],"reason":"checks-complete"}'
assert_gate "merge gate refuses waiting check as pending" waiting-check 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-complete"],"reason":"checks-complete"}'
assert_gate "merge gate refuses an absent check rollup" missing-checks 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-present"],"reason":"checks-present"}'
assert_gate "merge gate refuses a null check rollup" null-checks 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-present"],"reason":"checks-present"}'
assert_gate "merge gate refuses an empty check rollup" empty-checks 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-present"],"reason":"checks-present"}'
assert_gate "merge gate refuses a malformed check rollup" malformed-checks 1 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","missing":["checks-valid"],"reason":"checks-valid"}'
assert_gate "merge gate identifies malformed pull request JSON" malformed-pr-json 2 \
  '{"decision":"refuse","pull_request":"50","reason":"pull-request-evidence-invalid"}'
assert_gate "merge gate identifies non-object pull request JSON" non-object-pr 2 \
  '{"decision":"refuse","pull_request":"50","reason":"pull-request-evidence-invalid"}'
assert_gate "merge gate refuses a missing pull request head" missing-head 2 \
  '{"decision":"refuse","pull_request":"50","reason":"pull-request-evidence-invalid"}'
assert_gate "merge gate refuses an invalid pull request head" invalid-head 2 \
  '{"decision":"refuse","pull_request":"50","reason":"pull-request-evidence-invalid"}'
assert_gate "merge gate identifies malformed ticket JSON" malformed-ticket-json 2 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","reason":"ticket-evidence-invalid"}'
assert_gate "merge gate identifies non-object ticket JSON" non-object-ticket 2 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","reason":"ticket-evidence-invalid"}'
assert_gate "merge gate identifies malformed ticket schema" malformed-ticket-schema 2 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","reason":"ticket-evidence-invalid"}'
assert_gate "merge gate identifies unavailable ticket evidence" ticket-unavailable 2 \
  '{"decision":"refuse","pull_request":"50","headRefOid":"'"$gate_head"'","reason":"ticket-evidence-unavailable"}'

canonical_open_ledger="$tmp_dir/.git-loopy/canonical-open-subagents.jsonl"
python3 - "$canonical_open_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
row = {
    "route": "resolving-merge-conflicts",
    "target": "60",
    "session_id": "session-canonical-open",
    "agent_id": "agent-canonical-open",
    "agent_type": "resolving-merge-conflicts-agent",
    "agent_name": "resolving-merge-conflicts-agent",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": "/tmp/canonical-open",
    "chain_depth": 1,
    "finish_time": "",
    "outcome": "",
}
with open(ledger_path, "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
cp "$canonical_open_ledger" "$canonical_open_ledger.before"
canonical_lookup_log="$tmp_dir/canonical-lookups.log"

plan_ledger="$canonical_open_ledger"
for equivalent_target in 15 issue-15 60; do
  canonical_in_flight="$(
    PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
      CHAIN_GH_LOG="$canonical_lookup_log" \
      plan /code-review "$equivalent_target" AFK-safe code-review-agent \
        gpt-5.6-sol high default "$tmp_dir/plan-canonical-$equivalent_target"
  )"
  assert_plan "canonical in-flight target $equivalent_target" "$canonical_in_flight" \
    '{"decision":"decline","reason":"target-in-flight","route":"/code-review","target":"'"$equivalent_target"'"}'
done
if [ "$(wc -l < "$canonical_lookup_log" | tr -d ' ')" -ne 3 ]; then
  err "canonical target checks repeated GitHub lookups within one plan"
fi

canonical_unrelated="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /code-review 16 AFK-safe code-review-agent gpt-5.6-sol high default \
      "$tmp_dir/plan-canonical-unrelated"
)"
assert_plan "unrelated canonical target" "$canonical_unrelated" \
  '{"decision":"spawn","route":"/code-review","target":"16","agent":"code-review-agent","model":"gpt-5.6-sol","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-canonical-unrelated"}'

if PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$canonical_open_ledger" \
    --route code-review \
    --target issue-15 \
    --spawn-time 2026-08-22T00:01:00Z \
    --worktree "$tmp_dir/worktree-canonical-duplicate" \
    --chain-depth 2 \
    2>"$tmp_dir/canonical-duplicate.err"
then
  err "reserve accepted an equivalent target that was already in flight"
fi
if ! grep -q "target-in-flight: issue-15" "$tmp_dir/canonical-duplicate.err"; then
  err "reserve did not report the equivalent in-flight target"
fi
if [ -e "$tmp_dir/worktree-canonical-duplicate" ]; then
  err "equivalent target reservation created a worktree"
fi
if ! cmp -s "$canonical_open_ledger.before" "$canonical_open_ledger"; then
  err "matching an existing target spelling rewrote the legacy ledger row"
fi

canonical_halt_ledger="$tmp_dir/.git-loopy/canonical-halt-subagents.jsonl"
python3 - "$canonical_halt_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
row = {
    "route": "code-review",
    "target": "60",
    "session_id": "session-canonical-halt",
    "agent_id": "agent-canonical-halt",
    "agent_type": "code-review-agent",
    "agent_name": "code-review-agent",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": "/tmp/canonical-halt",
    "chain_depth": 1,
    "finish_time": "2026-08-22T00:10:00Z",
    "outcome": "no-evidence",
    "halt_reason": "no-evidence",
    "halted_at": "2026-08-22T00:10:00Z",
}
with open(ledger_path, "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

plan_ledger="$canonical_halt_ledger"
canonical_halted="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /implement 15 AFK-safe implement-agent gpt-5.6-terra high default \
      "$tmp_dir/plan-canonical-halted"
)"
assert_plan "canonical halted target" "$canonical_halted" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"no-evidence","route":"/implement","target":"15"}'

canonical_failed_ledger="$tmp_dir/.git-loopy/canonical-failed-subagents.jsonl"
python3 - "$canonical_failed_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
row = {
    "route": "implement",
    "target": "60",
    "session_id": "session-canonical-failed",
    "agent_id": "agent-canonical-failed",
    "agent_type": "implement-agent",
    "agent_name": "implement-agent",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": "/tmp/canonical-failed",
    "chain_depth": 1,
    "finish_time": "2026-08-22T00:10:00Z",
    "outcome": "failed",
}
with open(ledger_path, "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

plan_ledger="$canonical_failed_ledger"
canonical_failed="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /implement issue-15 AFK-safe implement-agent gpt-5.6-terra high default \
      "$tmp_dir/plan-canonical-failed"
)"
assert_plan "canonical failed target" "$canonical_failed" \
  '{"decision":"decline","reason":"target-failed","route":"/implement","target":"issue-15"}'

if PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$canonical_failed_ledger" \
    --route implement \
    --target 15 \
    --spawn-time 2026-08-22T00:11:00Z \
    --worktree "$tmp_dir/worktree-canonical-failed" \
    --chain-depth 2 \
    2>"$tmp_dir/canonical-failed.err"
then
  err "reserve accepted an equivalent target that had failed"
fi
if ! grep -q "target-failed: 15" "$tmp_dir/canonical-failed.err"; then
  err "reserve did not report the equivalent failed target"
fi
if [ -e "$tmp_dir/worktree-canonical-failed" ]; then
  err "failed target reservation created a worktree"
fi

canonical_guard_ledger="$tmp_dir/.git-loopy/canonical-guard-subagents.jsonl"
python3 - "$canonical_guard_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)

def bound(target, route, depth, identifier):
    return {
        "route": route,
        "target": target,
        "session_id": f"session-{identifier}",
        "agent_id": f"agent-{identifier}",
        "agent_type": f"{route}-agent",
        "agent_name": f"{route}-agent",
        "spawn_time": "2026-08-22T00:00:00Z",
        "worktree": f"/tmp/{identifier}",
        "chain_depth": depth,
        "finish_time": "2026-08-22T00:10:00Z",
        "outcome": "published",
    }

rows = [
    bound("60", "code-review", 1, "canonical-repeat-pr"),
    bound("15", "code-review", 2, "canonical-repeat-bare"),
    bound("issue-15", "code-review", 3, "canonical-repeat-prefixed"),
]
with open(ledger_path, "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

plan_ledger="$canonical_guard_ledger"
canonical_repetition="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /code-review issue-15 AFK-safe code-review-agent gpt-5.6-sol high default \
      "$tmp_dir/plan-canonical-repetition"
)"
assert_plan "canonical route repetition budget" "$canonical_repetition" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"route-repetition-limit","route":"/code-review","target":"issue-15"}'

canonical_depth_ledger="$tmp_dir/.git-loopy/canonical-depth-subagents.jsonl"
python3 - "$canonical_depth_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
rows = []
for depth in range(1, 9):
    route = (
        "implement",
        "code-review",
        "research",
        "push",
        "resolving-merge-conflicts",
    )[(depth - 1) % 5]
    rows.append({
        "route": route,
        "target": ("60", "15", "issue-15")[(depth - 1) % 3],
        "session_id": f"session-canonical-depth-{depth}",
        "agent_id": f"agent-canonical-depth-{depth}",
        "agent_type": f"{route}-agent",
        "agent_name": f"{route}-agent",
        "spawn_time": "2026-08-22T00:00:00Z",
        "worktree": f"/tmp/canonical-depth-{depth}",
        "chain_depth": depth,
        "finish_time": "2026-08-22T00:10:00Z",
        "outcome": "published",
    })

with open(ledger_path, "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

plan_ledger="$canonical_depth_ledger"
canonical_depth="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /research 15 AFK-safe research-agent claude-opus-5 high default \
      "$tmp_dir/plan-canonical-depth"
)"
assert_plan "canonical lineage depth budget" "$canonical_depth" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"chain-depth-limit","route":"/research","target":"15"}'

canonical_reserve_ledger="$tmp_dir/.git-loopy/canonical-reserve-subagents.jsonl"
PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
  "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$canonical_reserve_ledger" \
    --route implement \
    --target 60 \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$tmp_dir/worktree-canonical-reserve" \
    --chain-depth 1

if ! python3 - "$canonical_reserve_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

assert len(rows) == 1, rows
assert rows[0]["target"] == "issue-15", rows
PY
then
  err "reserve did not write the canonical target identity"
fi

"$CHAIN" bind \
  --ledger "$canonical_reserve_ledger" \
  --worktree "$tmp_dir/worktree-canonical-reserve" \
  --session-id session-canonical-reserve \
  --agent-id agent-canonical-reserve \
  --agent-type implement-agent \
  --agent-name implement-agent
canonical_completion="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published CHAIN_EXPECT_ISSUE=15 \
    "$CHAIN" complete --ledger "$canonical_reserve_ledger" \
      <<< '{"sessionId":"session-canonical-reserve","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'","agentId":"agent-canonical-reserve","agentType":"implement-agent","agentName":"implement-agent"}'
)"
assert_plan "canonical target completion" "$canonical_completion" \
  '{"continue":true,"outcome":"published","target":"issue-15"}'

legacy_completion_ledger="$tmp_dir/.git-loopy/legacy-completion-subagents.jsonl"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$legacy_completion_ledger" \
  --route implement \
  --target issue-15 \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-legacy-completion" \
  --chain-depth 1
"$CHAIN" bind \
  --ledger "$legacy_completion_ledger" \
  --worktree "$tmp_dir/worktree-legacy-completion" \
  --session-id session-legacy-completion \
  --agent-id agent-legacy-completion \
  --agent-type implement-agent \
  --agent-name implement-agent
python3 - "$legacy_completion_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
rows[0]["target"] = "60"
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

legacy_completion="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    CHAIN_EVIDENCE=published CHAIN_EXPECT_ISSUE=15 \
    "$CHAIN" complete --ledger "$legacy_completion_ledger" \
      <<< '{"sessionId":"session-legacy-completion","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'","agentId":"agent-legacy-completion","agentType":"implement-agent","agentName":"implement-agent"}'
)"
assert_plan "legacy target completion" "$legacy_completion" \
  '{"continue":true,"outcome":"published","target":"60"}'
if ! python3 - "$legacy_completion_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
assert row["target"] == "60", row
assert row["outcome"] == "published", row
PY
then
  err "legacy target completion rewrote or failed the existing row"
fi

resolution_failure_ledger="$tmp_dir/.git-loopy/resolution-failure-completion-subagents.jsonl"
reserve_and_bind \
  --ledger "$resolution_failure_ledger" \
  --route implement \
  --target issue-15 \
  --session-id session-resolution-failure-completion \
  --agent-id agent-resolution-failure-completion \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-resolution-failure-completion" \
  --chain-depth 1
python3 - "$resolution_failure_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
rows[0]["target"] = "60"
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

resolution_failure_status=0
resolution_failure_output="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    CHAIN_TARGET_LOOKUP=unavailable \
    "$CHAIN" complete --ledger "$resolution_failure_ledger" \
      <<< '{"sessionId":"session-resolution-failure-completion","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'","agentId":"agent-resolution-failure-completion","agentType":"implement-agent","agentName":"implement-agent"}' \
      2>/dev/null
)" || resolution_failure_status=$?
if [ "$resolution_failure_status" -ne 1 ]; then
  err "completion with an unresolvable canonical target returned $resolution_failure_status instead of 1"
fi
assert_plan "completion with an unresolvable canonical target" "$resolution_failure_output" \
  '{"continue":false,"outcome":"tracker-failed","target":"60","failure_kind":"transient","error":"target-resolution-failed: gh unavailable","exit_status":1}'
if ! python3 - "$resolution_failure_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
assert row["finish_time"] == "2026-08-22T00:11:00Z", row
assert row["outcome"] == "tracker-failed", row
assert row["tracker_failure_kind"] == "transient", row
assert "halt_reason" not in row, row
PY
then
  err "completion with an unresolvable canonical target left the row open or halted it"
fi
if [ -e "$tmp_dir/worktree-resolution-failure-completion" ]; then
  err "completion with an unresolvable canonical target left its clean worktree on disk"
fi

plan_ledger="$tmp_dir/.git-loopy/canonical-resolution-failure.jsonl"
for resolution_failure in rate-limited unavailable; do
  case "$resolution_failure" in
    rate-limited) resolution_detail="API rate limit exceeded" ;;
    unavailable) resolution_detail="gh unavailable" ;;
  esac
  canonical_resolution_failure="$(
    PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
      CHAIN_TARGET_LOOKUP="$resolution_failure" \
      plan /implement 60 AFK-safe implement-agent gpt-5.6-terra high default \
        "$tmp_dir/plan-canonical-resolution-$resolution_failure"
  )"
  assert_plan "target resolution $resolution_failure" "$canonical_resolution_failure" \
    '{"decision":"decline","reason":"target-resolution-failed","route":"/implement","target":"60","error":"'"$resolution_detail"'"}'
done

non_utf8_resolution="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    CHAIN_TARGET_LOOKUP=non-utf8 \
    plan /implement 60 AFK-safe implement-agent gpt-5.6-terra high default \
      "$tmp_dir/plan-canonical-resolution-non-utf8"
)"
if ! python3 - "$non_utf8_resolution" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
assert decision["decision"] == "decline", decision
assert decision["reason"] == "target-resolution-failed", decision
assert decision["error"].startswith("could not run gh:"), decision
PY
then
  err "plan did not decline cleanly when the canonical lookup returned non-UTF-8 output"
fi

legacy_unresolvable_ledger="$tmp_dir/.git-loopy/legacy-unresolvable-subagents.jsonl"
python3 - "$legacy_unresolvable_ledger" <<'PY'
import json
import os
import sys

ledger_path = sys.argv[1]
os.makedirs(os.path.dirname(ledger_path), exist_ok=True)
row = {
    "route": "code-review",
    "target": "7",
    "session_id": "session-legacy-unresolvable",
    "agent_id": "agent-legacy-unresolvable",
    "agent_type": "code-review-agent",
    "agent_name": "code-review-agent",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": "/tmp/legacy-unresolvable",
    "chain_depth": 1,
    "finish_time": "2026-08-22T00:10:00Z",
    "outcome": "published",
}
with open(ledger_path, "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
plan_ledger="$legacy_unresolvable_ledger"
unrelated_beside_legacy="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /code-review issue-unrelated-legacy AFK-safe code-review-agent \
      gpt-5.6-sol high default "$tmp_dir/plan-unrelated-legacy"
)"
assert_plan "unrelated target beside an unresolvable legacy row" "$unrelated_beside_legacy" \
  '{"decision":"spawn","route":"/code-review","target":"issue-unrelated-legacy","agent":"code-review-agent","model":"gpt-5.6-sol","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-unrelated-legacy"}'
requested_unresolvable="$(
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    plan /code-review 7 AFK-safe code-review-agent \
      gpt-5.6-sol high default "$tmp_dir/plan-requested-unresolvable"
)"
assert_plan "requested pull request without exactly one closing issue" "$requested_unresolvable" \
  '{"decision":"decline","reason":"target-resolution-failed","route":"/code-review","target":"7","error":"pull request #7 does not close exactly one issue"}'

resolution_reserve_ledger="$tmp_dir/.git-loopy/resolution-reserve.jsonl"
resolution_reserve_worktree="$tmp_dir/worktree-resolution-reserve"
resolution_reserve_error="$tmp_dir/resolution-reserve.err"
if (
  cd "$tmp_dir"
  PATH="$fake_bin:$PATH" GH_REPO=bradcstevens/git-loopy-skills \
    CHAIN_TARGET_LOOKUP=unavailable "$CHAIN" reserve --parent-pid "$$" \
    --ledger "$resolution_reserve_ledger" \
    --route implement \
    --target 60 \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$resolution_reserve_worktree" \
    --chain-depth 1 \
    2>"$resolution_reserve_error"
)
then
  err "reserve accepted a target whose canonical lookup failed"
fi
if ! grep -q "target-resolution-failed: 60: gh unavailable" "$resolution_reserve_error"; then
  err "reserve did not name the target and cause of a failed canonical lookup"
fi
if [ -e "$resolution_reserve_ledger" ] || [ -e "$resolution_reserve_worktree" ]; then
  err "reserve consumed a ledger row or worktree for a failed canonical lookup"
fi

complete_ledger="$tmp_dir/.git-loopy/complete-subagents.jsonl"
reserve_and_bind \
  --ledger "$complete_ledger" \
  --route implement \
  --target issue-published \
  --session-id session-published \
  --agent-id agent-published \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-published" \
  --chain-depth 1

completion_payload() {
  local agent_id="$1" timestamp="${2:-2026-08-22T00:11:00Z}"
  local agent_name="${3:-implement-agent}" agent_type="${4:-implement-agent}"
  local session_id="${5:-session-$agent_id}"
  local cwd="${6:-$tmp_dir}"
  local timestamp_json
  if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    timestamp_json="$timestamp"
  else
    timestamp_json="$(python3 -c 'import json; import sys; print(json.dumps(sys.argv[1]))' "$timestamp")"
  fi
  printf '%s' '{"sessionId":"'"$session_id"'","timestamp":'"$timestamp_json"',"cwd":"'"$cwd"'","transcriptPath":"'"$tmp_dir"'/transcript.jsonl","agentId":"'"$agent_id"'","agentType":"'"$agent_type"'","agentName":"'"$agent_name"'","agentDisplayName":"Implement agent","response":"Completed the route.","stopReason":"end_turn"}'
}

serial_repo="$tmp_dir/serial-reentry-repository"
git init --quiet "$serial_repo"
git -C "$serial_repo" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m initial
(
  cd "$serial_repo"
  "$CHAIN" reserve --parent-pid "$$" \
    --route code-review \
    --target issue-serial-hop \
    --spawn-time 2026-08-22T00:02:00Z \
    --worktree "$serial_repo" \
    --chain-depth 1 \
    --session-id session-serial-hop \
    --in-place
  "$CHAIN" bind \
    --worktree "$serial_repo" \
    --session-id session-serial-hop \
    --agent-id agent-serial-hop \
    --agent-type code-review-agent \
    --agent-name code-review-agent
)
serial_ledger="$serial_repo/.git-loopy/subagents.jsonl"
serial_completion_output="$(
  cd "$serial_repo"
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
    <<< "$(completion_payload agent-serial-hop 2026-08-22T00:11:00Z code-review-agent code-review-agent session-serial-hop "$serial_repo")"
)"
assert_plan "serial in-place completion" "$serial_completion_output" \
  '{"continue":true,"outcome":"published","target":"issue-serial-hop"}'
if [ ! -d "$serial_repo/.git" ] && [ ! -f "$serial_repo/.git" ]; then
  err "in-place completion removed the spawning worktree"
fi
serial_reentry="$(
  python3 "$REPO/skills/setup-git-loopy-skills/git-loopy-agent-stop.py" \
    <<< '{"cwd":"'"$serial_repo"'","timestamp":"2026-08-22T00:12:00Z","stop_hook_active":false}'
)"
if [ "$serial_reentry" != '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","targets":["issue-serial-hop"]}' ]; then
  err "serial completion did not re-enter /next through agentStop"
fi
if ! python3 - "$serial_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["finish_time"] == "2026-08-22T00:11:00Z", row
assert row["outcome"] == "published", row
assert row["routed"] is True, row
assert row["routed_at"] == "2026-08-22T00:12:00Z", row
PY
then
  err "serial hop did not close and route its ledger row"
fi
"$CHAIN" bind \
  --ledger "$fan_out_ledger" \
  --worktree "$tmp_dir/worktree-fan-out-1" \
  --session-id session-fan-out-1 \
  --agent-id agent-fan-out-1 \
  --agent-type implement-agent \
  --agent-name implement-agent
refill_completion="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$fan_out_ledger" \
    <<< "$(completion_payload agent-fan-out-1 2026-08-22T00:11:00Z implement-agent implement-agent session-fan-out-1 "$tmp_dir/worktree-fan-out-1")"
)"
assert_plan "fan-out completion" "$refill_completion" \
  '{"continue":true,"outcome":"published","target":"issue-fan-out-1"}'
refill_decision="$(
  "$CHAIN" plan \
    --ledger "$fan_out_ledger" \
    --route /implement \
    --target issue-fan-out-refill \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-fan-out-refill"
)"
assert_plan "fan-out refill after completion" "$refill_decision" \
  '{"decision":"spawn","route":"/implement","target":"issue-fan-out-refill","agent":"implement-agent","model":"gpt-5.6-terra","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/worktree-fan-out-refill"}'

unbound_ledger="$tmp_dir/.git-loopy/unbound-subagents.jsonl"
unbound_worktree="$tmp_dir/worktree-unbound"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$unbound_ledger" \
  --route implement \
  --target issue-unbound \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$unbound_worktree" \
  --chain-depth 1
cp "$unbound_ledger" "$unbound_ledger.before-complete"
unbound_output="$(
  PATH="$fake_bin:$PATH" "$CHAIN" complete --ledger "$unbound_ledger" \
    <<< "$(completion_payload agent-unbound 2026-08-22T00:11:00Z implement-agent implement-agent session-unbound "$unbound_worktree")"
)"
assert_plan "unbound completion" "$unbound_output" \
  '{"continue":false,"reason":"unbound-reservation","worktree":"'"$unbound_worktree"'"}'
if ! cmp -s "$unbound_ledger.before-complete" "$unbound_ledger"; then
  err "unbound completion modified the ledger"
fi

published_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-published 1787357460000 implement-agent implement-agent session-published)"
)"
assert_plan "published completion" "$published_output" \
  '{"continue":true,"outcome":"published","target":"issue-published"}'

if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

assert [{
    key: row[key]
    for key in (
        "route", "target", "session_id", "agent_id", "agent_type", "agent_name",
        "spawn_time", "worktree", "chain_depth", "finish_time", "outcome",
    )
} for row in rows] == [{
    "route": "implement",
    "target": "issue-published",
    "session_id": "session-published",
    "agent_id": "agent-published",
    "agent_type": "implement-agent",
    "agent_name": "implement-agent",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": sys.argv[1].replace("/.git-loopy/complete-subagents.jsonl", "/worktree-published"),
    "chain_depth": 1,
    "finish_time": "2026-08-22T00:11:00Z",
    "outcome": "published",
}]
assert rows[0]["finish_time"] == "2026-08-22T00:11:00Z"
PY
then
  err "published completion did not close the matching ledger row"
fi

if [ -e "$tmp_dir/worktree-published" ]; then
  err "published completion did not remove its worktree"
fi

default_worktree="$tmp_dir/worktree-default-ledger"
(
  cd "$tmp_dir"
  reserve_and_bind \
    --route implement \
    --target issue-default-ledger \
    --session-id session-default-ledger \
    --agent-id agent-default-ledger \
    --agent-type implement-agent \
    --agent-name implement-agent \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$default_worktree" \
    --chain-depth 1
)

default_completion_output="$(
  cd "$default_worktree"
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
    <<< "$(completion_payload agent-default-ledger 2026-08-22T00:11:00Z implement-agent implement-agent session-default-ledger)"
)"
assert_plan "linked worktree completion" "$default_completion_output" \
  '{"continue":true,"outcome":"published","target":"issue-default-ledger"}'

if [ -e "$default_worktree" ]; then
  err "completion from a linked worktree did not remove its worktree"
fi

separate_git_dir="$tmp_dir/vault-gitdir"
separate_working_tree="$tmp_dir/vault"
separate_worktree="$tmp_dir/vault-run-1"
separate_ledger="$separate_working_tree/.git-loopy/subagents.jsonl"
git init --quiet --separate-git-dir="$separate_git_dir" "$separate_working_tree"
git -C "$separate_working_tree" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m initial
(
  cd "$separate_working_tree"
  reserve_and_bind \
    --route implement \
    --target issue-separate-git-dir \
    --session-id session-separate-git-dir \
    --agent-id agent-separate-git-dir \
    --agent-type implement-agent \
    --agent-name implement-agent \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$separate_worktree" \
    --chain-depth 1
)

if [ ! -f "$separate_ledger" ]; then
  err "reserve from a separate-git-dir repository did not use the main working tree ledger"
fi
if [ -e "$separate_git_dir/.git-loopy/subagents.jsonl" ]; then
  err "reserve from a separate-git-dir repository wrote the ledger into the gitdir"
fi
if [ -e "$separate_worktree/.git-loopy/subagents.jsonl" ]; then
  err "reserve from a separate-git-dir repository created a linked worktree ledger"
fi

separate_completion_output="$(
  cd "$separate_worktree"
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
    <<< "$(completion_payload agent-separate-git-dir 2026-08-22T00:11:00Z implement-agent implement-agent session-separate-git-dir "$separate_worktree")"
)"
assert_plan "separate-git-dir linked worktree completion" "$separate_completion_output" \
  '{"continue":true,"outcome":"published","target":"issue-separate-git-dir"}'

if ! python3 - "$separate_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

assert len(rows) == 1
assert rows[0]["session_id"] == "session-separate-git-dir"
assert rows[0]["finish_time"] == "2026-08-22T00:11:00Z"
assert rows[0]["outcome"] == "published"
PY
then
  err "completion from a separate-git-dir linked worktree did not close the main ledger row"
fi

if [ -e "$separate_worktree" ]; then
  err "completion from a separate-git-dir linked worktree did not remove its worktree"
fi
if git -C "$separate_working_tree" worktree list --porcelain |
  grep -qxF "worktree $separate_worktree"; then
  err "completion from a separate-git-dir linked worktree leaked its worktree registration"
fi

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route code-review \
  --target issue-no-evidence \
  --session-id session-no-evidence \
  --agent-id agent-no-evidence \
  --agent-type code-review-agent \
  --agent-name code-review-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-no-evidence" \
  --chain-depth 2

no_evidence_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=no-evidence "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-no-evidence 2026-08-22T00:11:00Z code-review-agent code-review-agent session-no-evidence)"
)"
assert_plan "no-evidence completion" "$no_evidence_output" \
  '{"continue":false,"outcome":"no-evidence","target":"issue-no-evidence"}'
if [ -e "$tmp_dir/worktree-no-evidence" ]; then
  err "no-evidence completion left its clean worktree on disk"
fi

if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == "session-no-evidence")
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "no-evidence"
assert row["halt_reason"] == "no-evidence"
assert row["halted_at"] == "2026-08-22T00:11:00Z"
PY
then
  err "no-evidence completion did not record its target halt"
fi

plan_ledger="$complete_ledger"
no_evidence_target="$(plan /implement issue-no-evidence AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-no-evidence")"
assert_plan "no-evidence target" "$no_evidence_target" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"no-evidence","route":"/implement","target":"issue-no-evidence"}'

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route push \
  --target issue-clean-transient-tracker-failure \
  --session-id session-clean-transient-tracker-failure \
  --agent-id agent-clean-transient-tracker-failure \
  --agent-type push-agent \
  --agent-name push-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-clean-transient-tracker-failure" \
  --chain-depth 3

clean_transient_tracker_failure_status=0
if clean_transient_tracker_failure_output="$(
  CHAIN_TRACKER_MODE=transport-failure "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-clean-transient-tracker-failure 2026-08-22T00:11:00Z push-agent push-agent session-clean-transient-tracker-failure)" \
    2>"$tmp_dir/clean-transient-tracker-failure.err"
)"
then
  err "clean transient tracker failure returned success"
else
  clean_transient_tracker_failure_status=$?
fi
if [ "$clean_transient_tracker_failure_status" -ne 23 ]; then
  err "clean transient tracker failure did not preserve its exit status"
fi
if ! python3 - "$clean_transient_tracker_failure_output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["outcome"] == "tracker-failed"
assert result["failure_kind"] == "transient"
assert "retained_worktree" not in result
PY
then
  err "clean transient tracker failure was not reported as removed"
fi
if [ -e "$tmp_dir/worktree-clean-transient-tracker-failure" ]; then
  err "clean transient tracker failure left its worktree on disk"
fi

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route push \
  --target issue-transient-tracker-failure \
  --session-id session-transient-tracker-failure \
  --agent-id agent-transient-tracker-failure \
  --agent-type push-agent \
  --agent-name push-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-transient-tracker-failure" \
  --chain-depth 3

printf 'uncommitted work\n' > "$tmp_dir/worktree-transient-tracker-failure/uncommitted.txt"
transient_tracker_failure_error="$tmp_dir/transient-tracker-failure.err"
transient_tracker_failure_status=0
if transient_tracker_failure_output="$(
  CHAIN_TRACKER_MODE=transport-failure "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-transient-tracker-failure 2026-08-22T00:11:00Z push-agent push-agent session-transient-tracker-failure)" \
    2>"$transient_tracker_failure_error"
)"
then
  err "tracker transport failure returned success"
else
  transient_tracker_failure_status=$?
fi
if [ "$transient_tracker_failure_status" -ne 23 ]; then
  err "tracker transport failure did not preserve its exit status"
fi
assert_plan "transient tracker failure" "$transient_tracker_failure_output" \
  '{"continue":false,"outcome":"tracker-failed","target":"issue-transient-tracker-failure","failure_kind":"transient","error":"tracker transport failed for issue-transient-tracker-failure","exit_status":23,"retained_worktree":"'"$tmp_dir"'/worktree-transient-tracker-failure"}'
if ! grep -q \
  "tracker lookup failed for issue-transient-tracker-failure: tracker transport failed for issue-transient-tracker-failure" \
  "$transient_tracker_failure_error"
then
  err "tracker transport failure did not report its target and cause"
fi
if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(
    row
    for row in rows
    if row["session_id"] == "session-transient-tracker-failure"
)
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "tracker-failed"
assert row["tracker_error"] == (
    "tracker transport failed for issue-transient-tracker-failure"
)
assert row["tracker_failure_kind"] == "transient"
assert "halt_reason" not in row
assert "halted_at" not in row
PY
then
  err "transient tracker failure did not close the row without halting the target"
fi
if [ ! -f "$tmp_dir/worktree-transient-tracker-failure/uncommitted.txt" ]; then
  err "transient tracker failure removed uncommitted work"
fi
if ! grep -q \
  "worktree has uncommitted changes and was retained: $tmp_dir/worktree-transient-tracker-failure" \
  "$transient_tracker_failure_error"
then
  err "transient tracker failure did not report its retained dirty worktree"
fi

plan_ledger="$complete_ledger"
transient_retry="$(plan /push issue-transient-tracker-failure AFK-safe push-agent gpt-5.6-terra high default "$tmp_dir/plan-transient-retry")"
assert_plan "transient tracker retry" "$transient_retry" \
  '{"decision":"spawn","route":"/push","target":"issue-transient-tracker-failure","agent":"push-agent","model":"gpt-5.6-terra","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-transient-retry"}'

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route push \
  --target issue-missing-tracker-complete \
  --session-id session-missing-tracker-complete \
  --agent-id agent-missing-tracker-complete \
  --agent-type push-agent \
  --agent-name push-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-missing-tracker-complete" \
  --chain-depth 3

printf 'uncommitted launch failure work\n' > "$tmp_dir/worktree-missing-tracker-complete/uncommitted.txt"
missing_tracker_complete_error="$tmp_dir/missing-tracker-complete.err"
missing_tracker_complete_status=0
if missing_tracker_complete_output="$(
  CHAIN_TRACKER_BIN=/definitely-missing-git-loopy-tracker \
    "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-missing-tracker-complete 2026-08-22T00:11:00Z push-agent push-agent session-missing-tracker-complete)" \
    2>"$missing_tracker_complete_error"
)"
then
  err "missing tracker executable during complete returned success"
else
  missing_tracker_complete_status=$?
fi
if [ "$missing_tracker_complete_status" -ne 1 ]; then
  err "missing tracker executable during complete did not return failure"
fi
if ! python3 - "$missing_tracker_complete_output" "$tmp_dir/worktree-missing-tracker-complete" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["continue"] is False
assert result["outcome"] == "tracker-failed"
assert result["target"] == "issue-missing-tracker-complete"
assert result["failure_kind"] == "transient"
assert result["error"].startswith("could not run tracker:")
assert result["exit_status"] == 1
assert result["retained_worktree"] == sys.argv[2]
PY
then
  err "complete did not record a missing tracker executable as transient"
fi
if ! grep -q \
  "tracker lookup failed for issue-missing-tracker-complete: could not run tracker:" \
  "$missing_tracker_complete_error"
then
  err "complete did not report the missing tracker executable"
fi
if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(
    row
    for row in rows
    if row["session_id"] == "session-missing-tracker-complete"
)
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "tracker-failed"
assert row["tracker_failure_kind"] == "transient"
assert row["tracker_error"].startswith("could not run tracker:")
assert "halt_reason" not in row
assert "halted_at" not in row
PY
then
  err "missing tracker executable left the completion row open or halted"
fi
if [ ! -f "$tmp_dir/worktree-missing-tracker-complete/uncommitted.txt" ]; then
  err "missing tracker executable removed the completion worktree"
fi

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route push \
  --target issue-malformed-comment-complete \
  --session-id session-malformed-comment-complete \
  --agent-id agent-malformed-comment-complete \
  --agent-type push-agent \
  --agent-name push-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-malformed-comment-complete" \
  --chain-depth 3

printf 'uncommitted malformed response work\n' > "$tmp_dir/worktree-malformed-comment-complete/uncommitted.txt"
malformed_comment_complete_error="$tmp_dir/malformed-comment-complete.err"
malformed_comment_complete_status=0
if malformed_comment_complete_output="$(
  CHAIN_COMMENT_RESPONSE=invalid-timestamp \
    "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-malformed-comment-complete 2026-08-22T00:11:00Z push-agent push-agent session-malformed-comment-complete)" \
    2>"$malformed_comment_complete_error"
)"
then
  err "malformed successful comment data during complete returned success"
else
  malformed_comment_complete_status=$?
fi
if [ "$malformed_comment_complete_status" -ne 2 ]; then
  err "malformed successful comment data did not return protocol failure"
fi
if ! python3 - "$malformed_comment_complete_output" "$tmp_dir/worktree-malformed-comment-complete" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["continue"] is False
assert result["outcome"] == "tracker-failed"
assert result["target"] == "issue-malformed-comment-complete"
assert result["failure_kind"] == "transient"
assert result["error"].startswith("tracker returned invalid comment timestamp at index 0:")
assert result["exit_status"] == 2
assert result["retained_worktree"] == sys.argv[2]
PY
then
  err "complete did not classify malformed successful comment data as transient"
fi
if ! grep -q \
  "tracker lookup failed for issue-malformed-comment-complete: tracker returned invalid comment timestamp at index 0:" \
  "$malformed_comment_complete_error"
then
  err "complete did not report malformed successful comment data"
fi
if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(
    row
    for row in rows
    if row["session_id"] == "session-malformed-comment-complete"
)
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "tracker-failed"
assert row["tracker_failure_kind"] == "transient"
assert row["tracker_error"].startswith(
    "tracker returned invalid comment timestamp at index 0:"
)
assert "halt_reason" not in row
assert "halted_at" not in row
PY
then
  err "malformed successful comment data left the row open or halted"
fi
if [ ! -f "$tmp_dir/worktree-malformed-comment-complete/uncommitted.txt" ]; then
  err "malformed successful comment data removed the completion worktree"
fi

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route push \
  --target issue-permanent-tracker-failure \
  --session-id session-permanent-tracker-failure \
  --agent-id agent-permanent-tracker-failure \
  --agent-type push-agent \
  --agent-name push-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-permanent-tracker-failure" \
  --chain-depth 3

printf 'uncommitted permanent-failure work\n' > "$tmp_dir/worktree-permanent-tracker-failure/uncommitted.txt"
permanent_tracker_failure_error="$tmp_dir/permanent-tracker-failure.err"
permanent_tracker_failure_status=0
if permanent_tracker_failure_output="$(
  CHAIN_TRACKER_MODE=not-found "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-permanent-tracker-failure 2026-08-22T00:11:00Z push-agent push-agent session-permanent-tracker-failure)" \
    2>"$permanent_tracker_failure_error"
)"
then
  err "permanent tracker failure returned success"
else
  permanent_tracker_failure_status=$?
fi
if [ "$permanent_tracker_failure_status" -ne 1 ]; then
  err "permanent tracker failure did not preserve its exit status"
fi
assert_plan "permanent tracker failure" "$permanent_tracker_failure_output" \
  '{"continue":false,"outcome":"tracker-failed","target":"issue-permanent-tracker-failure","failure_kind":"permanent","error":"GraphQL: Could not resolve to an issue or pull request with the number of issue-permanent-tracker-failure. (repository.issue)","exit_status":1,"retained_worktree":"'"$tmp_dir"'/worktree-permanent-tracker-failure"}'
if ! grep -q \
  "tracker lookup failed for issue-permanent-tracker-failure: GraphQL: Could not resolve to an issue or pull request with the number of issue-permanent-tracker-failure. (repository.issue)" \
  "$permanent_tracker_failure_error"
then
  err "permanent tracker failure did not report its target and cause"
fi
if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(
    row
    for row in rows
    if row["session_id"] == "session-permanent-tracker-failure"
)
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "tracker-failed"
assert row["tracker_error"] == (
    "GraphQL: Could not resolve to an issue or pull request with the number of issue-permanent-tracker-failure. (repository.issue)"
)
assert row["tracker_failure_kind"] == "permanent"
assert row["halt_reason"] == "tracker-failed"
assert row["halted_at"] == "2026-08-22T00:11:00Z"
PY
then
  err "permanent tracker failure did not close and halt the target"
fi
if [ ! -f "$tmp_dir/worktree-permanent-tracker-failure/uncommitted.txt" ]; then
  err "permanent tracker failure removed uncommitted work"
fi
if ! grep -q \
  "worktree has uncommitted changes and was retained: $tmp_dir/worktree-permanent-tracker-failure" \
  "$permanent_tracker_failure_error"
then
  err "permanent tracker failure did not report its retained dirty worktree"
fi

permanent_retry="$(plan /push issue-permanent-tracker-failure AFK-safe push-agent gpt-5.6-terra high default "$tmp_dir/plan-permanent-retry")"
assert_plan "permanent tracker halt" "$permanent_retry" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"tracker-failed","route":"/push","target":"issue-permanent-tracker-failure"}'

# Each transient tracker failure must still close the row, leave the target retryable,
# and remove a clean worktree. The hang case waits out the real 30-second tracker timeout.
transient_tracker_cases=(
  "rate-limit:HTTP 403: API rate limit exceeded for user."
  "http-429:HTTP 429: too many requests"
  "server-failure:HTTP 503: service unavailable"
  "ambiguous-404:HTTP 404: resource not found"
  "timeout:request timed out while resolving issue-tracker-case-timeout"
  "hang:tracker timed out after 30 seconds"
  "non-utf8:tracker output was not valid UTF-8"
)
for transient_tracker_case in "${transient_tracker_cases[@]}"; do
  IFS=: read -r case_mode case_message <<< "$transient_tracker_case"
  case_slug="tracker-case-$case_mode"
  case_worktree="$tmp_dir/worktree-$case_slug"

  reserve_and_bind \
    --ledger "$complete_ledger" \
    --route push \
    --target "issue-$case_slug" \
    --session-id "session-$case_slug" \
    --agent-id "agent-$case_slug" \
    --agent-type push-agent \
    --agent-name push-agent \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$case_worktree" \
    --chain-depth 3

  case_status=0
  case_output="$(
    if [ "$case_mode" = non-utf8 ]; then
      CHAIN_COMMENT_RESPONSE=non-utf8
      export CHAIN_COMMENT_RESPONSE
    else
      CHAIN_TRACKER_MODE="$case_mode"
      export CHAIN_TRACKER_MODE
    fi
    "$CHAIN" complete --ledger "$complete_ledger" \
      <<< "$(completion_payload "agent-$case_slug" 2026-08-22T00:11:00Z push-agent push-agent "session-$case_slug")" \
      2>/dev/null
  )" || case_status=$?

  case "$case_mode" in
    hang) expected_status=124 ;;
    non-utf8) expected_status=2 ;;
    *) expected_status=1 ;;
  esac
  if [ "$case_status" -ne "$expected_status" ]; then
    err "$case_mode tracker failure returned $case_status instead of $expected_status"
  fi
  if ! python3 - "$case_output" "$case_message" "$expected_status" "issue-$case_slug" <<'PY'
import json
import sys

output, message, expected_status, target = sys.argv[1:]
result = json.loads(output)
assert result["continue"] is False
assert result["outcome"] == "tracker-failed"
assert result["target"] == target
assert result["failure_kind"] == "transient"
assert result["exit_status"] == int(expected_status)
assert result["error"].startswith(message), result["error"]
assert "retained_worktree" not in result
PY
  then
    err "$case_mode tracker failure did not report a transient tracker-failed result"
  fi
  if ! python3 - "$complete_ledger" "session-$case_slug" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == sys.argv[2])
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "tracker-failed"
assert row["tracker_failure_kind"] == "transient"
assert "halt_reason" not in row
assert "halted_at" not in row
PY
  then
    err "$case_mode tracker failure left the row open or halted the target"
  fi
  if [ -e "$case_worktree" ]; then
    err "$case_mode tracker failure left its clean worktree on disk"
  fi
done

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route research \
  --target issue-depth-complete \
  --session-id session-depth-complete \
  --agent-id agent-depth-complete \
  --agent-type research-agent \
  --agent-name research-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-depth-complete" \
  --chain-depth 8

depth_complete_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-depth-complete 2026-08-22T00:11:00Z research-agent research-agent session-depth-complete)"
)"
assert_plan "eighth completed lineage hop" "$depth_complete_output" \
  '{"continue":false,"outcome":"published","target":"issue-depth-complete"}'

if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == "session-depth-complete")
assert row["outcome"] == "published"
assert row["halt_reason"] == "chain-depth-limit"
assert row["halted_at"] == "2026-08-22T00:11:00Z"
PY
then
  err "eighth hop did not record the depth halt before re-entry"
fi

depth_increment_ledger="$tmp_dir/.git-loopy/depth-increment-subagents.jsonl"
reserve_and_bind \
  --ledger "$depth_increment_ledger" \
  --route implement \
  --target issue-depth-increment \
  --session-id session-depth-increment-1 \
  --agent-id agent-depth-increment-1 \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-depth-increment-1" \
  --chain-depth 1

PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$depth_increment_ledger" \
  <<< "$(completion_payload agent-depth-increment-1 2026-08-22T00:11:00Z implement-agent implement-agent session-depth-increment-1)" \
  >/dev/null

"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$depth_increment_ledger" \
  --route code-review \
  --target issue-depth-increment \
  --spawn-time 2026-08-22T00:12:00Z \
  --worktree "$tmp_dir/worktree-depth-increment-2" \
  --chain-depth 1

if ! python3 - "$depth_increment_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["worktree"].endswith("worktree-depth-increment-2"))
assert row["chain_depth"] == 2
PY
then
  err "reserve did not derive the next target lineage depth"
fi

guard_ledger="$tmp_dir/.git-loopy/guard-subagents.jsonl"
python3 - "$guard_ledger" <<'PY'
import json
import sys

ledger_path = sys.argv[1]

def bound(target, route, depth, identifier, finish_time="2026-08-22T00:10:00Z"):
    return {
        "route": route,
        "target": target,
        "session_id": f"session-{identifier}",
        "agent_id": f"agent-{identifier}",
        "agent_type": f"{route}-agent",
        "agent_name": f"{route}-agent",
        "spawn_time": "2026-08-22T00:00:00Z",
        "worktree": f"/tmp/{identifier}",
        "chain_depth": depth,
        "finish_time": finish_time,
        "outcome": "published" if finish_time else "",
    }

rows = [
    bound("issue-repeat-below", "code-review", 1, "repeat-below-1"),
    bound("issue-repeat-below", "code-review", 2, "repeat-below-2"),
    *(bound("issue-repeat-limit", "code-review", depth, f"repeat-limit-{depth}")
      for depth in range(1, 4)),
    *(bound(
        "issue-depth-below",
        ("implement", "code-review", "research", "push", "resolving-merge-conflicts")[
            (depth - 1) % 5
        ],
        depth,
        f"depth-below-{depth}",
    ) for depth in range(1, 8)),
    *(bound(
        "issue-depth-limit",
        ("implement", "code-review", "research", "push", "resolving-merge-conflicts")[
            (depth - 1) % 5
        ],
        depth,
        f"depth-limit-{depth}",
    ) for depth in range(1, 9)),
    bound("issue-unbound-budget", "code-review", 1, "unbound-budget"),
    {
        "route": "code-review",
        "target": "issue-unbound-budget",
        "spawn_time": "2026-08-22T00:00:00Z",
        "worktree": "/tmp/unbound-budget-reservation",
        "chain_depth": 8,
        "finish_time": "2026-08-22T00:10:00Z",
        "outcome": "published",
    },
    bound("issue-other-in-flight", "implement", 1, "other-in-flight", ""),
]

with open(ledger_path, "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

plan_ledger="$guard_ledger"
repeat_below="$(plan /code-review issue-repeat-below AFK-safe code-review-agent gpt-5.6-sol high default "$tmp_dir/plan-repeat-below")"
assert_plan "third route occurrence" "$repeat_below" \
  '{"decision":"spawn","route":"/code-review","target":"issue-repeat-below","agent":"code-review-agent","model":"gpt-5.6-sol","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-repeat-below"}'

repeat_limit="$(plan /code-review issue-repeat-limit AFK-safe code-review-agent gpt-5.6-sol high default "$tmp_dir/plan-repeat-limit")"
assert_plan "fourth route occurrence" "$repeat_limit" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"route-repetition-limit","route":"/code-review","target":"issue-repeat-limit"}'

if "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$guard_ledger" \
  --route code-review \
  --target issue-repeat-limit \
  --spawn-time 2026-08-22T00:11:00Z \
  --worktree "$tmp_dir/worktree-repeat-limit" \
  --chain-depth 4 \
  2>"$tmp_dir/repeat-limit.err"
then
  err "reserve bypassed the route repetition guard"
fi
if ! grep -q "target-halted: route-repetition-limit" "$tmp_dir/repeat-limit.err"; then
  err "reserve did not report the route repetition halt"
fi
if [ -e "$tmp_dir/worktree-repeat-limit" ]; then
  err "repetition guard created a worktree"
fi

depth_below="$(plan /research issue-depth-below AFK-safe research-agent gpt-6.1-sol high default "$tmp_dir/plan-depth-below")"
assert_plan "eighth lineage hop" "$depth_below" \
  '{"decision":"spawn","route":"/research","target":"issue-depth-below","agent":"research-agent","model":"gpt-6.1-sol","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-depth-below"}'

depth_limit="$(plan /research issue-depth-limit AFK-safe research-agent gpt-6.1-sol high default "$tmp_dir/plan-depth-limit")"
assert_plan "ninth lineage hop" "$depth_limit" \
  '{"decision":"decline","reason":"target-halted","halt_reason":"chain-depth-limit","route":"/research","target":"issue-depth-limit"}'

unbound_budget="$(plan /code-review issue-unbound-budget AFK-safe code-review-agent gpt-5.6-sol high default "$tmp_dir/plan-unbound-budget")"
assert_plan "unbound reservation is not a hop" "$unbound_budget" \
  '{"decision":"spawn","route":"/code-review","target":"issue-unbound-budget","agent":"code-review-agent","model":"gpt-5.6-sol","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-unbound-budget"}'

if ! python3 - "$guard_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

repeat = next(row for row in rows if row["target"] == "issue-repeat-limit" and row["chain_depth"] == 3)
depth = next(row for row in rows if row["target"] == "issue-depth-limit" and row["chain_depth"] == 8)
other = next(row for row in rows if row["target"] == "issue-other-in-flight")
assert repeat["outcome"] == "published"
assert repeat["halt_reason"] == "route-repetition-limit"
assert depth["outcome"] == "published"
assert depth["halt_reason"] == "chain-depth-limit"
assert other["finish_time"] == ""
assert "halt_reason" not in other
PY
then
  err "guard halt bookkeeping did not isolate the target"
fi

reserve_and_bind \
  --ledger "$complete_ledger" \
  --route implement \
  --target issue-unmatched \
  --session-id session-unmatched \
  --agent-id agent-unmatched \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-unmatched" \
  --chain-depth 3

cp "$complete_ledger" "$complete_ledger.before-unmatched"
unmatched_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-from-another-run 2026-08-22T00:11:00Z implement-agent implement-agent session-unmatched)"
)"
assert_plan "unmatched completion" "$unmatched_output" \
  '{"continue":false,"reason":"unmatched-payload","agent_id":"agent-from-another-run"}'

# Agents this chain never spawned reach the same hook, so identity still has to
# decline them. Each of these differs from the bound row in exactly one field
# the match reads.
other_session_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-unmatched 2026-08-22T00:11:00Z implement-agent implement-agent session-from-another-run)"
)"
assert_plan "completion from another session" "$other_session_output" \
  '{"continue":false,"reason":"unmatched-payload","agent_id":"agent-unmatched"}'

other_type_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-unmatched 2026-08-22T00:11:00Z code-review code-review session-unmatched)"
)"
assert_plan "completion from another agent type" "$other_type_output" \
  '{"continue":false,"reason":"unmatched-payload","agent_id":"agent-unmatched"}'

if ! cmp -s "$complete_ledger.before-unmatched" "$complete_ledger"; then
  err "unmatched completion modified the ledger"
fi

# A row bound with a descriptive agent name must be closed by the payload the
# runtime actually sends. The runtime sets `agentName` to the agent *type* and
# carries no field at all for the name the caller chose, so a match that read
# the bound name could never close such a row and every hop leaked one (#67).
#
# The payload below is captured, not constructed: it is the verbatim
# `subagentStop` hook input recorded in a real session's events.jsonl, and that
# very invocation is recorded returning `unmatched-payload` against a live
# ledger. A payload built from the same variables the test passes to `bind` is
# self-consistent by construction and cannot observe this bug at all.
captured_fixture="$REPO/scripts/fixtures/subagent-stop-hook-invocation.json"
captured_ledger="$tmp_dir/.git-loopy/captured-subagents.jsonl"
captured_worktree="$tmp_dir/worktree-captured"
# The name a caller binds after launching a descriptively named background
# agent. Taken from a row this bug left open in this repo's own ledger.
captured_bound_name="Confirm route before marking routed"

IFS=$'\t' read -r captured_session_id captured_agent_id captured_agent_type captured_agent_name <<<"$(
  python3 - "$captured_fixture" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fixture:
    event = json.load(fixture)
assert event["data"]["hookType"] == "subagentStop", event["data"]["hookType"]
payload = event["data"]["input"]
print("\t".join([
    payload["sessionId"],
    payload["agentId"],
    payload["agentType"],
    payload["agentName"],
]))
PY
)"

# Without this the test could be quietly rewritten into the self-consistent
# shape it exists to rule out.
if [ "$captured_agent_name" = "$captured_bound_name" ]; then
  err "the captured payload carries the bound name, so it cannot distinguish the two payload shapes"
fi

# The runtime reports a run under the session that launched it, so a real
# payload's session id is never the agent's own id. A capture where the two
# agreed would close the row no matter which of them `bind` recorded, and the
# documented rule that `--session-id` takes the routing session would go
# unexercised.
if [ "$captured_session_id" = "$captured_agent_id" ]; then
  err "the captured payload's session id equals its agent id, so it cannot exercise the documented bind path"
fi

reserve_and_bind \
  --ledger "$captured_ledger" \
  --route implement \
  --target issue-captured \
  --session-id "$captured_session_id" \
  --agent-id "$captured_agent_id" \
  --agent-type "$captured_agent_type" \
  --agent-name "$captured_bound_name" \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$captured_worktree" \
  --chain-depth 1

captured_payload="$(
  python3 - "$captured_fixture" "$tmp_dir" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fixture:
    payload = json.load(fixture)["data"]["input"]
# `cwd` is the only captured value rewritten, because the recorded absolute path
# belongs to the machine that produced the capture. It is repointed at this
# test's repository and not at the row's worktree, because that is the
# relationship the capture recorded: the runtime reports the launching session's
# own directory, never the reserved worktree the run worked in. A payload whose
# `cwd` were the row's worktree could be matched by directory instead of by
# identity, which is exactly what this test must not allow. Every field the
# match reads reaches `complete` exactly as the runtime sent it.
payload["cwd"] = sys.argv[2]
print(json.dumps(payload, separators=(",", ":")))
PY
)"

captured_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$captured_ledger" \
    <<< "$captured_payload"
)"
assert_plan "captured payload completion" "$captured_output" \
  '{"continue":true,"outcome":"published","target":"issue-captured"}'

if ! python3 - "$captured_ledger" "$captured_bound_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

assert len(rows) == 1, rows
assert rows[0]["finish_time"] == "2026-08-22T23:22:11Z", rows
assert rows[0]["outcome"] == "published", rows
# The bound name stays on the row: it is still what a human reads to tell one
# hop from another, it just no longer decides which row a payload closes.
assert rows[0]["agent_name"] == sys.argv[2], rows
PY
then
  err "the captured subagentStop payload did not close the row bound with a descriptive agent name"
fi

if [ -e "$captured_worktree" ]; then
  err "captured payload completion did not remove its worktree"
fi

# Real payloads from built-in agent types carry only what the runtime chooses to
# send. `complete` must require nothing beyond the fields it reads: requiring an
# unread one rejected every live completion, and the chain went silent (#41).
# `agentName` is absent below because nothing reads it any more (#67), so this
# also fails if it ever creeps back into required_fields.
minimal_payload() {
  local agent_id="$1" agent_type="$2" session_id="$3" payload_cwd="$4"
  printf '%s' '{"sessionId":"'"$session_id"'","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$payload_cwd"'","agentId":"'"$agent_id"'","agentType":"'"$agent_type"'"}'
}

minimal_ledger="$tmp_dir/.git-loopy/minimal-subagents.jsonl"
reserve_and_bind \
  --ledger "$minimal_ledger" \
  --route implement \
  --target issue-minimal \
  --session-id session-minimal \
  --agent-id agent-minimal \
  --agent-type code-review \
  --agent-name code-review \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-minimal" \
  --chain-depth 1

minimal_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$minimal_ledger" \
    <<< "$(minimal_payload agent-minimal code-review session-minimal "$tmp_dir")"
)"
assert_plan "minimal completion" "$minimal_output" \
  '{"continue":true,"outcome":"published","target":"issue-minimal"}'

if ! python3 - "$minimal_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

assert len(rows) == 1, rows
assert rows[0]["finish_time"] == "2026-08-22T00:11:00Z", rows
assert rows[0]["outcome"] == "published", rows
assert not rows[0].get("routed"), rows
PY
then
  err "a payload carrying only the fields complete reads did not close its ledger row"
fi

# Every field the runtime may add is optional, including ones no release has sent
# yet: a conditional field must never be able to stop the chain again.
optional_ledger="$tmp_dir/.git-loopy/optional-subagents.jsonl"
reserve_and_bind \
  --ledger "$optional_ledger" \
  --route implement \
  --target issue-optional \
  --session-id session-optional \
  --agent-id agent-optional \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-optional" \
  --chain-depth 1

optional_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$optional_ledger" \
    <<< '{"sessionId":"session-optional","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'","transcriptPath":"'"$tmp_dir"'/transcript.jsonl","agentId":"agent-optional","agentType":"implement-agent","agentName":"implement-agent","agentDisplayName":"Implement agent","response":"Completed the route.","stopReason":"end_turn","permissionMode":"default","unreleasedFutureField":{"nested":[1,2,3]}}'
)"
assert_plan "every-optional-field completion" "$optional_output" \
  '{"continue":true,"outcome":"published","target":"issue-optional"}'

# The fields that remain required are exactly the ones complete reads, and each
# is still named when it is absent.
required_ledger="$tmp_dir/.git-loopy/required-subagents.jsonl"
reserve_and_bind \
  --ledger "$required_ledger" \
  --route implement \
  --target issue-required \
  --session-id session-required \
  --agent-id agent-required \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-required" \
  --chain-depth 1
cp "$required_ledger" "$required_ledger.before-missing"

payload_without() {
  python3 -c '
import json
import sys

payload = json.loads(sys.argv[1])
del payload[sys.argv[2]]
print(json.dumps(payload, separators=(",", ":")))
' "$1" "$2"
}

required_payload="$(completion_payload agent-required 2026-08-22T00:11:00Z implement-agent implement-agent session-required)"
for required_field in sessionId timestamp cwd agentId agentType; do
  missing_error="$tmp_dir/missing-$required_field.err"
  if PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
    --ledger "$required_ledger" \
    <<< "$(payload_without "$required_payload" "$required_field")" \
    >/dev/null 2>"$missing_error"
  then
    err "complete accepted a payload missing $required_field"
  fi
  if ! grep -q "subagent-stop payload is missing $required_field" "$missing_error"; then
    err "complete did not name the missing $required_field"
  fi
done

if ! cmp -s "$required_ledger.before-missing" "$required_ledger"; then
  err "a payload missing a required field modified the ledger"
fi
if [ -e "$required_ledger.lock" ]; then
  err "a rejected payload left the ledger lock behind"
fi

# The whole point of closing the row: agentStop must then find it unrouted, or
# the chain does nothing and reports nothing wrong.
reentry_repo="$tmp_dir/reentry-repository"
git init --quiet "$reentry_repo"
git -C "$reentry_repo" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m initial
(
  cd "$reentry_repo"
  reserve_and_bind \
    --route implement \
    --target issue-reentry \
    --session-id session-reentry \
    --agent-id agent-reentry \
    --agent-type code-review \
    --agent-name code-review \
    --spawn-time 2026-08-22T00:00:00Z \
    --worktree "$reentry_repo/worktree-reentry" \
    --chain-depth 1
)

reentry_output="$(
  cd "$reentry_repo"
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
    <<< "$(minimal_payload agent-reentry code-review session-reentry "$reentry_repo")"
)"
assert_plan "re-entry completion" "$reentry_output" \
  '{"continue":true,"outcome":"published","target":"issue-reentry"}'

reentry_decision="$(
  python3 "$REPO/skills/setup-git-loopy-skills/git-loopy-agent-stop.py" \
    <<< '{"cwd":"'"$reentry_repo"'","timestamp":"2026-08-22T00:12:00Z","stop_hook_active":false}'
)"
if [ "$reentry_decision" != '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","targets":["issue-reentry"]}' ]; then
  err "agentStop did not see a real completion as an unrouted run"
fi

recovery_ledger="$tmp_dir/recovery-subagents.jsonl"
plan_ledger="$recovery_ledger"
stale_worktree="$tmp_dir/worktree-stale"
reserve_and_bind \
  --ledger "$recovery_ledger" \
  --route implement \
  --target issue-stale \
  --session-id session-stale \
  --agent-id agent-stale \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2015-01-01T00:00:00Z \
  --worktree "$stale_worktree" \
  --chain-depth 4

if [ ! -e "$stale_worktree" ]; then
  err "stale fixture did not create its worktree"
fi

stale_target="$(plan /implement issue-stale AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-stale")"
assert_plan "stale target before recovery" "$stale_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/implement","target":"issue-stale"}'

recovery_output="$("$CHAIN" recover --ledger "$recovery_ledger" --stale-after-seconds 1 --now 2026-08-22T00:05:00Z)"
assert_plan "old in-flight run recovery" "$recovery_output" \
  '{"recovered":0,"targets":[]}'

aggressive_recovery_output="$("$CHAIN" recover --ledger "$recovery_ledger" --stale-after-seconds 0 --now 2026-08-22T00:05:00Z)"
assert_plan "zero-threshold in-flight run recovery" "$aggressive_recovery_output" \
  '{"recovered":0,"targets":[]}'

if [ ! -e "$stale_worktree" ]; then
  err "recovery disturbed an in-flight run whose parent is alive"
fi

if ! python3 - "$recovery_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == "session-stale")
assert row["finish_time"] == ""
assert row["outcome"] == ""
assert "reclaimed_at" not in row
PY
then
  err "recovery modified an in-flight run whose parent is alive"
fi

recovered_target="$(plan /implement issue-stale AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-recovered")"
assert_plan "target after recovery" "$recovered_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/implement","target":"issue-stale"}'

abandoned_run_ledger="$tmp_dir/.git-loopy/abandoned-run-subagents.jsonl"
abandoned_run_worktree="$tmp_dir/worktree-abandoned-run"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-abandoned-run \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 --parent-pid "$$"
  "$1" bind --ledger "$2" --worktree "$3" --session-id session-abandoned-run \
    --agent-id agent-abandoned-run --agent-type implement-agent --agent-name implement-agent
' bash "$CHAIN" "$abandoned_run_ledger" "$abandoned_run_worktree"

abandoned_run_output="$("$CHAIN" recover --ledger "$abandoned_run_ledger" \
  --stale-after-seconds 86400 --now 2026-08-22T00:00:01Z)"
assert_plan "abandoned run recovery" "$abandoned_run_output" \
  '{"recovered":1,"targets":["issue-abandoned-run"]}'
if [ -e "$abandoned_run_worktree" ]; then
  err "recovery did not release an abandoned run's worktree"
fi
if ! python3 - "$abandoned_run_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["agent_id"] == "agent-abandoned-run"
assert row["finish_time"] == "2026-08-22T00:00:01Z"
assert row["outcome"] == "reclaimed"
assert row["reclaimed_at"] == "2026-08-22T00:00:01Z"
PY
then
  err "abandoned run recovery was not recorded as reclaimed"
fi

reused_pid_run_ledger="$tmp_dir/.git-loopy/reused-pid-run-subagents.jsonl"
reused_pid_run_worktree="$tmp_dir/worktree-reused-pid-run"
reserve_and_bind \
  --ledger "$reused_pid_run_ledger" \
  --route implement \
  --target issue-reused-pid-run \
  --session-id session-reused-pid-run \
  --agent-id agent-reused-pid-run \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$reused_pid_run_worktree" \
  --chain-depth 1
python3 - "$reused_pid_run_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
row["parent_start"] = "Mon Jan 01 00:00:00 2001"
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

reused_pid_output="$("$CHAIN" recover --ledger "$reused_pid_run_ledger" \
  --stale-after-seconds 999999999 --now 2026-08-22T00:00:01Z)"
assert_plan "reused parent pid abandoned run recovery" "$reused_pid_output" \
  '{"recovered":1,"targets":["issue-reused-pid-run"]}'
if [ -e "$reused_pid_run_worktree" ]; then
  err "recovery did not reclaim an abandoned run after parent pid reuse"
fi

unknown_parent_run_ledger="$tmp_dir/.git-loopy/unknown-parent-run-subagents.jsonl"
unknown_parent_run_worktree="$tmp_dir/worktree-unknown-parent-run"
reserve_and_bind \
  --ledger "$unknown_parent_run_ledger" \
  --route implement \
  --target issue-unknown-parent-run \
  --session-id session-unknown-parent-run \
  --agent-id agent-unknown-parent-run \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2015-01-01T00:00:00Z \
  --worktree "$unknown_parent_run_worktree" \
  --chain-depth 1
python3 - "$unknown_parent_run_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
del row["parent_pid"]
del row["parent_start"]
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

unknown_parent_output="$("$CHAIN" recover --ledger "$unknown_parent_run_ledger" \
  --stale-after-seconds 0 --now 2026-08-22T00:00:01Z)"
assert_plan "unknown-parent run recovery" "$unknown_parent_output" \
  '{"recovered":0,"targets":[]}'
if [ ! -e "$unknown_parent_run_worktree" ]; then
  err "recovery reclaimed a run without proof its parent was gone"
fi

dirty_abandoned_run_ledger="$tmp_dir/.git-loopy/dirty-abandoned-run-subagents.jsonl"
dirty_abandoned_run_worktree="$tmp_dir/worktree-dirty-abandoned-run"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-dirty-abandoned-run \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 --parent-pid "$$"
  "$1" bind --ledger "$2" --worktree "$3" --session-id session-dirty-abandoned-run \
    --agent-id agent-dirty-abandoned-run --agent-type implement-agent --agent-name implement-agent
' bash "$CHAIN" "$dirty_abandoned_run_ledger" "$dirty_abandoned_run_worktree"
printf 'uncommitted recovery work\n' > "$dirty_abandoned_run_worktree/uncommitted.txt"

dirty_abandoned_run_error="$tmp_dir/dirty-abandoned-run.err"
dirty_abandoned_run_output="$("$CHAIN" recover --ledger "$dirty_abandoned_run_ledger" \
  --stale-after-seconds 999999999 --now 2026-08-22T00:00:01Z \
  2>"$dirty_abandoned_run_error")"
assert_plan "dirty abandoned run recovery" "$dirty_abandoned_run_output" \
  '{"recovered":1,"targets":["issue-dirty-abandoned-run"],"retained_worktrees":["'"$dirty_abandoned_run_worktree"'"]}'
if [ ! -f "$dirty_abandoned_run_worktree/uncommitted.txt" ]; then
  err "recovery destroyed an uncommitted file in a reclaimed worktree"
fi
if ! grep -q \
  "worktree has uncommitted changes and was retained: $dirty_abandoned_run_worktree" \
  "$dirty_abandoned_run_error"
then
  err "recovery did not report the retained dirty worktree"
fi
if ! python3 - "$dirty_abandoned_run_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["finish_time"] == "2026-08-22T00:00:01Z"
assert row["outcome"] == "reclaimed"
assert row["reclaimed_at"] == "2026-08-22T00:00:01Z"
PY
then
  err "dirty worktree recovery did not release the ledger slot"
fi

plan_ledger="$abandoned_run_ledger"
reclaimed_abandoned_target="$(plan /implement issue-abandoned-run AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-abandoned-run")"
assert_plan "reclaimed abandoned run target" "$reclaimed_abandoned_target" \
  '{"decision":"spawn","route":"/implement","target":"issue-abandoned-run","agent":"implement-agent","model":"gpt-5.6-terra","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-abandoned-run"}'

orphan_ledger="$tmp_dir/.git-loopy/orphan-subagents.jsonl"
orphan_worktree="$tmp_dir/worktree-orphan"
"$CHAIN" reserve --parent-pid "$$" \
  --ledger "$orphan_ledger" \
  --route implement \
  --target issue-orphan \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$orphan_worktree" \
  --chain-depth 1

live_parent_output="$("$CHAIN" recover --ledger "$orphan_ledger" --stale-after-seconds 60 --now 2026-08-22T00:00:30Z)"
assert_plan "live parent before timeout" "$live_parent_output" \
  '{"recovered":0,"targets":[]}'
if [ ! -e "$orphan_worktree" ]; then
  err "recovery removed a live parent's reservation before its timeout"
fi

timeout_output="$("$CHAIN" recover --ledger "$orphan_ledger" --stale-after-seconds 60 --now 2026-08-22T00:05:00Z)"
assert_plan "live parent timeout" "$timeout_output" \
  '{"recovered":1,"targets":["issue-orphan"]}'
if [ -e "$orphan_worktree" ]; then
  err "recovery did not release the timed-out reservation worktree"
fi
if ! python3 - "$orphan_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["finish_time"] == "2026-08-22T00:05:00Z"
assert row["outcome"] == "reclaimed"
assert row["reclaimed_at"] == "2026-08-22T00:05:00Z"
PY
then
  err "timeout recovery did not distinguish the reclaimed reservation"
fi

dead_parent_ledger="$tmp_dir/.git-loopy/dead-parent-subagents.jsonl"
dead_parent_worktree="$tmp_dir/worktree-dead-parent"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-dead-parent \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 --parent-pid "$$"
  :
' bash "$CHAIN" "$dead_parent_ledger" "$dead_parent_worktree"
dead_parent_output="$("$CHAIN" recover --ledger "$dead_parent_ledger" --stale-after-seconds 3600 --now 2026-08-22T00:00:01Z)"
assert_plan "dead parent recovery" "$dead_parent_output" \
  '{"recovered":1,"targets":["issue-dead-parent"]}'
if [ -e "$dead_parent_worktree" ]; then
  err "recovery did not release a dead parent's reservation worktree"
fi

# The routing agent reaches `reserve` through a shell that exits with the command,
# so the invoking process is never the one whose death orphans the reservation.
# The reserving parent is the session that will bind the run, and only the caller
# knows which process that is.
named_parent_ledger="$tmp_dir/.git-loopy/named-parent-subagents.jsonl"
named_parent_worktree="$tmp_dir/worktree-named-parent"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-named-parent \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 \
    --parent-pid "$4"
  exit $?
' bash "$CHAIN" "$named_parent_ledger" "$named_parent_worktree" "$$"
named_parent_output="$("$CHAIN" recover --ledger "$named_parent_ledger" \
  --stale-after-seconds 3600 --now 2026-08-22T00:00:01Z)"
assert_plan "reservation owned by a live parent" "$named_parent_output" \
  '{"recovered":0,"targets":[]}'
if [ ! -e "$named_parent_worktree" ]; then
  err "recovery reclaimed a live parent's reservation made through a transient shell"
fi

# Falling back to the invoking shell would put every reservation under a process
# that is already gone, so a caller that names no parent is refused outright
# rather than given one that cannot answer for it.
unnamed_parent_ledger="$tmp_dir/.git-loopy/unnamed-parent-subagents.jsonl"
unnamed_parent_worktree="$tmp_dir/worktree-unnamed-parent"
if "$CHAIN" reserve \
  --ledger "$unnamed_parent_ledger" \
  --route implement \
  --target issue-unnamed-parent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$unnamed_parent_worktree" \
  --chain-depth 1 2>/dev/null
then
  err "reserve accepted a reservation that named no parent"
fi
if [ -e "$unnamed_parent_ledger" ]; then
  err "reserve recorded a reservation that named no parent"
fi
if [ -e "$unnamed_parent_worktree" ]; then
  err "reserve created a worktree for a reservation that named no parent"
fi

# A parent that has already exited orphans its reservation the moment it is
# written, so it is refused at reserve rather than left for recovery to sweep.
gone_parent_ledger="$tmp_dir/.git-loopy/gone-parent-subagents.jsonl"
gone_parent_worktree="$tmp_dir/worktree-gone-parent"
if "$CHAIN" reserve \
  --ledger "$gone_parent_ledger" \
  --route implement \
  --target issue-gone-parent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$gone_parent_worktree" \
  --chain-depth 1 \
  --parent-pid 999999 2>/dev/null
then
  err "reserve accepted a parent that is not running"
fi
if [ -e "$gone_parent_ledger" ]; then
  err "reserve recorded a reservation whose parent was already gone"
fi
if [ -e "$gone_parent_worktree" ]; then
  err "reserve created a worktree for a reservation whose parent was already gone"
fi

automatic_ledger="$tmp_dir/.git-loopy/automatic-recovery-subagents.jsonl"
automatic_worktree="$tmp_dir/worktree-automatic-recovery"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-automatic-recovery \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 --parent-pid "$$"
  :
' bash "$CHAIN" "$automatic_ledger" "$automatic_worktree"
automatic_output="$(
  CHAIN_MAX_CONCURRENCY=1 CHAIN_RESERVATION_STALE_SECONDS=3600 "$CHAIN" plan \
    --ledger "$automatic_ledger" \
    --route /implement \
    --target issue-automatic-candidate \
    --safety AFK-safe \
    --agent implement-agent \
    --model gpt-5.6-terra \
    --effort high \
    --context-tier default \
    --worktree "$tmp_dir/worktree-automatic-candidate"
)"
assert_plan "automatic orphan recovery before planning" "$automatic_output" \
  '{"decision":"spawn","route":"/implement","target":"issue-automatic-candidate","agent":"implement-agent","model":"gpt-5.6-terra","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/worktree-automatic-candidate"}'
if [ -e "$automatic_worktree" ]; then
  err "plan did not reclaim the dead parent's worktree before checking capacity"
fi

concurrent_ledger="$tmp_dir/.git-loopy/concurrent-recovery-subagents.jsonl"
concurrent_worktree="$tmp_dir/worktree-concurrent-recovery"
bash -c '
  "$1" reserve --ledger "$2" --route implement --target issue-concurrent-recovery \
    --spawn-time 2026-08-22T00:00:00Z --worktree "$3" --chain-depth 1 --parent-pid "$$"
  :
' bash "$CHAIN" "$concurrent_ledger" "$concurrent_worktree"
"$CHAIN" recover --ledger "$concurrent_ledger" --stale-after-seconds 3600 \
  --now 2026-08-22T00:00:01Z > "$tmp_dir/recover-one.json" &
recover_one_pid=$!
"$CHAIN" recover --ledger "$concurrent_ledger" --stale-after-seconds 3600 \
  --now 2026-08-22T00:00:01Z > "$tmp_dir/recover-two.json" &
recover_two_pid=$!
wait "$recover_one_pid"
wait "$recover_two_pid"
if ! python3 - "$tmp_dir/recover-one.json" "$tmp_dir/recover-two.json" "$concurrent_ledger" <<'PY'
import json
import sys

results = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:3]]
assert sorted(result["recovered"] for result in results) == [0, 1], results
with open(sys.argv[3], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
assert len(rows) == 1, rows
assert rows[0]["outcome"] == "reclaimed", rows
PY
then
  err "concurrent reclaimers did not leave one reclaimed reservation"
fi
if [ -e "$concurrent_worktree" ]; then
  err "concurrent reclaimers left the reclaimed worktree behind"
fi

reservation_ledger="$tmp_dir/.git-loopy/reservation-crash.jsonl"
CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE=30 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$reservation_ledger" \
  --route implement \
  --target issue-reservation-crash \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-reservation-crash" \
  --chain-depth 1 &
reservation_crash_pid=$!
reservation_recorded=0
reservation_deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$reservation_deadline" ]; do
  if [ -f "$reservation_ledger.pending" ]; then
    reservation_recorded=1
    break
  fi
  kill -0 "$reservation_crash_pid" 2>/dev/null || break
  sleep 0.01
done
kill -KILL "$reservation_crash_pid" 2>/dev/null || true
wait "$reservation_crash_pid" 2>/dev/null || true
if [ "$reservation_recorded" -eq 0 ]; then
  err "reservation crash fixture did not record its pending reservation"
fi

if [ -e "$reservation_ledger" ]; then
  err "reservation crash fixture published a reservation row before its worktree"
fi
if [ -e "$tmp_dir/worktree-reservation-crash" ]; then
  err "reservation crash fixture created its worktree before the test could interrupt it"
fi

reservation_recovery="$("$CHAIN" recover --ledger "$reservation_ledger" --stale-after-seconds 60 --now 2026-08-22T00:05:00Z)"
assert_plan "uncommitted reservation recovery" "$reservation_recovery" \
  '{"recovered":0,"targets":[]}'
if [ -e "$reservation_ledger.pending" ]; then
  err "recovery left the pending record of an uncommitted reservation behind"
fi
if [ -e "$tmp_dir/worktree-reservation-crash" ]; then
  err "recovery left an uncommitted reservation worktree behind"
fi

lock_crash_ledger="$tmp_dir/.git-loopy/lock-crash.jsonl"
lock_crash_worktree="$tmp_dir/worktree-lock-crash"
CHAIN_RESERVE_PAUSE_BEFORE_COMMIT=1 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$lock_crash_ledger" \
  --route implement \
  --target issue-lock-crash \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$lock_crash_worktree" \
  --chain-depth 1 &
lock_crash_pid=$!
for _ in $(seq 1 500); do
  [ -f "$lock_crash_worktree/.git-loopy/worktree-owner" ] && break
  sleep 0.01
done
if [ ! -f "$lock_crash_worktree/.git-loopy/worktree-owner" ]; then
  err "SIGKILL recovery fixture did not reach its marked worktree"
else
  kill -KILL "$lock_crash_pid"
  wait "$lock_crash_pid" 2>/dev/null || true
fi

if [ ! -d "$lock_crash_ledger.lock" ]; then
  err "SIGKILL did not leave the ledger lock behind"
fi
if [ -e "$lock_crash_ledger" ]; then
  err "SIGKILL published a reservation row past its commit point"
fi
if [ ! -f "$lock_crash_ledger.pending" ]; then
  err "SIGKILL did not leave the pending record of its marked worktree behind"
fi

reserve_and_bind \
  --ledger "$lock_crash_ledger" \
  --route code-review \
  --target issue-after-lock-crash \
  --session-id session-after-lock-crash \
  --agent-id agent-after-lock-crash \
  --agent-type code-review-agent \
  --agent-name code-review-agent \
  --spawn-time 2026-08-22T00:01:00Z \
  --worktree "$tmp_dir/worktree-after-lock-crash" \
  --chain-depth 1

if [ -e "$lock_crash_ledger.lock" ]; then
  err "reserve did not recover the SIGKILL-stranded ledger lock"
fi
if [ -e "$lock_crash_worktree" ]; then
  err "reserve did not roll back the marked worktree of an uncommitted reservation"
fi
if [ -e "$lock_crash_ledger.pending" ]; then
  err "reserve did not clear the pending record of an uncommitted reservation"
fi
if ! python3 - "$lock_crash_ledger" "$lock_crash_worktree" <<'PY'
import json
import sys

ledger_path, rolled_back = sys.argv[1:]
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
assert [row["target"] for row in rows] == ["issue-after-lock-crash"], rows
assert all(row["worktree"] != rolled_back for row in rows), rows
PY
then
  err "a SIGKILL before the commit point left a reservation row behind"
fi

# A SIGKILL in the other half of the window — after the row is published but
# before the pending record is cleared — must keep the reservation, not undo it.
python3 - "$tmp_dir/worktree-after-lock-crash" "$lock_crash_ledger" > "$lock_crash_ledger.pending" <<'PY'
import json
import sys

worktree, ledger_path = sys.argv[1:]
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
committed = next(row for row in rows if row["worktree"] == worktree)
print(json.dumps({
    "worktree": worktree,
    "branch": "no-such-branch",
    "commit": "row",
    "reservation_id": committed["reservation_id"],
}, separators=(",", ":")))
PY
"$CHAIN" recover --ledger "$lock_crash_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T00:02:00Z >/dev/null
if [ -e "$lock_crash_ledger.pending" ]; then
  err "recovery left the pending record of a committed reservation behind"
fi
if [ ! -f "$tmp_dir/worktree-after-lock-crash/.git-loopy/worktree-owner" ]; then
  err "recovery rolled back a reservation that had already committed"
fi

# A retry that reuses every reserve argument: only the reservation's own id tells
# the new transaction from the row the previous one left, so the unrecorded
# worktree must still go.
reuse_worktree="$tmp_dir/worktree-after-lock-crash"
git -C "$tmp_dir" worktree remove --force "$reuse_worktree"
git -C "$tmp_dir" worktree add --quiet -b reused-path "$reuse_worktree" >/dev/null
"$CHAIN" claim --worktree "$reuse_worktree" --owner-pid "$$"
python3 - "$reuse_worktree" "$lock_crash_ledger" > "$lock_crash_ledger.pending" <<'PY'
import json
import sys

worktree, ledger_path = sys.argv[1:]
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
committed = next(row for row in rows if row["worktree"] == worktree)
print(json.dumps({
    "worktree": worktree,
    "branch": "reused-path",
    "commit": "row",
    "reservation_id": "0" * 32,
}, separators=(",", ":")))
PY
"$CHAIN" recover --ledger "$lock_crash_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T09:01:00Z >/dev/null
if [ -e "$reuse_worktree" ]; then
  err "a retry that reused every reserve argument was mistaken for its own commit"
fi
if git -C "$tmp_dir" rev-parse --verify --quiet reused-path >/dev/null; then
  err "rolling back an uncommitted reservation left its branch behind"
fi

# A rollback that cannot remove the worktree must keep its record, because
# dropping it would leave nothing naming the directory it failed to remove.
stuck_dir="$tmp_dir/worktree-unremovable"
mkdir -p "$stuck_dir"
python3 - "$stuck_dir" > "$lock_crash_ledger.pending" <<'PY'
import json
import sys

print(json.dumps({
    "worktree": sys.argv[1],
    "branch": "",
    "commit": "row",
    "reservation_id": "f" * 32,
}, separators=(",", ":")))
PY
if "$CHAIN" recover --ledger "$lock_crash_ledger" --stale-after-seconds 999999999 \
  --now 2026-08-22T10:00:00Z >/dev/null 2>&1
then
  err "recovery reported success after failing to remove an unrecorded worktree"
fi
if [ ! -f "$lock_crash_ledger.pending" ]; then
  err "a failed rollback dropped the record of the worktree it could not remove"
fi
if [ -e "$lock_crash_ledger.lock" ]; then
  err "a failed rollback stranded the ledger lock"
fi
rm -f "$lock_crash_ledger.pending"
rmdir "$stuck_dir"

# An unreadable record is not a committed one. Keep it and fail, rather than
# dropping the last thing naming whatever worktree it described.
for unreadable in \
  'not json' \
  '[]' \
  '{"worktree":"/tmp/x","commit":"row"}' \
  '{"worktree":"/tmp/x","commit":"nonsense"}' \
  '{"worktree":"/tmp/x","branch":5,"commit":"marker"}' \
  '{"worktree":"/tmp/x","branch":0,"commit":"marker"}' \
  '{"worktree":"/tmp/x","branch":false,"commit":"marker"}' \
  '{"worktree":"/tmp/x","branch":[],"commit":"marker"}' \
  '{"worktree":"/tmp/x","branch":null,"commit":"marker"}' \
  '{"worktree":"/tmp/x","branch":"","commit":"row","reservation_id":7}' \
  '{"commit":"marker"}'
do
  printf '%s\n' "$unreadable" > "$lock_crash_ledger.pending"
  if "$CHAIN" recover --ledger "$lock_crash_ledger" --stale-after-seconds 999999999 \
    --now 2026-08-22T11:00:00Z >/dev/null 2>&1
  then
    err "recovery reported success on an unreadable pending worktree record"
  fi
  if [ ! -f "$lock_crash_ledger.pending" ]; then
    err "an unreadable pending worktree record was deleted as though it had committed"
  fi
  if [ -e "$lock_crash_ledger.lock" ]; then
    err "an unreadable pending worktree record stranded the ledger lock"
  fi
done
rm -f "$lock_crash_ledger.pending"

# A ledger the sweep cannot read is unreadable state too, not proof of a commit.
unreadable_ledger="$tmp_dir/.git-loopy/unreadable.jsonl"
for bad_row in '["not","a","row"]' '{"reservation_id":7}' 'not json'; do
  printf '%s\n' "$bad_row" > "$unreadable_ledger"
  printf '{"worktree":"/tmp/x","branch":"","commit":"row","reservation_id":"%s"}\n' "$(printf 'a%.0s' $(seq 32))" \
    > "$unreadable_ledger.pending"
  if "$CHAIN" recover --ledger "$unreadable_ledger" --stale-after-seconds 999999999 \
    --now 2026-08-22T12:00:00Z >/dev/null 2>&1
  then
    err "recovery reported success while the ledger it swept could not be read"
  fi
  if [ ! -f "$unreadable_ledger.pending" ]; then
    err "an unreadable ledger caused its pending worktree record to be deleted"
  fi
done
rm -f "$unreadable_ledger" "$unreadable_ledger.pending"

pidless_lock_ledger="$tmp_dir/.git-loopy/pidless-lock.jsonl"
mkdir -p "$pidless_lock_ledger.lock"
CHAIN_LOCK_STALE_SECONDS=0 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$pidless_lock_ledger" \
  --route implement \
  --target issue-pidless-lock \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-pidless-lock" \
  --chain-depth 1

if [ -e "$pidless_lock_ledger.lock" ]; then
  err "reserve did not recover the PID-less stale ledger lock"
fi

recovery_lock_ledger="$tmp_dir/.git-loopy/recovery-lock.jsonl"
mkdir -p "$recovery_lock_ledger.lock.recovery"
printf '999999\tstale process\n' > "$recovery_lock_ledger.lock.recovery/pid"
reserve_and_bind \
  --ledger "$recovery_lock_ledger" \
  --route implement \
  --target issue-recovery-lock \
  --session-id session-recovery-lock \
  --agent-id agent-recovery-lock \
  --agent-type implement-agent \
  --agent-name implement-agent \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-recovery-lock" \
  --chain-depth 1

if [ -e "$recovery_lock_ledger.lock.recovery" ]; then
  err "reserve did not recover the stranded reclamation lock"
fi

if [ "$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /')" != "$parent_worktrees_before" ]; then
  err "chain tests modified the parent repository worktree registry"
fi

exit "$fail"
