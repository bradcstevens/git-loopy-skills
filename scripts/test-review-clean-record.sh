#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RECORD="$REPO/scripts/review-clean-record.py"
PRODUCER="$REPO/skills/code-review/SKILL.md"
CONSUMER="$REPO/skills/next/SKILL.md"
head="0123456789abcdef0123456789abcdef01234567"

emitted="$(python3 "$RECORD" emit "$head")"
[ "$emitted" = "review-clean: head=$head" ] ||
  { echo "error: producer did not emit the canonical record" >&2; exit 1; }

printf '%s\n' "Review complete." "$emitted" |
  python3 "$RECORD" match "$head" ||
  { echo "error: gate matcher rejected the producer's record" >&2; exit 1; }

if printf '%s\n' "$emitted" | python3 "$RECORD" match \
  "fedcba9876543210fedcba9876543210fedcba98"; then
  echo "error: gate matcher accepted evidence for another head" >&2
  exit 1
fi

if printf '%s\n' "review-clean: head=$head" | python3 "$RECORD" match \
  "0123456789abcdef0123456789abcdef0123456g"; then
  echo "error: gate matcher accepted a malformed head" >&2
  exit 1
fi

python3 - "$REPO" "$head" <<'PY'
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
head = sys.argv[2]
producer = (repo / "skills/code-review/SKILL.md").read_text()
commands = re.findall(r'`(python3 [^`\n]+ emit "\$reviewed_head")`', producer)
if len(commands) != 1:
    sys.exit("error: producer must document one emit command")
command = [
    argument.replace("$SKILL_DIR", str(repo / "skills/code-review"))
    .replace("$reviewed_head", head)
    for argument in shlex.split(commands[0])
]
with tempfile.TemporaryDirectory(prefix="review-clean-") as outside:
    result = subprocess.run(command, cwd=outside, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"error: documented emit command failed outside the repo:\n{result.stderr}")
    if result.stdout != f"review-clean: head={head}\n":
        sys.exit("error: documented emit command did not emit the canonical record")

gate = (repo / "skills/next/scripts/chain.sh").read_text()
gate_path = re.search(r'^review_clean_record="([^"]+)"$', gate, re.M)
if gate_path is None:
    sys.exit("error: merge gate does not name its record source")
gate_record = Path(
    gate_path[1].replace("$script_dir", str(repo / "skills/next/scripts"))
)
if not Path(command[1]).samefile(gate_record):
    sys.exit("error: documented emitter and merge gate resolve to different scripts")
PY

grep -Fq 'scripts/review-clean-record.py' "$PRODUCER" ||
  { echo "error: producer does not cite the canonical record source" >&2; exit 1; }
grep -Fq 'scripts/review-clean-record.py' "$CONSUMER" ||
  { echo "error: merge gate does not cite the canonical record source" >&2; exit 1; }

capture_line="$(grep -nF 'reviewed_head="$(git rev-parse HEAD)"' "$PRODUCER" | cut -d: -f1)"
guard_line="$(grep -nF 'current_head="$(git rev-parse HEAD)"' "$PRODUCER" | cut -d: -f1)"
[ -n "$capture_line" ] && [ -n "$guard_line" ] && [ "$capture_line" -lt "$guard_line" ] ||
  { echo "error: producer does not pin the reviewed head before its change guard" >&2; exit 1; }
grep -Fq 'it must equal the captured `reviewed_head`' "$PRODUCER" ||
  { echo "error: producer does not refuse a changed worktree head" >&2; exit 1; }
grep -Fq 'gh pr view <pr-number> --json headRefOid --jq .headRefOid' "$PRODUCER" ||
  { echo "error: producer does not guard against a moved durable PR head" >&2; exit 1; }
grep -Fq 'emit "$reviewed_head"' "$PRODUCER" ||
  { echo "error: producer does not emit the pinned reviewed head" >&2; exit 1; }
grep -Fq '`/push` as the succeeding skill' "$PRODUCER" ||
  { echo "error: producer does not name its succeeding skill" >&2; exit 1; }
echo "ok: review-clean producer and matcher agree"
