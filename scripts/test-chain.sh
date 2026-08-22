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
  "$CHAIN" reserve "${ledger_args[@]}" \
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
  "$CHAIN" reserve \
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
  python3 - "$ledger" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]
assert len(rows) == 1
assert rows[0] == {
    "route": "implement",
    "target": "issue-4",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": sys.argv[1].replace("/.git-loopy/subagents.jsonl", "/worktree-1"),
    "chain_depth": 1,
    "finish_time": "",
    "outcome": "",
}
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

CHAIN_RESERVE_PAUSE_BEFORE_COMMIT=1 "$CHAIN" reserve \
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
"$CHAIN" reserve \
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
if "$CHAIN" reserve \
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

concurrency_ledger="$tmp_dir/.git-loopy/concurrency-subagents.jsonl"
"$CHAIN" reserve \
  --ledger "$concurrency_ledger" \
  --route implement \
  --target issue-concurrency-holder \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-concurrency-holder" \
  --chain-depth 1
cp "$concurrency_ledger" "$concurrency_ledger.before-limit"
if CHAIN_MAX_CONCURRENCY=1 "$CHAIN" reserve \
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

unbound_ledger="$tmp_dir/.git-loopy/unbound-subagents.jsonl"
unbound_worktree="$tmp_dir/worktree-unbound"
"$CHAIN" reserve \
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

assert rows == [{
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

"$CHAIN" reserve \
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

if "$CHAIN" reserve \
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
assert_plan "stale worktree recovery" "$recovery_output" \
  '{"recovered":1,"targets":["issue-stale"]}'

if [ -e "$stale_worktree" ]; then
  err "recovery did not remove the stale worktree"
fi

if ! python3 - "$recovery_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == "session-stale")
assert row["finish_time"] == "2026-08-22T00:05:00Z"
assert row["outcome"] == "failed"
PY
then
  err "recovery did not close the stale ledger row as failed"
fi

recovered_target="$(plan /implement issue-stale AFK-safe implement-agent gpt-5.6-terra high default "$tmp_dir/plan-recovered")"
assert_plan "target after recovery" "$recovered_target" \
  '{"decision":"decline","reason":"target-failed","route":"/implement","target":"issue-stale"}'

reservation_ledger="$tmp_dir/.git-loopy/reservation-crash.jsonl"
CHAIN_RESERVE_PAUSE_BEFORE_WORKTREE=1 "$CHAIN" reserve \
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
CHAIN_RESERVE_PAUSE_BEFORE_COMMIT=1 "$CHAIN" reserve \
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
CHAIN_LOCK_STALE_SECONDS=0 "$CHAIN" reserve \
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
