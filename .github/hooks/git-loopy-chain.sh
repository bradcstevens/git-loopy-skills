#!/usr/bin/env bash
# Resolves the git-loopy chain script and hands the hook payload to it.
#
# The hook JSON that invokes this file is committed to the repository, so it
# cannot name an absolute path: the chain script lives wherever the skill was
# installed, which differs on every machine and does not exist at all in CI.
# A committed absolute path is therefore wrong everywhere except the machine
# that generated it, and it fails the hook validator on all the others.
#
# Called as: git-loopy-chain.sh <subcommand>
# The event payload arrives on standard input and is passed through untouched.
set -euo pipefail

subcommand="${1:?usage: git-loopy-chain.sh <subcommand>}"

candidates=(
  "${COPILOT_HOME:-$HOME/.copilot}/skills/next/chain.sh"
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/next/chain.sh"
)

for candidate in "${candidates[@]}"; do
  if [ -x "$candidate" ]; then
    exec "$candidate" "$subcommand"
  fi
done

# Exiting non-zero here would fail the hook and disrupt an agent that has
# nothing to do with the chain, so report and stand down.
echo "git-loopy chain hook: no chain.sh found; looked in ${candidates[*]}" >&2
exit 0
