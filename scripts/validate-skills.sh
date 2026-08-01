#!/usr/bin/env bash
set -euo pipefail

# Validates that every skill in this repo is installable by `npx skills add`:
#   - lives at skills/<name>/SKILL.md
#   - has YAML frontmatter with a name and a description
#   - has a frontmatter name matching its directory name
# Also checks that relative links between docs/*.md resolve.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

fail=0
err() {
  echo "error: $1" >&2
  fail=1
}

count=0
while IFS= read -r skill_md; do
  dir="$(dirname "$skill_md")"
  count=$((count + 1))

  if [ "$(head -1 "$skill_md")" != "---" ]; then
    err "$skill_md does not start with YAML frontmatter"
    continue
  fi

  frontmatter="$(awk 'NR==1 && $0=="---" {next} /^---$/ {exit} {print}' "$skill_md")"
  name="$(printf '%s\n' "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  description="$(printf '%s\n' "$frontmatter" | sed -n 's/^description:[[:space:]]*//p' | head -1)"

  [ -n "$name" ] || err "$skill_md frontmatter is missing 'name'"
  [ -n "$description" ] || err "$skill_md frontmatter is missing 'description'"

  # Nested skills are addressed by their own directory name, so the check applies
  # at every level, not just to top-level skills.
  expected="$(basename "$dir")"
  if [ -n "$name" ] && [ "$name" != "$expected" ]; then
    err "$skill_md frontmatter name '$name' does not match directory '$expected'"
  fi
done < <(find skills -name SKILL.md -not -path '*/node_modules/*' | sort)

[ "$count" -gt 0 ] || err "no skills found under skills/"

if [ -d docs ]; then
  while IFS= read -r line; do
    doc="${line%%:*}"
    target="$(printf '%s\n' "${line#*:}" | sed -E 's/^\]\(\.\///; s/\)$//')"
    [ -f "docs/$target" ] || err "$doc links to missing docs/$target"
  done < <(grep -roE '\]\(\./[a-z0-9.-]+\.md\)' docs | sort -u)
fi

if [ "$fail" -eq 0 ]; then
  echo "ok: $count skill(s) valid"
fi
exit "$fail"
