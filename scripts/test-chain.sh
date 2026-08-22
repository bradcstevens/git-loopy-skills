#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHAIN="$REPO/skills/next/chain.sh"
tmp_dir="$(mktemp -d)"
fail=0

err() {
  echo "error: $1" >&2
  fail=1
}

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

git -C "$tmp_dir" init --quiet
ledger="$tmp_dir/.git-loopy/subagents.jsonl"

if [ -e "$ledger" ]; then
  err "ledger exists before the first record"
fi

(
  cd "$tmp_dir"
  "$CHAIN" record \
  --route implement \
  --target issue-4 \
  --session-id session-1 \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-1" \
  --chain-depth 1
)

if [ ! -f "$ledger" ]; then
  err "record did not create the ledger"
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
    "session_id": "session-1",
    "spawn_time": "2026-08-22T00:00:00Z",
    "worktree": sys.argv[1].replace("/.git-loopy/subagents.jsonl", "/worktree-1"),
    "chain_depth": 1,
    "finish_time": "",
    "outcome": "",
}
PY
fi

"$CHAIN" record \
  --ledger "$ledger" \
  --route code-review \
  --target issue-4 \
  --session-id session-2 \
  --spawn-time 2026-08-22T00:01:00Z \
  --worktree "$tmp_dir/worktree-2" \
  --chain-depth 2

if [ "$(wc -l < "$ledger" | tr -d ' ')" -ne 2 ]; then
  err "record did not append a second row"
fi

CHAIN_RECORD_PAUSE_BEFORE_COMMIT=10 "$CHAIN" record \
  --ledger "$ledger" \
  --route push \
  --target issue-4 \
  --session-id interrupted \
  --spawn-time 2026-08-22T00:02:00Z \
  --worktree "$tmp_dir/worktree-3" \
  --chain-depth 3 &
record_pid=$!
for _ in $(seq 1 100); do
  if grep -q interrupted "$tmp_dir/.git-loopy"/.subagents.* 2>/dev/null; then
    break
  fi
  sleep 0.01
done
kill -TERM "$record_pid"
wait "$record_pid" 2>/dev/null || true

if [ "$(wc -l < "$ledger" | tr -d ' ')" -ne 2 ]; then
  err "interrupted append left a partial row"
fi
if grep -q interrupted "$ledger"; then
  err "interrupted append committed an incomplete record"
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
    --context-tier "$7"
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

outside_route="$(plan /triage issue-6 AFK-safe triage-agent gpt-5.6-terra high default)"
assert_plan "outside route" "$outside_route" \
  '{"decision":"decline","reason":"route-not-allowlisted","route":"/triage","target":"issue-6"}'

hitl_route="$(plan /implement issue-6 HITL implement-agent gpt-5.6-terra high default)"
assert_plan "HITL route" "$hitl_route" \
  '{"decision":"decline","reason":"action-not-afk-safe","route":"/implement","target":"issue-6"}'

afk_safe_route="$(plan /implement issue-6 AFK-safe implement-agent gpt-5.6-terra xhigh long_context)"
assert_plan "AFK-safe route" "$afk_safe_route" \
  '{"decision":"spawn","route":"/implement","target":"issue-6","agent":"implement-agent","model":"gpt-5.6-terra","effort":"xhigh","context_tier":"long_context"}'

if [ -e "$plan_ledger" ]; then
  err "plan created a ledger"
fi

"$CHAIN" record \
  --ledger "$plan_ledger" \
  --route implement \
  --target issue-6 \
  --session-id session-3 \
  --spawn-time 2026-08-22T00:03:00Z \
  --worktree "$tmp_dir/worktree-4" \
  --chain-depth 1
cp "$plan_ledger" "$plan_ledger.before"

in_flight_target="$(plan /code-review issue-6 AFK-safe code-review-agent gpt-5.6-sol xhigh default)"
assert_plan "in-flight target" "$in_flight_target" \
  '{"decision":"decline","reason":"target-in-flight","route":"/code-review","target":"issue-6"}'

if ! cmp -s "$plan_ledger.before" "$plan_ledger"; then
  err "plan modified the ledger"
fi

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
"$CHAIN" record \
  --ledger "$complete_ledger" \
  --route implement \
  --target issue-published \
  --session-id agent-published \
  --agent-id agent-published \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-published" \
  --chain-depth 1

completion_payload() {
  printf '%s' '{"sessionId":"parent-session","timestamp":"2026-08-22T00:11:00Z","cwd":"'"$tmp_dir"'","transcriptPath":"'"$tmp_dir"'/transcript.jsonl","agentId":"'"$1"'","agentType":"implement-agent","agentName":"implement-agent","agentDisplayName":"Implement agent","response":"Completed the route.","stopReason":"end_turn"}'
}

published_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-published)"
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
    "session_id": "agent-published",
    "agent_id": "agent-published",
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

"$CHAIN" record \
  --ledger "$complete_ledger" \
  --route code-review \
  --target issue-no-evidence \
  --session-id agent-no-evidence \
  --agent-id agent-no-evidence \
  --spawn-time 2026-08-22T00:00:00Z \
  --worktree "$tmp_dir/worktree-no-evidence" \
  --chain-depth 2

no_evidence_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=no-evidence "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-no-evidence)"
)"
assert_plan "no-evidence completion" "$no_evidence_output" \
  '{"continue":false,"outcome":"no-evidence","target":"issue-no-evidence"}'

if ! python3 - "$complete_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger]

row = next(row for row in rows if row["session_id"] == "agent-no-evidence")
assert row["finish_time"] == "2026-08-22T00:11:00Z"
assert row["outcome"] == "no-evidence"
PY
then
  err "no-evidence completion did not close the matching ledger row"
fi

cp "$complete_ledger" "$complete_ledger.before-unmatched"
unmatched_output="$(
  PATH="$fake_bin:$PATH" CHAIN_EVIDENCE=published "$CHAIN" complete --ledger "$complete_ledger" \
    <<< "$(completion_payload agent-unmatched)"
)"
assert_plan "unmatched completion" "$unmatched_output" \
  '{"continue":false,"reason":"unmatched-payload","agent_id":"agent-unmatched"}'

if ! cmp -s "$complete_ledger.before-unmatched" "$complete_ledger"; then
  err "unmatched completion modified the ledger"
fi

exit "$fail"
