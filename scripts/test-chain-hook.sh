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

exit "$fail"
