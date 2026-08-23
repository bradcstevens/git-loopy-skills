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
# The helper ships twice — bundled with the skill and installed in the repo — so
# the copies can only stay in step if the installed one holds no implementation
# of its own. A pasted-in decision would drift the moment the bundle changes.
for owned_by_the_bundle in no-unrouted-completion route-abandoned stop_hook_active; do
  if grep -Fq "$owned_by_the_bundle" "$agent_stop_helper"; then
    err "this repository hook carries its own copy of the agentStop decision logic"
  fi
done
if [ ! -f "$setup_agent_stop_helper" ]; then
  err "the bundled agentStop helper the repository hook defers to is missing"
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
  local stop_hook_active="$1" timestamp="${2-2026-08-22T00:01:00Z}"
  local session_id="${3-session-parent}"
  local fields='"cwd":"'"$fixture_worktree"'","stop_hook_active":'"$stop_hook_active"

  # An empty timestamp or session id stands for a payload carrying no such
  # field at all. ADR-0005 keeps a field optional until something reads it, so
  # the helper has to cope with either being absent.
  [ -z "$timestamp" ] || fields="$fields"',"timestamp":"'"$timestamp"'"'
  [ -z "$session_id" ] || fields="$fields"',"sessionId":"'"$session_id"'"'
  printf '{%s}' "$fields"
}

reenter() {
  COPILOT_HOME="$tmp_dir/missing-copilot-home" \
    "$REPO/.github/hooks/git-loopy-chain.sh" reenter \
    <<< "$(agent_stop_payload "$@")"
}

block_decision='{"decision":"block","reason":"A completed run is unrouted. Run /next now.","target":"issue-26"}'

block_decision_for() {
  printf '{"decision":"block","reason":"A completed run is unrouted. Run /next now.","target":"%s"}' "$1"
}

confirmed_decision_for() {
  printf '{"decision":"allow","reason":"stop-hook-active","confirmed":"%s"}' "$1"
}

assert_decision() {
  local label="$1" actual="$2" expected="$3"

  [ "$actual" = "$expected" ] || err "$label: expected $expected, got $actual"
}

# Reads one field off the row carrying a given target, so a multi-row ledger can
# be asserted without hand-rolling a reader per assertion.
ledger_field() {
  python3 - "$fixture_ledger" "$1" "$2" <<'PY'
import json
import sys

ledger_path, target, field = sys.argv[1:]
with open(ledger_path, encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]

row = next((row for row in rows if row.get("target") == target), None)
print(json.dumps(row.get(field) if row is not None else None, separators=(",", ":")))
PY
}

assert_ledger_intact() {
  local label="$1"

  if [ -e "$fixture_ledger.lock" ]; then
    err "$label left the ledger lock behind"
  fi
  # A surviving replacement file is a half-finished write, and a half-written
  # ledger reads as a ledger with no completed run — the silence this hook
  # exists to prevent.
  if compgen -G "$(dirname "$fixture_ledger")/.subagents.*" > /dev/null; then
    err "$label left a partial ledger write behind"
  fi
}

# Blocking is a route *request*, not a route. The reason reaches the parent as a
# dismissible queued prompt, so emitting it is no evidence that /next ran.
write_fixture_ledger
assert_decision "an unrouted completion" "$(reenter false 2026-08-22T00:01:00Z)" "$block_decision"
assert_ledger_intact "the first block"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert not row.get("routed"), row
assert "routed_at" not in row, row
assert row["route_requested_at"] == "2026-08-22T00:01:00Z", row
assert row["route_attempts"] == 1, row
PY
then
  err "agentStop recorded a completed route instead of a route request"
fi

# The queued prompt was dismissed, so no forced turn ever ran: the request is
# still owed and the next agentStop has to ask again.
assert_decision "an unconfirmed request" "$(reenter false 2026-08-22T00:02:00Z)" "$block_decision"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert not row.get("routed"), row
assert row["route_requested_at"] == "2026-08-22T00:01:00Z", row
assert row["route_attempts"] == 2, row
PY
then
  err "agentStop did not count the unconfirmed request against the same row"
fi

