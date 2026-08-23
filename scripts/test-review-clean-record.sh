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
echo "ok: review-clean producer and matcher agree"
