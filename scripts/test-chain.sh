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

# Identity is itself conditional. Of the 824 real `subagentStop` invocations
# recorded on the machine that produced these fixtures, 502 carry neither
# `agentId` nor `agentType`, and the two are perfectly correlated: a payload has
# both or neither. Requiring either rejected 61% of live traffic at exit 2,
# before any match ran, so those rows could never close (#70).
#
# The payload below is captured for the same reason the one above is: a test
# that builds its own payload cannot observe a shape the runtime sends and the
# code does not expect.
no_identity_fixture="$REPO/scripts/fixtures/subagent-stop-hook-invocation-without-identity.json"
no_identity_ledger="$tmp_dir/.git-loopy/no-identity-subagents.jsonl"
no_identity_worktree="$tmp_dir/worktree-no-identity"
# Bound descriptively, so this also fails if the fallback ever reads the bound
# name instead of the agent type the runtime sends as `agentName` (#67).
no_identity_bound_name="Review the tiered predicate"

IFS=$'\t' read -r no_identity_session_id no_identity_agent_name no_identity_fields <<<"$(
  python3 - "$no_identity_fixture" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fixture:
    event = json.load(fixture)
assert event["data"]["hookType"] == "subagentStop", event["data"]["hookType"]
payload = event["data"]["input"]
print("\t".join([
    payload["sessionId"],
    payload["agentName"],
    ",".join(sorted(payload)),
]))
PY
)"

# Without this the fixture could be quietly rewritten into the shape it exists
# to rule out, and the fallback tier would go untested behind a passing suite.
if [[ ",$no_identity_fields," == *,agentId,* || ",$no_identity_fields," == *,agentType,* ]]; then
  err "the no-identity fixture carries an identity field, so it cannot exercise the fallback tier"
fi
if [ "$no_identity_agent_name" = "$no_identity_bound_name" ]; then
  err "the no-identity fixture carries the bound name, so it cannot distinguish the two from each other"
fi

reserve_and_bind \
  --ledger "$no_identity_ledger" \
  --route implement \
  --target issue-no-identity \
  --session-id "$no_identity_session_id" \
  --agent-id agent-no-identity \
  --agent-type "$no_identity_agent_name" \
  --agent-name "$no_identity_bound_name" \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$no_identity_worktree" \
  --chain-depth 1

# Every captured field the fallback reads reaches `complete` exactly as the
# runtime sent it, except `cwd`: the recorded absolute path belongs to the
# machine that produced the capture. It is repointed at the row's worktree
# because that is the clause under test — the fallback correlates by the
# directory the payload reports. The with-identity capture above is deliberately
# repointed somewhere else, so it can only ever match by identity.
#
# The optional arguments rewrite exactly one clause of the fallback at a time,
# so each negative case below differs from the bound row in one field and no
# other.
no_identity_payload() {
  python3 - "$no_identity_fixture" "$1" "${2:-}" "${3:-}" <<'PY'
import json
import sys

fixture_path, cwd, session_id, agent_name = sys.argv[1:]
with open(fixture_path, encoding="utf-8") as fixture:
    payload = json.load(fixture)["data"]["input"]
payload["cwd"] = cwd
if session_id:
    payload["sessionId"] = session_id
if agent_name:
    payload["agentName"] = agent_name
print(json.dumps(payload, separators=(",", ":")))
PY
}

cp "$no_identity_ledger" "$no_identity_ledger.before-unmatched"

# A payload with no identity still has to be declined at exit 0, not rejected at
# exit 2: exit 2 is the failure that silenced the chain in #41.
no_identity_other_session_status=0
no_identity_other_session_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$no_identity_ledger" \
    <<< "$(no_identity_payload "$no_identity_worktree" session-from-another-run)"
)" || no_identity_other_session_status=$?
if [ "$no_identity_other_session_status" -ne 0 ]; then
  err "a no-identity payload from another session exited $no_identity_other_session_status instead of declining"
fi
assert_plan "no-identity completion from another session" "$no_identity_other_session_output" \
  '{"continue":false,"reason":"unmatched-payload","session_id":"session-from-another-run","agent_type":"'"$no_identity_agent_name"'","worktree":"'"$no_identity_worktree"'"}'

no_identity_other_type_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$no_identity_ledger" \
    <<< "$(no_identity_payload "$no_identity_worktree" "" some-other-agent-type)"
)"
assert_plan "no-identity completion from another agent type" "$no_identity_other_type_output" \
  '{"continue":false,"reason":"unmatched-payload","session_id":"'"$no_identity_session_id"'","agent_type":"some-other-agent-type","worktree":"'"$no_identity_worktree"'"}'

no_identity_other_worktree="$tmp_dir/worktree-no-identity-elsewhere"
# A directory that exists, so that a predicate which stopped reading the
# worktree would get as far as closing the row and fail this case by name,
# rather than crashing on a `cwd` that was never there.
mkdir -p "$no_identity_other_worktree"
no_identity_other_worktree_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$no_identity_ledger" \
    <<< "$(no_identity_payload "$no_identity_other_worktree")"
)"
assert_plan "no-identity completion from another worktree" "$no_identity_other_worktree_output" \
  '{"continue":false,"reason":"unmatched-payload","session_id":"'"$no_identity_session_id"'","agent_type":"'"$no_identity_agent_name"'","worktree":"'"$no_identity_other_worktree"'"}'

if ! cmp -s "$no_identity_ledger.before-unmatched" "$no_identity_ledger"; then
  err "a declined no-identity completion modified the ledger"
fi

no_identity_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$no_identity_ledger" \
    <<< "$(no_identity_payload "$no_identity_worktree")"
)"
assert_plan "no-identity completion" "$no_identity_output" \
  '{"continue":true,"outcome":"published","target":"issue-no-identity"}'

