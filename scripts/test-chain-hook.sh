#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$REPO/scripts/validate-chain-hook.py"
tmp_dir="$(mktemp -d)"
fail=0

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

err() {
  echo "error: $1" >&2
  fail=1
}

hook="$tmp_dir/git-loopy-chain.json"
agent_stop_helper="$REPO/.github/hooks/git-loopy-agent-stop.py"
setup_agent_stop_helper="$REPO/skills/setup-git-loopy-skills/git-loopy-agent-stop.py"

if ! grep -Fq 'setup-git-loopy-skills' "$agent_stop_helper"; then
  err "this repository hook does not use the setup helper as its canonical implementation"
fi
# The reenter branch must invoke the bundled helper, but must not exec away:
# exec-ing skips the invocation log, which is the silence that log removes.
if ! grep -Fq 'git-loopy-agent-stop.py' \
  "$REPO/skills/setup-git-loopy-skills/SKILL.md"; then
  err "setup would not route agentStop through its bundled helper"
fi
if grep -Fq 'exec python3 "$(dirname "${BASH_SOURCE[0]}")/git-loopy-agent-stop.py"' \
  "$REPO/skills/setup-git-loopy-skills/SKILL.md"; then
  err "setup execs the agentStop helper, bypassing the hook invocation log"
fi

python3 - "$REPO/.github/hooks/git-loopy-chain.json" "$hook" <<'PY'
import json
import sys

source_path, hook_path = sys.argv[1:]
with open(source_path, encoding="utf-8") as source:
    hook = json.load(source)
with open(hook_path, "w", encoding="utf-8") as destination:
    json.dump(hook, destination)
PY

if ! python3 "$VALIDATOR" "$hook"; then
  err "validator rejected the generated chain hooks"
fi

python3 - "$hook" <<'PY'
import json
import sys

hook_path = sys.argv[1]
with open(hook_path, encoding="utf-8") as hook_file:
    hook = json.load(hook_file)
del hook["hooks"]["agentStop"]
with open(hook_path, "w", encoding="utf-8") as hook_file:
    json.dump(hook, hook_file)
PY

if python3 "$VALIDATOR" "$hook" >/dev/null 2>&1; then
  err "validator accepted a hook without agentStop"
fi

python3 - "$REPO/.github/hooks/git-loopy-chain.json" "$hook" <<'PY'
import json
import sys

source_path, hook_path = sys.argv[1:]
with open(source_path, encoding="utf-8") as source:
    hook = json.load(source)
hook["hooks"]["agentStop"][0]["bash"] = (
    "/tmp/git-loopy-chain.sh reenter"
)
with open(hook_path, "w", encoding="utf-8") as destination:
    json.dump(hook, destination)
PY

if python3 "$VALIDATOR" "$hook" >/dev/null 2>&1; then
  err "validator accepted a machine-specific agentStop resolver"
fi

fixture_repo="$tmp_dir/reentry-repository"
git -C "$tmp_dir" init --quiet "$fixture_repo"
git -C "$fixture_repo" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m initial
fixture_ledger="$fixture_repo/.git-loopy/subagents.jsonl"
mkdir -p "$(dirname "$fixture_ledger")"
fixture_worktree="$tmp_dir/reentry-linked-worktree"
git -C "$fixture_repo" worktree add --quiet -b agent-stop-fixture "$fixture_worktree"

write_fixture_ledger() {
  python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps({
        "target": "issue-26",
        "finish_time": "2026-08-22T00:00:00Z",
        "outcome": "published",
    }) + "\n")
PY
}

agent_stop_payload() {
  local stop_hook_active="$1"
  printf '%s' '{"cwd":"'"$fixture_worktree"'","timestamp":"2026-08-22T00:01:00Z","stop_hook_active":'"$stop_hook_active"'}'
}

write_fixture_ledger
block_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$block_output" != '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","targets":["issue-26"]}' ]; then
  err "agentStop did not block for an unrouted completion"
fi

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
assert row["routed"] is True
assert row["routed_at"] == "2026-08-22T00:01:00Z"
PY
then
  err "agentStop did not mark the blocked completion routed"
fi

routed_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$routed_output" != '{"decision":"allow","reason":"no-unrouted-completion"}' ]; then
  err "agentStop did not stand aside after routing the completion"
fi

