#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HANDOFF="$REPO/skills/handoff/handoff.sh"
tmp_dir="$(mktemp -d)"
fail=0

err() {
  echo "error: $1" >&2
  fail=1
}

launched_pid=""

cleanup() {
  [ -z "$launched_pid" ] || kill "$launched_pid" 2>/dev/null || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

export HANDOFF_SETTLE_SECONDS=1
export HANDOFF_ARGV="$tmp_dir/argv"

stub() {
  local path="$tmp_dir/$1-stub.sh"
  cat > "$path"
  chmod +x "$path"
  printf '%s\n' "$path"
}

alive_stub="$(stub alive <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HANDOFF_ARGV"
echo "starting"
sleep 30
EOF
)"

rejected_stub="$(stub rejected <<'EOF'
#!/usr/bin/env bash
echo "error: unknown option '--effort'"
exit 1
EOF
)"

exited_stub="$(stub exited <<'EOF'
#!/usr/bin/env bash
echo "done already"
EOF
)"

# The prompt carries an apostrophe, a #, and a newline: the three things a shell
# would mangle if the prompt travelled as command text rather than as a file.
prompt_file="$tmp_dir/prompt.txt"
cat > "$prompt_file" <<'EOF'
/implement issue 42 and keep the runner's ledger intact # not a comment
Second line stays attached.
EOF

run() {
  HANDOFF_COPILOT_BIN="$1" "$HANDOFF" \
    --name "Fix login bug" \
    --model gpt-5.6-terra \
    --effort high \
    --context default \
    --prompt-file "$prompt_file" \
    "${@:2}"
}

field() {
  python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"
}

set +e
"$HANDOFF" --name only-a-name >/dev/null 2>&1
missing_status=$?
"$HANDOFF" --name n --model m --effort e --context c --prompt-file "$tmp_dir/absent.txt" >/dev/null 2>&1
absent_status=$?
set -e
[ "$missing_status" -eq 2 ] || err "an incomplete call exited $missing_status rather than 2"
[ "$absent_status" -eq 2 ] || err "a missing prompt file exited $absent_status rather than 2"

log="$tmp_dir/launched.log"
set +e
launched_json="$(run "$alive_stub" --log "$log")"
launched_status=$?
set -e

[ "$launched_status" -eq 0 ] || err "a live session exited $launched_status rather than 0"
[ "$(field "$launched_json" status)" = "launched" ] ||
  err "a live session reported $(field "$launched_json" status) rather than launched"
[ "$(field "$launched_json" log)" = "$log" ] || err "the reported log path is not the one passed"
[ "$(field "$launched_json" resume)" = "copilot --yolo --resume='Fix login bug'" ] ||
  err "the resume command does not quote a multi-word session name"

launched_pid="$(field "$launched_json" pid)"
kill -0 "$launched_pid" 2>/dev/null || err "the reported pid is not a running process"

expected_argv="$tmp_dir/expected-argv"
{
  printf '%s\n' --yolo --no-ask-user -n "Fix login bug" --model gpt-5.6-terra
  printf '%s\n' --effort high --context default -p
  cat "$prompt_file"
} > "$expected_argv"
# cat strips the prompt's trailing newline, which printf then restores.
if ! diff -q "$expected_argv" "$HANDOFF_ARGV" >/dev/null; then
  err "the session did not receive the runtime flags and the prompt as one argument each"
  diff "$expected_argv" "$HANDOFF_ARGV" >&2 || true
fi

kill "$launched_pid" 2>/dev/null || true
launched_pid=""

set +e
rejected_json="$(run "$rejected_stub" --log "$tmp_dir/rejected.log")"
rejected_status=$?
exited_json="$(run "$exited_stub" --log "$tmp_dir/exited.log")"
exited_status=$?
set -e

[ "$rejected_status" -eq 1 ] || err "a rejected flag exited $rejected_status rather than 1"
[ "$(field "$rejected_json" status)" = "rejected" ] ||
  err "an error: line reported $(field "$rejected_json" status) rather than rejected"
case "$(field "$rejected_json" log_head)" in
  *"unknown option"*) ;;
  *) err "a rejected launch did not carry the log line that explains it" ;;
esac

[ "$exited_status" -eq 1 ] || err "an early exit exited $exited_status rather than 1"
[ "$(field "$exited_json" status)" = "exited" ] ||
  err "an early exit reported $(field "$exited_json" status) rather than exited"

default_log_json="$(HANDOFF_COPILOT_BIN="$exited_stub" TMPDIR="$tmp_dir/tmproot" "$HANDOFF" \
  --name "Fix login bug" \
  --model gpt-5.6-terra \
  --effort high \
  --context default \
  --prompt-file "$prompt_file" || true)"
default_log="$(field "$default_log_json" log)"
case "$default_log" in
  "$tmp_dir/tmproot/copilot-fix-login-bug-"*.log) ;;
  *) err "the default log path is not a slugged, timestamped file under TMPDIR: $default_log" ;;
esac
case "$default_log" in
  "$REPO"/*) err "the default log path lands inside the repository: $default_log" ;;
esac

if [ "$fail" -eq 0 ]; then
  echo "ok: handoff launcher valid"
fi
exit "$fail"
