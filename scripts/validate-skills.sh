#!/usr/bin/env bash
set -euo pipefail

# Validates that every skill in this repo is installable by `npx skills add`:
#   - lives at skills/<name>/SKILL.md
#   - has YAML frontmatter with a name and a description
#   - has a frontmatter name matching its directory name
#   - names its GitHub Copilot model, effort and context in that frontmatter
# Also checks docs links and alignment of scorecard roles with profiles/.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

fail=0
err() {
  echo "error: $1" >&2
  fail=1
}

for reference in PHASE-BOUNDARIES.md SKILL-SELECTION.md; do
  [ -f "skills/next/references/$reference" ] || err "skills/next/references/$reference must be co-installed with next"
done

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

  # Every skill names the GitHub Copilot model, reasoning effort and context size
  # to run it with. /set-task-models writes them from /model-scorecard's picks.
  model="$(printf '%s\n' "$frontmatter" | sed -n 's/^model:[[:space:]]*//p' | head -1)"
  effort="$(printf '%s\n' "$frontmatter" | sed -n 's/^effort:[[:space:]]*//p' | head -1)"
  context="$(printf '%s\n' "$frontmatter" | sed -n 's/^context:[[:space:]]*//p' | head -1)"
  [[ "$model" =~ ^[a-z0-9][a-z0-9.-]*$ ]] ||
    err "$skill_md frontmatter 'model' must be a GitHub Copilot model id, not '$model'"
  [[ "$effort" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] ||
    err "$skill_md frontmatter 'effort' must be a reasoning effort, not '$effort'"
  [[ "$context" =~ ^[0-9]+[KM]$ ]] ||
    err "$skill_md frontmatter 'context' must be a context size such as 200K or 1M, not '$context'"
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
python3 scripts/test-chain-entry.py || fail=1
bash scripts/test-link-skills.sh || fail=1
bash scripts/test-chain-hook.sh || fail=1
bash scripts/test-hook-log.sh || fail=1
bash scripts/test-review-clean-record.sh || fail=1
bash scripts/test-handoff.sh || fail=1
python3 scripts/test-next-runtime.py || fail=1
python3 scripts/test-plan-handoff.py || fail=1
python3 scripts/test-planning-guidance.py || fail=1
python3 scripts/test-set-task-models.py || fail=1
python3 scripts/test-model-scorecard.py || fail=1
python3 scripts/validate-profile-roles.py || fail=1
python3 scripts/test-profile-roles.py || fail=1
python3 scripts/test-next-sessions.py || fail=1
python3 scripts/test-upstream-sync.py || fail=1
python3 scripts/test-load-guidance.py || fail=1
python3 scripts/test-implement-spec.py || fail=1
python3 scripts/test-skill-sync.py || fail=1
python3 scripts/test-pr-guidance.py || fail=1
exit "$fail"
