#!/usr/bin/env bash
# Rebuild the scorecard and project its picks into skill headers and named agents.
set -euo pipefail

usage() {
  echo "usage: build.sh --jev-home PATH --git-loopy PATH [--skills-repo PATH] [--main-model ID] [--no-headless]" >&2
  exit 2
}

jev_home="" git_loopy="" skills_repo="" main_model="" headless="--headless"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jev-home) jev_home="${2:?}"; shift 2 ;;
    --git-loopy) git_loopy="${2:?}"; shift 2 ;;
    --skills-repo) skills_repo="${2:?}"; shift 2 ;;
    --main-model) main_model="${2:?}"; shift 2 ;;
    --no-headless) headless="--no-headless"; shift ;;
    *) usage ;;
  esac
done
[ -n "$jev_home" ] && [ -n "$git_loopy" ] || usage

skill_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
scripts="$skill_dir/scripts"
skills_repo="${skills_repo:-$(cd "$skill_dir/../.." && pwd -P)}"
sync_script="$skills_repo/skills/set-task-models/sync_skill_headers.py"
if [ ! -f "$sync_script" ]; then
  echo "error: missing $sync_script; pass --skills-repo with the git-loopy-skills checkout" >&2
  exit 2
fi
sdk_project="$git_loopy/git-loopy/python"
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/model-scorecard.XXXXXX")"
echo "run dir: $run_dir"

echo "== capture leaderboard (Jev)"
python3 "$scripts/capture_leaderboard.py" --jev-home "$jev_home" --out "$run_dir/leaderboard.json" "$headless"

echo "== inventory harnesses"
uv run --project "$sdk_project" --no-sync python "$scripts/list_models.py" --harness copilot-cli --out "$run_dir/models-copilot.json"
uv run --project "$sdk_project" --no-sync python "$scripts/list_models.py" --harness sdk --out "$run_dir/models-git-loopy.json"

echo "== measure working sets"
python3 "$scripts/measure_context.py" --git-loopy "$git_loopy" --out "$run_dir/working-sets.json"

echo "== score"
python3 "$scripts/score.py" --run-dir "$run_dir" --git-loopy "$git_loopy" --skills-root "$skills_repo/skills" ${main_model:+--main-model "$main_model"} --out "$skill_dir/references/scorecard.md"
echo "== synchronize skill headers and agents"
python3 "$sync_script" --skills-repo "$skills_repo" --headers "$skill_dir/references/skill-headers.json" --write
echo "scorecard: $skill_dir/references/scorecard.md"
