#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  handoff.sh --name NAME --model MODEL --effort LEVEL --context TIER \
    --prompt-file PATH [--log PATH]

Launches a detached GitHub Copilot CLI session on the prompt in --prompt-file and
returns once its log has proven or disproven the launch.

--name, --model, --effort and --context are the runtime /next sized, and reach
the session as -n, --model, --effort and --context. The prompt travels as a file
that no shell re-quotes, so an apostrophe in it is safe. --log defaults to a
timestamped path under TMPDIR, outside every worktree.

Prints one JSON object and exits 0 only for "launched":
  launched  the session is running; "resume" is the command that rejoins it
  rejected  the session printed an error: line, usually a flag it would not take
  exited    the session ended inside the settle window; read "log_head"

HANDOFF_COPILOT_BIN sets the launched binary (default: copilot).
HANDOFF_SETTLE_SECONDS sets how long the launch is watched (default: 5).
EOF
  exit 2
}

die() {
  echo "error: $1" >&2
  exit 2
}

name="" model="" effort="" context="" prompt_file="" log=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) [ -z "$name" ] || usage; name="${2:?missing value for --name}"; shift 2 ;;
    --model) [ -z "$model" ] || usage; model="${2:?missing value for --model}"; shift 2 ;;
    --effort) [ -z "$effort" ] || usage; effort="${2:?missing value for --effort}"; shift 2 ;;
    --context) [ -z "$context" ] || usage; context="${2:?missing value for --context}"; shift 2 ;;
    --prompt-file)
      [ -z "$prompt_file" ] || usage
      prompt_file="${2:?missing value for --prompt-file}"; shift 2 ;;
    --log) [ -z "$log" ] || usage; log="${2:?missing value for --log}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$name" ] && [ -n "$model" ] && [ -n "$effort" ] && [ -n "$context" ] &&
  [ -n "$prompt_file" ] || usage

[ -s "$prompt_file" ] || die "prompt file is empty or missing: $prompt_file"

copilot_bin="${HANDOFF_COPILOT_BIN:-copilot}"
command -v "$copilot_bin" >/dev/null 2>&1 || die "no such command: $copilot_bin"

settle_seconds="${HANDOFF_SETTLE_SECONDS:-5}"
case "$settle_seconds" in
  '' | *[!0-9]*) die "HANDOFF_SETTLE_SECONDS must be a whole number of seconds: $settle_seconds" ;;
esac

if [ -z "$log" ]; then
  slug="$(
    printf '%s' "$name" |
      tr '[:upper:]' '[:lower:]' |
      sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
  )"
  [ -n "$slug" ] || slug="session"
  tmp_root="${TMPDIR:-/tmp}"
  log="${tmp_root%/}/copilot-$slug-$(date +%Y%m%d-%H%M%S).log"
fi

mkdir -p "$(dirname "$log")"
: > "$log"

pid_file="$(mktemp)"
trap 'rm -f "$pid_file"' EXIT

# The prompt reaches the session as one argument read from the file, never as
# shell text a launcher could re-quote and split.
prompt="$(cat "$prompt_file")"

# --yolo carries the session past permission prompts no one is there to answer,
# and --no-ask-user keeps it working alone rather than waiting on a question that
# reaches nobody. Launching from a subshell reparents the session away from this
# script, so it outlives the caller's process tree rather than ending with it.
(
  nohup "$copilot_bin" --yolo --no-ask-user \
    -n "$name" --model "$model" --effort "$effort" --context "$context" \
    -p "$prompt" >"$log" 2>&1 &
  printf '%s\n' "$!" > "$pid_file"
)
pid="$(cat "$pid_file")"

# nohup reports success whether the session started or died on a rejected flag,
# so the log is the only evidence either way. Counted polls hold the window open
# for its whole length, which a whole-second clock reading cannot promise.
status="launched"
polls=$(( settle_seconds * 4 ))
[ "$polls" -gt 0 ] || polls=1
while [ "$polls" -gt 0 ]; do
  sleep 0.25
  if grep -q '^error:' "$log"; then
    status="rejected"
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    if grep -q '^error:' "$log"; then
      status="rejected"
    else
      status="exited"
    fi
    break
  fi
  polls=$(( polls - 1 ))
done

python3 - "$status" "$pid" "$log" "$name" "$model" "$effort" "$context" <<'PY'
import json
import shlex
import sys

status, pid, log, name, model, effort, context = sys.argv[1:]

result = {
    "status": status,
    "pid": int(pid),
    "log": log,
    "name": name,
    "model": model,
    "effort": effort,
    "context": context,
    "resume": "copilot --yolo --resume=" + shlex.quote(name),
}

if status != "launched":
    with open(log, encoding="utf-8", errors="replace") as log_file:
        result["log_head"] = "".join(log_file.readlines()[:20]).rstrip()

print(json.dumps(result, separators=(",", ":")))
PY

[ "$status" = "launched" ]