# stop_hook_active is the runtime's evidence that the parent took the turn the
# block forced, which is the only thing that promotes a request to a route.
assert_decision "a confirmed request" "$(reenter true 2026-08-22T00:03:00Z)" \
  '{"decision":"allow","reason":"stop-hook-active","confirmed":"issue-26"}'
assert_ledger_intact "the confirmation"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["routed"] is True, row
assert row["routed_at"] == "2026-08-22T00:03:00Z", row
PY
then
  err "agentStop did not mark the confirmed request routed"
fi

assert_decision "a routed completion" "$(reenter false 2026-08-22T00:04:00Z)" \
  '{"decision":"allow","reason":"no-unrouted-completion"}'

# The attempt count is the request; the request time is only provenance. A
# payload carrying no `timestamp` — which nothing required before confirmation
# existed, per ADR-0005 — must still leave a request the forced turn can
# confirm, or a hop that actually landed is re-blocked and then abandoned under
# a target that was in fact routed.
write_fixture_ledger
assert_decision "an untimestamped request" "$(reenter false "")" "$block_decision"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["route_attempts"] == 1, row
assert "route_requested_at" not in row, row
PY
then
  err "agentStop recorded a route request time it can never confirm"
fi

assert_decision "an untimestamped confirmation" "$(reenter true "")" \
  '{"decision":"allow","reason":"stop-hook-active","confirmed":"issue-26"}'
assert_decision "a completion routed without a timestamp" "$(reenter false)" \
  '{"decision":"allow","reason":"no-unrouted-completion"}'

# A turn forced in one session is no evidence for a request another session
# made, so a request has to name who asked for it.
#
# Two rows can hold requests at the same time. The block path always takes the
# first owed row, and rows are appended at reservation time but finished in
# place, so a run reserved earlier and completed later becomes the first owed
# row *after* a later row was already blocked for. Crediting whichever pending
# row comes first then marks one target routed on a turn forced for another,
# and the miscredited hop is never asked for again — the silent dropped hop
# this helper exists to remove.
python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for row in (
        {"target": "issue-27", "finish_time": "", "outcome": ""},
        {"target": "issue-26", "finish_time": "2026-08-22T00:00:00Z", "outcome": "published"},
    ):
        ledger.write(json.dumps(row) + "\n")
PY

assert_decision "a request from one session" \
  "$(reenter false 2026-08-22T01:00:00Z session-a)" "$(block_decision_for issue-26)"

# The earlier reservation finishes, so it becomes the first owed row and the
# next block takes it while issue-26's request is still unconfirmed.
python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    rows = [json.loads(line) for line in ledger if line.strip()]
rows[0]["finish_time"] = "2026-08-22T01:01:00Z"
rows[0]["outcome"] = "published"
with open(sys.argv[1], "w", encoding="utf-8") as ledger:
    for row in rows:
        ledger.write(json.dumps(row) + "\n")
PY

assert_decision "a request from a second session" \
  "$(reenter false 2026-08-22T01:02:00Z session-b)" "$(block_decision_for issue-27)"
assert_decision "the first session's forced turn" \
  "$(reenter true 2026-08-22T01:03:00Z session-a)" "$(confirmed_decision_for issue-26)"
assert_ledger_intact "the correlated confirmation"

assert_decision "the confirmed row" "$(ledger_field issue-26 routed)" "true"
if [ "$(ledger_field issue-27 routed)" != "null" ]; then
  err "agentStop credited a forced turn to a request another session made"
fi

# A session holding no request of its own confirms nothing, rather than
# consuming somebody else's and dropping their hop.
assert_decision "an unrelated session's forced turn" \
  "$(reenter true 2026-08-22T01:04:00Z session-c)" \
  '{"decision":"allow","reason":"stop-hook-active"}'
assert_decision "the request left standing" "$(ledger_field issue-27 routed)" "null"

assert_decision "the second session asking again" \
  "$(reenter false 2026-08-22T01:05:00Z session-b)" "$(block_decision_for issue-27)"
assert_decision "the second session's forced turn" \
  "$(reenter true 2026-08-22T01:06:00Z session-b)" "$(confirmed_decision_for issue-27)"

