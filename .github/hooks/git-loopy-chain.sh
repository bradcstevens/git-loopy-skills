#!/usr/bin/env bash
# Resolves the git-loopy chain script and hands the hook payload to it.
#
# The hook JSON that invokes this file is committed to the repository, so it
# cannot name an absolute path: the chain script lives wherever the skill was
# installed, which differs on every machine and does not exist at all in CI.
# A committed absolute path is therefore wrong everywhere except the machine
# that generated it, and it fails the hook validator on all the others.
#
# Called as: git-loopy-chain.sh [--event EVENT] <subcommand>
# The event payload arrives on standard input.
set -euo pipefail

event=""
if [ "${1:-}" = "--event" ]; then
  event="${2:?missing hook event}"
  shift 2
fi

subcommand="${1:?usage: git-loopy-chain.sh [--event EVENT] <subcommand>}"
if [ -z "$event" ]; then
  case "$subcommand" in
    complete) event="subagentStop" ;;
    *) event="$subcommand" ;;
  esac
fi

payload="$(cat)"
logger="$(dirname "${BASH_SOURCE[0]}")/git-loopy-hook-log.sh"

log_invocation() {
  local exit_status="$1" decision="$2"

  [ -x "$logger" ] || return 0
  "$logger" --event "$event" --exit-status "$exit_status" --decision "$decision" \
    <<< "$payload" >/dev/null 2>&1 || :
}

candidates=(
  "${COPILOT_HOME:-$HOME/.copilot}/skills/next/chain.sh"
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/next/chain.sh"
)

for candidate in "${candidates[@]}"; do
  if [ -x "$candidate" ]; then
    set +e
    if [ "$subcommand" = "reenter" ]; then
      # agentStop re-entry runs its own script, but still through the logging
      # path below: exec-ing here would skip the invocation log entirely, which
      # is the silence that log exists to remove.
      decision="$(python3 "$(dirname "${BASH_SOURCE[0]}")/git-loopy-agent-stop.py" <<< "$payload")"
    else
      decision="$("$candidate" "$subcommand" <<< "$payload")"
    fi
    chain_status=$?
    set -e

    log_invocation "$chain_status" "$decision"
    [ -z "$decision" ] || printf '%s
' "$decision"
    exit "$chain_status"
  fi
done

# Exiting non-zero here would fail the hook and disrupt an agent that has
# nothing to do with the chain, so report and stand down.
log_invocation 0 '{"decision":"stand-down","reason":"chain-not-found"}'
echo "git-loopy chain hook: no chain.sh found; looked in ${candidates[*]}" >&2
exit 0
