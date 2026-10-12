---
name: model-scorecard
description: Score Copilot models 1–100 for every SDLC task type, Copilot built-in subagent and git-loopy task type from the live Artificial Analysis leaderboard, and rewrite the scorecard reference.
model: claude-sonnet-5.5
effort: low
context: 200K
disable-model-invocation: true
---

# Model scorecard

Rebuild [`references/scorecard.md`](references/scorecard.md), the **scorecard**: one Copilot model id, reasoning effort and context size (`###K`) per role, scored 1–100 for fit. Roles are the seven Copilot built-in subagents and the seven git-loopy task types; the common SDLC tasks and every skill in this repository map onto them. The scorecard reports; `/model-fit` applies settings, including each skill's `model`, `effort` and `context` header.

[`profiles.json`](profiles.json) holds each role's Intelligence Index band, benchmarks, working-set estimate and constraints, the ranked fields whose order sets the score weights, and the `skills` map that assigns each skill the role whose work it is. Retune there; the scorecard and [`references/skill-headers.json`](references/skill-headers.json) are regenerated output.

## 1. Prepare

Load `jev-ultrafast` and complete its **Prepare** section: an absolute `JEV_ULTRAFAST_HOME` and working provider credentials. Resolve the git-loopy checkout — `~/code/github/bradcstevens/git-loopy` by default; ask for the path when it is absent. Its environment carries the Copilot SDK, and its Run logs and `config.toml` feed the scorecard.

**Done:** `JEV_ULTRAFAST_HOME` imports `jev_ultrafast.Agent`, and `<git-loopy>/git-loopy/python/.venv` exists.

## 2. Build

```bash
"<skill-dir>/scripts/build.sh" --jev-home "$JEV_ULTRAFAST_HOME" --git-loopy "<git-loopy>"
```

Four stages run fail-fast. Jev opens the live leaderboard, and the embedded dataset is verified against the rows Jev sees. The SDK lists what your installed `copilot` (subagents) and git-loopy's pinned CLI (task types) offer this account. Local Copilot session logs and git-loopy Run logs give each role's p95 working set, and each skill's from the sessions a user started with `/<skill>`. The scorer ranks every selectable model@effort per role, gives each skill its role's pick with context fitted to the skill's own runs (its role's below 5 runs), and rewrites the scorecard and `skill-headers.json`. Add `--no-headless` to watch Jev.

**Done:** exit 0; the capture line shows `"jev_status": "done"` with at least 5 `rows_matched` and 0 `conflicts`; the final summary names a model, effort, context and score for every role, then counts the skills given header picks. A failed stage is the result: report its error — Jev credentials, Edge, SDK sign-in — in place of a scorecard.

## 3. Report

Read the regenerated scorecard and `git diff` it against the previous one. Report:

- the subagent, git-loopy and skill tables, with every change since the last scorecard;
- each skill whose header (**Now**) differs from its pick;
- each pick flagged `outside band` or `II estimated`, and every coverage gap;
- each role whose working set came from a profile estimate rather than local runs.

**Done:** every role's and skill's recommendation and change is reported, and the scorecard waits for the user to commit it or apply it with `/model-fit`.