# A request is confirmed by a turn from the session that asked, so a payload
# carrying no `sessionId` cannot make one. ADR-0005 requires a field the chain
# reads and this path reads this one, so the hook names what is missing and
# stands aside rather than forcing a turn nothing could ever credit — which
# would re-block to the cap and abandon a hop that had in fact landed.
write_fixture_ledger
cp "$fixture_ledger" "$fixture_ledger.before-unidentified"
assert_decision "a request from an unidentified session" \
  "$(reenter false 2026-08-22T02:00:00Z "")" \
  '{"decision":"allow","reason":"missing-session-id","target":"issue-26"}'
if ! cmp -s "$fixture_ledger.before-unidentified" "$fixture_ledger"; then
  err "agentStop recorded a request no forced turn could confirm"
fi
assert_ledger_intact "the unidentified request"

# And the same absence on the confirming side confirms nothing, rather than
# taking over a request some identified session is still owed a turn for.
assert_decision "a request from one session again" \
  "$(reenter false 2026-08-22T02:01:00Z session-d)" "$block_decision"
assert_decision "an unidentified forced turn" "$(reenter true 2026-08-22T02:02:00Z "")" \
  '{"decision":"allow","reason":"stop-hook-active"}'
assert_decision "the request left standing" "$(ledger_field issue-26 routed)" "null"
assert_decision "the identified forced turn" \
  "$(reenter true 2026-08-22T02:03:00Z session-d)" "$(confirmed_decision_for issue-26)"

# ADR-0004: the runtime permits 8 consecutive blocks and then exits without
# saying why, so the chain's own cap has to trip first and name what it dropped.
write_fixture_ledger
blocks=0
for attempt in 1 2 3 4 5 6 7 8; do
  attempt_decision="$(reenter false "2026-08-22T00:0$attempt:00Z")"
  if [ "$attempt_decision" = "$block_decision" ]; then
    blocks=$((blocks + 1))
    continue
  fi
  assert_decision "a request past the cap" "$attempt_decision" \
    '{"decision":"allow","reason":"route-abandoned","target":"issue-26"}'
  break
done
if [ "$blocks" -eq 0 ]; then
  err "agentStop never blocked for an unconfirmed route request"
fi
if [ "$blocks" -ge 8 ]; then
  err "agentStop re-blocked to the runtime ceiling instead of tripping its own cap"
fi
assert_ledger_intact "the abandoned route"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert row["route_abandoned"] is True, row
assert not row.get("routed"), row
PY
then
  err "agentStop did not record the abandoned target on its ledger row"
fi

assert_decision "an abandoned route" "$(reenter false 2026-08-22T00:09:00Z)" \
  '{"decision":"allow","reason":"no-unrouted-completion"}'

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
assert_decision "a ledger with no completed run" "$(reenter false)" \
  '{"decision":"allow","reason":"no-unrouted-completion"}'

write_fixture_ledger
mkdir "$fixture_ledger.lock"
printf '999999\tstale process\n' > "$fixture_ledger.lock/pid"
assert_decision "a stale ledger lock" "$(reenter false)" "$block_decision"
assert_ledger_intact "the reclaimed lock"

# A lock held by a live process is not stale, and a hook that cannot take the
# lock must leave the ledger exactly as it found it.
write_fixture_ledger
cp "$fixture_ledger" "$fixture_ledger.before-busy"
mkdir "$fixture_ledger.lock"
printf '%s\t%s\n' "$$" "$(ps -o lstart= -p $$ | xargs)" > "$fixture_ledger.lock/pid"
assert_decision "a held ledger lock" "$(reenter false)" \
  '{"decision":"allow","reason":"ledger-busy"}'
if ! cmp -s "$fixture_ledger.before-busy" "$fixture_ledger"; then
  err "agentStop wrote to a ledger it never locked"
fi
rm -rf "$fixture_ledger.lock"

write_fixture_ledger
assert_decision "a turn a block already forced" "$(reenter true)" \
  '{"decision":"allow","reason":"stop-hook-active"}'
assert_ledger_intact "the stop_hook_active turn"

if ! python3 - "$fixture_ledger" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as ledger:
    row = json.loads(ledger.readline())

assert "routed" not in row, row
assert "route_requested_at" not in row, row
PY
then
  err "agentStop started a route while stop_hook_active was true"
fi

exit "$fail"
