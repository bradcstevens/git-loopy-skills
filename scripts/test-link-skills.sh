#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
tmp_dir="$(cd "$tmp_dir" && pwd -P)"
trap 'rm -rf "$tmp_dir"' EXIT
fail=0

err() {
  echo "error: $1" >&2
  fail=1
}

checkout="$tmp_dir/checkout with spaces"
home="$tmp_dir/home"
mkdir -p "$checkout/scripts" "$checkout/skills/example/nested" "$checkout/.github/agents"
cp "$REPO/scripts/link-skills.sh" "$checkout/scripts/"
cp "$REPO/.github/agents/"*.agent.md "$checkout/.github/agents/"
touch "$checkout/skills/example/SKILL.md" "$checkout/skills/example/nested/SKILL.md"
printf 'retired profile\n' > "$checkout/.github/agents/retired.agent.md"

run_linker() {
  HOME="$home" bash "$checkout/scripts/link-skills.sh" > "$tmp_dir/linker.stdout"
}

run_linker
for source in "$checkout/.github/agents/"*.agent.md; do
  target="$home/.copilot/agents/$(basename "$source")"
  if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$source" ] || [ ! -f "$target" ]; then
    err "$(basename "$source") was not linked to the invoking checkout"
  fi
done
for destination in "$home/.copilot/skills" "$home/.config/git-loopy/skills"; do
  [ "$(readlink "$destination/example")" = "$checkout/skills/example" ] ||
    err "example skill was not linked into $destination"
  [ -f "$destination/example/nested/SKILL.md" ] || err "nested skill was not installed"
  [ ! -e "$destination/nested" ] || err "nested skill was flattened"
done

agents="$home/.copilot/agents"
rm "$agents/wayfinder.agent.md"
printf 'stale profile\n' > "$agents/wayfinder.agent.md"
printf 'personal profile\n' > "$agents/personal.agent.md"
mkdir "$tmp_dir/elsewhere"
printf 'external profile\n' > "$tmp_dir/elsewhere/external.agent.md"
ln -s "$tmp_dir/elsewhere/external.agent.md" "$agents/external.agent.md"
ln -s "$tmp_dir/elsewhere/missing.agent.md" "$agents/external-missing.agent.md"
rm "$agents/research-agent.agent.md"
ln -s "$tmp_dir/elsewhere/external.agent.md" "$agents/research-agent.agent.md"
rm "$agents/push-agent.agent.md"
ln -s "$tmp_dir/elsewhere/missing.agent.md" "$agents/push-agent.agent.md"
rm "$checkout/.github/agents/retired.agent.md"
relative_agents="../../../checkout with spaces/.github/agents"
ln -s "$relative_agents/retired-relative.agent.md" "$agents/retired-relative.agent.md"

run_linker
[ -L "$agents/wayfinder.agent.md" ] &&
  [ "$(readlink "$agents/wayfinder.agent.md")" = "$checkout/.github/agents/wayfinder.agent.md" ] ||
  err "stale real profile was not replaced by its checkout link"
[ "$(cat "$agents/personal.agent.md")" = "personal profile" ] ||
  err "unrelated real profile was changed"
for name in external research-agent; do
  [ "$(readlink "$agents/$name.agent.md")" = "$tmp_dir/elsewhere/external.agent.md" ] ||
    err "$name link pointing elsewhere was changed"
done
[ "$(readlink "$agents/external-missing.agent.md")" = "$tmp_dir/elsewhere/missing.agent.md" ] ||
  err "dangling external link was changed"
[ "$(readlink "$agents/push-agent.agent.md")" = "$tmp_dir/elsewhere/missing.agent.md" ] ||
  err "same-name dangling external link was changed"
for name in retired retired-relative; do
  [ ! -L "$agents/$name.agent.md" ] || err "$name checkout link was not pruned"
done

snapshot_home() {
  python3 - "$home" <<'PY'
import os
import sys

for directory, dirs, files in os.walk(sys.argv[1]):
    dirs.sort()
    for name in sorted(dirs + files):
        path = os.path.join(directory, name)
        stat = os.lstat(path)
        print(path, stat.st_ino, stat.st_mtime_ns, stat.st_ctime_ns)
PY
}

before="$(snapshot_home)"
run_linker
[ "$(snapshot_home)" = "$before" ] || err "a repeat run changed the installed home"

guard_home="$tmp_dir/guard-home"
mkdir -p "$guard_home/.copilot"
ln -s "$checkout/.github/agents" "$guard_home/.copilot/agents"
if HOME="$guard_home" bash "$checkout/scripts/link-skills.sh" > "$tmp_dir/guard.stdout" 2> "$tmp_dir/guard.stderr"; then
  err "agent destination pointing into the checkout was accepted"
fi
grep -q "symlink into this repo" "$tmp_dir/guard.stderr" ||
  err "unsafe agent destination did not report its error"
for source in "$checkout/.github/agents/"*.agent.md; do
  [ ! -L "$source" ] || err "unsafe destination overwrote a checkout profile"
done

collision_home="$tmp_dir/collision-home"
mkdir -p "$collision_home/.copilot/agents/wayfinder.agent.md"
printf 'keep\n' > "$collision_home/.copilot/agents/wayfinder.agent.md/keep"
if HOME="$collision_home" bash "$checkout/scripts/link-skills.sh" > "$tmp_dir/collision.stdout" 2> "$tmp_dir/collision.stderr"; then
  err "directory occupying an agent profile path was accepted"
fi
grep -q "directory, not an agent profile" "$tmp_dir/collision.stderr" ||
  err "agent directory collision did not report its error"
[ "$(cat "$collision_home/.copilot/agents/wayfinder.agent.md/keep")" = "keep" ] ||
  err "agent directory collision removed unrelated contents"

if [ "$fail" -eq 0 ]; then
  echo "ok: maintainer links install and reconcile skills and custom agents safely"
fi
exit "$fail"
