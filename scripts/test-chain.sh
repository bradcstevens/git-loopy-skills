#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHAIN="$REPO/skills/next/chain.sh"
tmp_dir="$(python3 -c 'import os; import sys; print(os.path.realpath(sys.argv[1]))' "$(mktemp -d)")"
fail=0

err() {
  echo "error: $1" >&2
  fail=1
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

timezone_stable_start="$(TZ=UTC ps -o lstart= -p "$$" | xargs)"
if [ "$(TZ=America/Denver python3 "$REPO/skills/next/claim-recovery.py" owner-gone "$$" "$timezone_stable_start")" != "false" ]; then
  err "claim recovery treated a live parent as gone after a timezone change"
fi

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
  err "claim --create-branch left its journal or lock behind"
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
  err "a failed claim --create-branch left its journal behind"
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
  err "a refused claim --create-branch left its journal behind"
fi
git -C "$tmp_dir" worktree remove --force "$bystander_worktree"
git -C "$tmp_dir" branch -D bystander >/dev/null

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

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

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
chmod +x "$fake_bin/gh"

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

depth_below="$(plan /research issue-depth-below AFK-safe research-agent claude-opus-5 high default "$tmp_dir/plan-depth-below")"
assert_plan "eighth lineage hop" "$depth_below" \
  '{"decision":"spawn","route":"/research","target":"issue-depth-below","agent":"research-agent","model":"claude-opus-5","effort":"high","context_tier":"default","worktree":"'"$tmp_dir"'/plan-depth-below"}'

depth_limit="$(plan /research issue-depth-limit AFK-safe research-agent claude-opus-5 high default "$tmp_dir/plan-depth-limit")"
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
    <<< "$(completion_payload agent-unmatched 2026-08-22T00:11:00Z wrong-agent implement-agent session-unmatched)"
)"
assert_plan "unmatched completion" "$unmatched_output" \
  '{"continue":false,"reason":"unmatched-payload","agent_id":"agent-unmatched"}'

if ! cmp -s "$complete_ledger.before-unmatched" "$complete_ledger"; then
  err "unmatched completion modified the ledger"
fi

# Real payloads from built-in agent types carry only what the runtime chooses to
# send. `complete` must require nothing beyond the fields it reads: requiring an
# unread one rejected every live completion, and the chain went silent (#41).
minimal_payload() {
  local agent_id="$1" agent_type="$2" agent_name="$3" session_id="$4" payload_cwd="$5"
  printf '%s' '{"sessionId":"'"$session_id"'","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$payload_cwd"'","agentId":"'"$agent_id"'","agentType":"'"$agent_type"'","agentName":"'"$agent_name"'"}'
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
    <<< "$(minimal_payload agent-minimal code-review code-review session-minimal "$tmp_dir")"
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
for required_field in sessionId timestamp cwd agentId agentType agentName; do
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
    <<< "$(minimal_payload agent-reentry code-review code-review session-reentry "$reentry_repo")"
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
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$stale_worktree" \
  --chain-depth 4

if [ ! -e "$stale_worktree" ]; then
  err "stale fixture did not create its worktree"
fi

stale_target="$(plan /implement issue-stale AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-stale")"
assert_plan "stale target before recovery" "$stale_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/implement","target":"issue-stale"}'

recovery_output="$("$CHAIN" recover --ledger "$recovery_ledger" --stale-after-seconds 60 --now 2026-08-22T00:05:00Z)"
assert_plan "bound run recovery" "$recovery_output" \
  '{"recovered":0,"targets":[]}'

if [ ! -e "$stale_worktree" ]; then
  err "recovery disturbed the bound run worktree"
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
  err "recovery modified a bound run"
fi

recovered_target="$(plan /implement issue-stale AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-recovered")"
assert_plan "target after recovery" "$recovered_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/implement","target":"issue-stale"}'

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
CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE=1 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$reservation_ledger" \
  --route implement \
  --target issue-reservation-crash \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-reservation-crash" \
  --chain-depth 1 &
reservation_crash_pid=$!
for _ in $(seq 1 500); do
  [ -f "$reservation_ledger.pending" ] && break
  sleep 0.01
done
if [ ! -f "$reservation_ledger.pending" ]; then
  err "reservation crash fixture did not record its pending reservation"
else
  kill -KILL "$reservation_crash_pid"
  wait "$reservation_crash_pid" 2>/dev/null || true
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