# Fan-out finishes in batches, so several runs can complete between two parent
# turns. One `/next` fill refills every slot the batch freed, so the batch is
# worth one block: the runtime allows eight consecutive blocks and stands the
# hook aside on the turn a block forces, so a second unrouted row would strand
# the rest of the batch and force a spurious re-entry later.
write_batch_fixture_ledger() {
  python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for target in ("issue-26", "issue-27", "issue-30"):
        ledger.write(json.dumps({
            "target": target,
            "finish_time": "2026-08-22T00:00:00Z",
            "outcome": "published",
        }) + "\n")
    ledger.write(json.dumps({
        "target": "issue-31",
        "finish_time": "",
        "outcome": "",
    }) + "\n")
PY
}

write_batch_fixture_ledger
batch_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$batch_output" != '{"decision":"block","reason":"3 completed runs are unrouted. Run /next now and refill every freed slot.","targets":["issue-26","issue-27","issue-30"]}' ]; then
  err "agentStop did not route a batch of completions in one block"
fi

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

completed = [row for row in rows if row["finish_time"]]
assert all(row["routed"] is True for row in completed), rows
assert all(row["routed_at"] == "2026-08-22T00:01:00Z" for row in completed), rows
assert "routed" not in rows[-1], rows
PY
then
  err "agentStop left part of the batch unrouted or routed a run still in flight"
fi

batch_routed_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$batch_routed_output" != '{"decision":"allow","reason":"no-unrouted-completion"}' ]; then
  err "agentStop blocked a second time for a batch it had already routed"
fi

# A row the chain script could not have written is ledger corruption, and it must
# not hold the rest of the batch hostage: it is never marked routed, so refusing
# the whole batch over it would stall every later natural stop too.
python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps({
        "target": "issue-32",
        "finish_time": "2026-08-22T00:00:00Z",
        "outcome": "published",
    }) + "\n")
    ledger.write(json.dumps({
        "target": "",
        "finish_time": "2026-08-22T00:00:00Z",
        "outcome": "published",
    }) + "\n")
    ledger.write(json.dumps({
        "target": "issue-33",
        "finish_time": "2026-08-22T00:00:00Z",
        "outcome": "published",
    }) + "\n")
PY
corrupt_batch_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$corrupt_batch_output" != '{"decision":"block","reason":"2 completed runs are unrouted. Run /next now and refill every freed slot.","targets":["issue-32","issue-33"]}' ]; then
  err "agentStop let one unusable row withhold the rest of the batch"
fi

corrupt_only_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$corrupt_only_output" != '{"decision":"allow","reason":"invalid-completed-row"}' ]; then
  err "agentStop did not name the unusable row once it was all that was left"
fi

python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps({
        "target": "issue-open",
        "finish_time": "",
        "outcome": "",
    }) + "\n")
PY
ordinary_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$ordinary_output" != '{"decision":"allow","reason":"no-unrouted-completion"}' ]; then
  err "agentStop did not stand aside without a completed run"
fi

# Recovery closes an orphaned reservation to release capacity, but no agent completed
# that row. It must not force a spurious `/next` re-entry or mark it as routed.
python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    ledger.write(json.dumps({
        "target": "issue-reclaimed",
        "finish_time": "2026-08-22T00:00:00Z",
        "outcome": "reclaimed",
    }) + "\n")
PY
reclaimed_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$reclaimed_output" != '{"decision":"allow","reason":"no-unrouted-completion"}' ]; then
  err "agentStop treated a reclaimed reservation as a completed run"
fi
if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert "routed" not in row
PY
then
  err "agentStop routed a reclaimed reservation"
fi

write_fixture_ledger
mkdir "$fixture_ledger.lock"
printf '999999\tstale process\n' > "$fixture_ledger.lock/pid"
stale_lock_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload false)"
)"
if [ "$stale_lock_output" != '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","targets":["issue-26"]}' ]; then
  err "agentStop did not reclaim a stale ledger lock"
fi
if [ -e "$fixture_ledger.lock" ]; then
  err "agentStop left the reclaimed ledger lock behind"
fi

write_fixture_ledger
active_output="$(
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload true)"
)"
if [ "$active_output" != '{"decision":"allow","reason":"stop-hook-active"}' ]; then
  err "agentStop did not stand aside when stop_hook_active was true"
fi

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())
assert "routed" not in row
PY
then
  err "agentStop routed a completion while stop_hook_active was true"
fi

exit "$fail"
