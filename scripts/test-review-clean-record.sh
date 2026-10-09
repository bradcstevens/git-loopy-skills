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
