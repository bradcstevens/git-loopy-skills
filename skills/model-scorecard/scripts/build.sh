#!/usr/bin/env bash
# Rebuild references/scorecard.md: capture -> inventory -> working sets -> score.
set -euo pipefail

usage() {
  echo "usage: build.sh --jev-home PATH --git-loopy PATH [--main-model ID] [--no-headless]" >&2
  exit 2
}

jev_home="" git_loopy="" main_model="" headless="--headless"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jev-home) jev_home="${2:?}"; shift 2 ;;
    --git-loopy) git_loopy="${2:?}"; shift 2 ;;
    --main-model) main_model="${2:?}"; shift 2 ;;
    --no-headless) headless="--no-headless"; shift ;;
    *) usage ;;
  esac
done
[ -n "$jev_home" ] && [ -n "$git_loopy" ] || usage

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
scripts="$skill_dir/scripts"
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
python3 "$scripts/score.py" --run-dir "$run_dir" --git-loopy "$git_loopy" ${main_model:+--main-model "$main_model"} --out "$skill_dir/references/scorecard.md"
echo "scorecard: $skill_dir/references/scorecard.md"