if ! python3 - "$no_identity_ledger" "$no_identity_bound_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

assert len(rows) == 1, rows
# The captured timestamp is epoch milliseconds, exactly as the runtime sent it.
assert rows[0]["finish_time"] == "2026-08-24T00:35:36Z", rows
assert rows[0]["outcome"] == "published", rows
assert rows[0]["agent_name"] == sys.argv[2], rows
PY
then
  err "a captured payload carrying no agentId or agentType did not close its bound ledger row"
fi

if [ -e "$no_identity_worktree" ]; then
  err "no-identity completion did not remove its worktree"
fi

# Two open rows a no-identity payload cannot tell apart must close neither.
# `reserve` refuses a second open reservation on a worktree, so the colliding
# row is written straight to the ledger: the guard exists for the ledgers that
# hold one anyway — written by an older release, repaired by hand, or shared by
# two chains — where guessing between them would close the wrong run.
ambiguous_ledger="$tmp_dir/.git-loopy/ambiguous-subagents.jsonl"
ambiguous_worktree="$tmp_dir/worktree-ambiguous"
reserve_and_bind \
  --ledger "$ambiguous_ledger" \
  --route implement \
  --target issue-ambiguous-first \
  --session-id "$no_identity_session_id" \
  --agent-id agent-ambiguous-first \
  --agent-type "$no_identity_agent_name" \
  --agent-name "$no_identity_bound_name" \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$ambiguous_worktree" \
  --chain-depth 1

python3 - "$ambiguous_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
assert len(rows) == 1, rows
collision = dict(rows[0])
collision["target"] = "issue-ambiguous-second"
collision["agent_id"] = "agent-ambiguous-second"
rows.append(collision)
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
cp "$ambiguous_ledger" "$ambiguous_ledger.before-ambiguous"

ambiguous_status=0
ambiguous_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$ambiguous_ledger" \
    <<< "$(no_identity_payload "$ambiguous_worktree")"
)" || ambiguous_status=$?
if [ "$ambiguous_status" -ne 0 ]; then
  err "an ambiguous no-identity payload exited $ambiguous_status instead of declining"
fi
assert_plan "ambiguous no-identity completion" "$ambiguous_output" \
  '{"continue":false,"reason":"ambiguous-payload","session_id":"'"$no_identity_session_id"'","agent_type":"'"$no_identity_agent_name"'","worktree":"'"$ambiguous_worktree"'"}'

if ! cmp -s "$ambiguous_ledger.before-ambiguous" "$ambiguous_ledger"; then
  err "an ambiguous no-identity completion modified the ledger"
fi
if [ ! -e "$ambiguous_worktree" ]; then
  err "an ambiguous no-identity completion removed a worktree it did not close"
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

# Validation is tiered because the match is. A payload that names an agent is
# still held to both identity fields, and one that names none is held to the
# `agentName` the fallback correlates by instead — each named when it is absent,
# because the chain cannot close a row without the field the path it took reads.
identity_error="$tmp_dir/missing-identity-half.err"
if PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
  --ledger "$required_ledger" \
  <<< "$(payload_without "$required_payload" agentId)" \
  >/dev/null 2>"$identity_error"
then
  err "complete accepted a payload carrying half an identity"
fi
if ! grep -q "subagent-stop payload is missing agentId" "$identity_error"; then
  err "complete did not name the missing half of the payload identity"
fi

fallback_error="$tmp_dir/missing-agent-name.err"
if PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete \
  --ledger "$required_ledger" \
  <<< '{"sessionId":"session-required","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'"}' \
  >/dev/null 2>"$fallback_error"
then
  err "complete accepted a payload carrying neither an identity nor an agentName"
fi
if ! grep -q "subagent-stop payload is missing agentName" "$fallback_error"; then
  err "complete did not name the agentName the fallback reads"
fi

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
for _ in $(seq 1 100); do
  grep -q reservation-crash "$reservation_ledger" 2>/dev/null && break
  sleep 0.01
done
if ! grep -q reservation-crash "$reservation_ledger" 2>/dev/null; then
  err "reservation crash fixture did not record its worktree reservation"
else
  kill -KILL "$reservation_crash_pid"
  wait "$reservation_crash_pid" 2>/dev/null || true
fi

if [ -e "$tmp_dir/worktree-reservation-crash" ]; then
  err "reservation crash fixture created its worktree before the test could interrupt it"
fi

reservation_recovery="$("$CHAIN" recover --ledger "$reservation_ledger" --stale-after-seconds 60 --now 2026-08-22T00:05:00Z)"
assert_plan "uncreated worktree recovery" "$reservation_recovery" \
  '{"recovered":1,"targets":["issue-reservation-crash"]}'

lock_crash_ledger="$tmp_dir/.git-loopy/lock-crash.jsonl"
CHAIN_RESERVE_PAUSE_BEFORE_COMMIT=1 "$CHAIN" reserve --parent-pid "$$" \
  --ledger "$lock_crash_ledger" \
  --route implement \
  --target issue-lock-crash \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-lock-crash" \
  --chain-depth 1 &
lock_crash_pid=$!
for _ in $(seq 1 100); do
  [ -f "$lock_crash_ledger.lock/pid" ] && break
  sleep 0.01
done
if [ ! -f "$lock_crash_ledger.lock/pid" ]; then
  err "SIGKILL recovery fixture did not acquire the ledger lock"
else
  kill -KILL "$lock_crash_pid"
  wait "$lock_crash_pid" 2>/dev/null || true
fi

if [ ! -d "$lock_crash_ledger.lock" ]; then
  err "SIGKILL did not leave the ledger lock behind"
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
