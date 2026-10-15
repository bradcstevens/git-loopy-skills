---
name: model-scorecard
description: Score Copilot models 1–100 for every SDLC task type, Copilot built-in subagent and git-loopy task type from the live Artificial Analysis leaderboard, and rewrite the scorecard reference.
model: claude-sonnet-5.5
effort: low
context: 200K
disable-model-invocation: true
---

# Model scorecard

Rebuild [`references/scorecard.md`](references/scorecard.md), the **scorecard**: one Copilot model id, reasoning effort and context size (`###K`) per role, scored 1–100 for fit. Roles are the seven Copilot built-in subagents and the seven git-loopy task types; the common SDLC tasks and every skill in this repository map onto them. Each successful build automatically applies the skill picks to `skills/**/SKILL.md` and matching `.github/agents/<skill>.agent.md` files. Built-in subagent and git-loopy settings remain recommendations; `/set-task-models` applies those settings.

[`profiles.json`](profiles.json) holds each role's Intelligence Index band, benchmarks, working-set estimate and constraints, the ranked fields whose order sets the score weights, and the `skills` map that assigns each skill the role whose work it is. Retune there; the scorecard and [`references/skill-headers.json`](references/skill-headers.json) are regenerated output.

## 1. Prepare

Load `jev-ultrafast` and complete its **Prepare** section: an absolute `JEV_ULTRAFAST_HOME` and working provider credentials. Resolve the git-loopy checkout — `~/code/github/bradcstevens/git-loopy` by default; ask for the path when it is absent. Its environment carries the Copilot SDK, and its Run logs and `config.toml` feed the scorecard.

**Done:** `JEV_ULTRAFAST_HOME` imports `jev_ultrafast.Agent`, and `<git-loopy>/git-loopy/python/.venv` exists.

Resolve the git-loopy-skills checkout too. The build defaults to the repository containing this skill (following symlinks); when running an independently installed copy, pass `--skills-repo <checkout>`. It must contain `skills/set-task-models/sync_skill_headers.py`. Preserve unrelated edits and inspect the target skill headers and agents before running.

## 2. Build

```bash
"<skill-dir>/scripts/build.sh" --jev-home "$JEV_ULTRAFAST_HOME" --git-loopy "<git-loopy>"
```

Five stages run fail-fast. Jev opens the live leaderboard, and the embedded dataset is verified against the rows Jev sees. The SDK lists what your installed `copilot` (subagents) and git-loopy's pinned CLI (task types) offer this account. Local Copilot session logs and git-loopy Run logs give each role's p95 working set, and each skill's from the sessions a user started with `/<skill>`. The scorer ranks every selectable model@effort per role, gives each skill its role's pick with context fitted to the skill's own runs (its role's below 5 runs), and rewrites the scorecard and `skill-headers.json`. The final stage runs `sync_skill_headers.py --write` against those freshly generated picks. Add `--no-headless` to watch Jev.

Agents use the skill's exact name, `model` and `reasoning-effort`, plus context metadata and a generated CLI command with `--model`, `--reasoning-effort` and `--context`. Context metadata does not configure the runtime: use that command to guarantee the requested tier. Existing agent instructions and unrelated metadata survive; the `*-agent` chain carriers are not renamed or rewritten. New agents inherit the skill's invocation flags. Git-ignored local skills are excluded.

**Done:** exit 0; the capture line shows `"jev_status": "done"` with at least 5 `rows_matched` and 0 `conflicts`; the final summary names a model, effort, context and score for every role, then counts the synchronized skill headers and agents. A failed stage is the result: report its error — Jev credentials, Edge, SDK sign-in, projection — instead of claiming completion. A projection failure may leave regenerated references; report these as unapplied, and any explicitly reported partial writes.

## 3. Report

Read the regenerated scorecard and `git diff` it against the previous one. Report:

- the subagent, git-loopy and skill tables, with every change since the last scorecard;
- each skill and agent changed by the projection (**Now** in the scorecard records the pre-application header);
- each pick flagged `outside band` or `II estimated`, and every coverage gap;
- each role whose working set came from a profile estimate rather than local runs.

**Done:** every role's and skill's recommendation and change is reported, the skill headers and agents match the generated picks, and the changes wait for the user to commit. Do not change global settings or the current session's model, effort or context.
