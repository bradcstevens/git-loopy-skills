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
if ! grep -Fq \
  'exec python3 "$(dirname "${BASH_SOURCE[0]}")/git-loopy-agent-stop.py"' \
  "$REPO/skills/setup-git-loopy-skills/SKILL.md"; then
  err "setup would not route agentStop through its bundled helper"
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
if [ "$block_output" != '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","target":"issue-26"}' ]; then
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
