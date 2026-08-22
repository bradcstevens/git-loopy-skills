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

chain_script="$tmp_dir/chain script.sh"
hook="$tmp_dir/git-loopy-chain.json"
printf '%s\n' '#!/usr/bin/env bash' > "$chain_script"
chmod +x "$chain_script"

python3 - "$chain_script" "$hook" <<'PY'
import json
import shlex
import sys

chain_script, hook_path = sys.argv[1:]
with open(hook_path, "w", encoding="utf-8") as hook_file:
    json.dump({
        "version": 1,
        "hooks": {
            "subagentStop": [{
                "type": "command",
                "bash": f"{shlex.quote(chain_script)} complete",
            }],
        },
    }, hook_file)
PY

if ! python3 "$VALIDATOR" "$hook"; then
  err "validator rejected a generated subagentStop hook"
fi

python3 - "$hook" "$tmp_dir/missing-chain.sh" <<'PY'
import json
import sys

hook_path, chain_script = sys.argv[1:]
with open(hook_path, "w", encoding="utf-8") as hook_file:
    json.dump({
        "version": 1,
        "hooks": {
            "subagentStop": [{
                "type": "command",
                "bash": f"{chain_script} complete",
            }],
        },
    }, hook_file)
PY

if python3 "$VALIDATOR" "$hook" >/dev/null 2>&1; then
  err "validator accepted a hook with a missing chain script"
fi

exit "$fail"
