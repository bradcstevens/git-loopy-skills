#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO/.github/hooks/git-loopy-chain.sh"
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

init_repo() {
  git -C "$1" init --quiet
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
  git -C "$1" commit --quiet --allow-empty -m initial
}

home="$tmp_dir/home"
mkdir -p "$home/skills/next"
cat > "$home/skills/next/chain.sh" <<'CHAIN'
#!/usr/bin/env bash
set -euo pipefail

[ "$1" = "complete" ] || exit 64
payload="$(cat)"
case "$payload" in
  *error-agent*)
    echo "chain failure" >&2
    exit 23
    ;;
  *unmatched-agent*)
    printf '%s\n' '{"continue":false,"reason":"unmatched-payload","agent_id":"unmatched-agent"}'
    ;;
  *matched-agent*)
    printf '%s\n' '{"continue":true,"outcome":"published","target":"issue-matched"}'
    ;;
esac
CHAIN
chmod +x "$home/skills/next/chain.sh"

payload() {
  python3 - "$1" <<'PY'
import json
import sys

agent_id = sys.argv[1]
print(json.dumps({
    "sessionId": f"session-{agent_id}",
    "timestamp": 1787357460000,
    "cwd": "/ignored-by-fake-chain",
    "transcriptPath": "/tmp/transcript.jsonl",
    "agentId": agent_id,
    "agentType": "implement-agent",
    "agentName": "implement-agent",
    "agentDisplayName": "Implement agent",
    "response": "Completed the route.",
    "stopReason": "end_turn",
}))
PY
}

run_hook() {
  local repo="$1" agent_id="$2" resolver="${3:-$RESOLVER}"

  set +e
  hook_output="$(
    cd "$repo"
    COPILOT_HOME="$home" "$resolver" --event subagentStop complete \
      <<< "$(payload "$agent_id")" 2>"$tmp_dir/hook.stderr"
  )"
  hook_status=$?
  set -e
}

repo="$tmp_dir/repo"
mkdir "$repo"
init_repo "$repo"

run_hook "$repo" matched-agent
if [ "$hook_status" -ne 0 ]; then
  err "matched hook exited $hook_status"
fi
if [ "$hook_output" != '{"continue":true,"outcome":"published","target":"issue-matched"}' ]; then
  err "matched hook changed the chain decision"
fi

run_hook "$repo" unmatched-agent
if [ "$hook_status" -ne 0 ]; then
  err "unmatched hook exited $hook_status"
fi
if [ "$hook_output" != '{"continue":false,"reason":"unmatched-payload","agent_id":"unmatched-agent"}' ]; then
  err "unmatched hook changed the chain decision"
fi

run_hook "$repo" error-agent
if [ "$hook_status" -ne 23 ]; then
  err "error hook did not preserve the chain exit status"
fi
if [ -n "$hook_output" ]; then
  err "error hook changed the chain output"
fi

log="$repo/.git-loopy/hook-invocations.jsonl"
if [ ! -f "$log" ]; then
  err "hook invocations did not create a log beside the ledger"
elif ! python3 - "$log" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as log_file:
    rows = [json.loads(line) for line in log_file]

assert [row["event"] for row in rows] == ["subagentStop"] * 3, rows
assert rows[0]["run"]["agent_id"] == "matched-agent", rows
assert rows[0]["decision"] == {
    "continue": True,
    "outcome": "published",
    "target": "issue-matched",
}, rows
assert rows[1]["run"]["agent_id"] == "unmatched-agent", rows
assert rows[1]["decision"] == {
    "continue": False,
    "reason": "unmatched-payload",
    "agent_id": "unmatched-agent",
}, rows
assert rows[2]["run"]["agent_id"] == "error-agent", rows
assert rows[2]["decision"] == {"decision": "error", "exit_status": 23}, rows
PY
then
  err "hook log did not record matched, unmatched, and error decisions"
fi

if ! git -C "$REPO" check-ignore -q .git-loopy/hook-invocations.jsonl; then
  err "hook log is not ignored by git"
fi

template_repo="$tmp_dir/template-repo"
mkdir "$template_repo"
init_repo "$template_repo"
python3 - "$REPO/skills/setup-git-loopy-skills/SKILL.md" "$template_repo" <<'PY'
import os
import pathlib
import sys

skill_path = pathlib.Path(sys.argv[1])
repo_path = pathlib.Path(sys.argv[2])
source = skill_path.read_text(encoding="utf-8")

for name, marker in (
    ("git-loopy-chain.sh", "RESOLVER"),
    ("git-loopy-hook-log.sh", "LOGGER"),
):
    start = f"cat > .github/hooks/{name} <<'{marker}'\n"
    try:
        script = source.split(start, 1)[1].split(f"\n{marker}\n", 1)[0] + "\n"
    except IndexError as error:
        raise SystemExit(f"missing {name} setup template") from error
    destination = repo_path / ".github" / "hooks" / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(script, encoding="utf-8")
    os.chmod(destination, 0o755)

marker = "# Keep runtime state local to this working copy.\n"
try:
    ignore_script = marker + source.split(marker, 1)[1].split("\nfi\n", 1)[0] + "\nfi\n"
except IndexError as error:
    raise SystemExit("missing runtime ignore setup template") from error
destination = repo_path / ".install-runtime-ignore.sh"
destination.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + ignore_script, encoding="utf-8")
os.chmod(destination, 0o755)
PY

(
  cd "$template_repo"
  ./.install-runtime-ignore.sh
)
run_hook "$template_repo" matched-agent "$template_repo/.github/hooks/git-loopy-chain.sh"
if [ "$hook_status" -ne 0 ]; then
  err "setup-generated hook exited $hook_status"
fi
if [ "$hook_output" != '{"continue":true,"outcome":"published","target":"issue-matched"}' ]; then
  err "setup-generated hook changed the chain decision"
fi
if [ ! -f "$template_repo/.git-loopy/hook-invocations.jsonl" ]; then
  err "setup-generated hook did not install hook logging"
fi
if ! git -C "$template_repo" check-ignore -q .git-loopy/hook-invocations.jsonl; then
  err "setup-generated hook did not ignore hook logging"
fi

blocked_repo="$tmp_dir/blocked-repo"
mkdir "$blocked_repo"
init_repo "$blocked_repo"
touch "$blocked_repo/.git-loopy"

run_hook "$blocked_repo" matched-agent
if [ "$hook_status" -ne 0 ]; then
  err "unwritable log changed the hook exit status"
fi
if [ "$hook_output" != '{"continue":true,"outcome":"published","target":"issue-matched"}' ]; then
  err "unwritable log changed the hook decision"
fi

exit "$fail"
