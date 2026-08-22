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

phase_boundaries_router="skills/skill-router/PHASE-BOUNDARIES.md"
phase_boundaries_next="skills/next/PHASE-BOUNDARIES.md"
if ! cmp -s "$phase_boundaries_router" "$phase_boundaries_next"; then
  err "$phase_boundaries_router and $phase_boundaries_next must be kept in sync"
fi

count=0
while IFS= read -r skill_md; do
  dir="$(dirname "$skill_md")"

  # A git-ignored skill directory is local-only: it lives in a working copy but
  # is not part of this repo, so it is not ours to validate.
  if git check-ignore -q "$dir/" 2>/dev/null; then
    continue
  fi

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
    # A relative link resolves against the directory of the file that carries
    # it, not against docs/ — otherwise every cross-link inside docs/adr/ is
    # reported missing.
    [ -f "$(dirname "$doc")/$target" ] || err "$doc links to missing $(dirname "$doc")/$target"
  done < <(grep -roE '\]\(\./[a-z0-9.-]+\.md\)' docs | sort -u)
fi

chain_hook=".github/hooks/git-loopy-chain.json"
if [ -e "$chain_hook" ]; then
  if ! python3 scripts/validate-chain-hook.py "$chain_hook"; then
    err "$chain_hook is not a valid git-loopy chain hook"
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "ok: $count skill(s) valid"
fi

scripts/test-chain.sh || fail=1
bash scripts/test-chain-hook.sh || fail=1
exit "$fail"
