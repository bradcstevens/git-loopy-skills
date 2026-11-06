# Model scorecard

Generated 2026-11-06T06:54+00:00 by `/model-scorecard`; regenerate rather than edit.
Leaderboard: https://artificialanalysis.ai/embed/llm-leaderboard, captured 2026-11-06T06:53:26+00:00: 282 current models; Jev verified 10 visible rows with 0 conflicts.
Harnesses: installed `copilot` 1.0.106-11 (subagents) and git-loopy's SDK CLI 1.0.98 (task types). Compaction triggers at 0.808 of the window.

**Score** is 1–100 fit for the role, weighted by rank (rank-order centroid): Time to first answer token 40.8 · Task-fit success 24.2 · End-to-end time 15.8 · Token appetite 10.3 · Consistency 6.1 · Output tokens/s 2.8.
**Context** is the prompt cap the recommended tier gives that model. **II** is the Intelligence Index.

## Copilot built-in subagents

Apply with `/subagents`, or `subagents.agents.<agent>` in `~/.copilot/settings.json`: `model`, `effortLevel`, `contextTier`. **Now** reads `~/.copilot/settings.json`; rubber-duck avoids the vendor of the main session model, `claude-opus-5.5`.

| Agent | Model | Effort | Context | Score | II | Runner-up | Now |
|---|---|---|---|---|---|---|---|
| explore | `gpt-6.1-sol` | low | 272K default | 82 | 34.8 | `gpt-6.1-terra` medium (77) | claude-sonnet-5.5 low default |
| task | `gpt-6.1-sol` | low | 272K default | 79 | 34.8 | `claude-sonnet-5.5` medium (73) | claude-sonnet-5.5 low default |
| general-purpose | `gpt-6.1-sol` | medium | 272K default | 71 | 46.3 | `gpt-6-astra` medium (69) | gpt-6-astra medium long_context |
| rubber-duck | `gpt-6-astra` | medium | 272K default | 71 | 51.6 | `gpt-6.1-sol` high (53) | gpt-6.1-sol high default |
| code-review | `claude-opus-5.5` | high | 200K default | 53 | 51.8 | `claude-sonnet-5.5` max (29) | claude-opus-5.5 medium long_context |
| research | `gpt-6.1-sol` | medium | 922K long_context | 72 | 46.3 | `gpt-6-astra` medium (70) | gpt-6-astra medium long_context |
| security-review | `gpt-6-astra` | medium | 272K default | 70 | 51.6 | `claude-opus-5.5` high (54) | claude-opus-5.5 medium long_context |

## git-loopy task types

Apply with `[routing.<type>]` `model` and `effort` in git-loopy's `config.toml`. `context_tier` is run-level (ADR-0017), so Context shows each model's default-tier cap. **Now** reads `~/code/github/bradcstevens/git-loopy/git-loopy/config.toml`.

| Task type | Model | Effort | Context | Score | II | Runner-up | Now |
|---|---|---|---|---|---|---|---|
| planning | `gpt-6-astra` | medium | 272K default | 71 | 51.6 | `claude-opus-5.5` high (56) | claude-opus-5.5 medium long_context |
| review | `claude-opus-5.5` | high | 200K default | 53 | 51.8 | `claude-sonnet-5.5` low (60) | claude-opus-5.5 medium long_context |
| implementation | `gpt-6.1-sol` | medium | 272K default | 71 | 46.3 | `gpt-6-astra` medium (69) | gpt-6-astra medium long_context |
| test | `gpt-6.1-sol` | medium | 272K default | 71 | 46.3 | `claude-opus-5.5` medium (62) | gpt-6-astra medium long_context |
| docs | `gpt-6-astra` | low | 272K default | 77 | 43.3 | `gpt-6.1-terra` high (68) | claude-sonnet-5.5 medium long_context |
| chore | `gpt-6.1-sol` | low | 272K default | 79 | 34.8 | `claude-sonnet-5.5` medium (73) | claude-sonnet-5.5 low long_context |
| bugfix | `gpt-6-astra` | medium | 272K default | 70 | 51.6 | `claude-opus-5.5` high (56) | claude-opus-5.5 medium long_context |

## SDLC task types

Each common software-lifecycle task maps to the role whose work it is; its row repeats that role's pick.

| Task | Covers | Role | Model | Effort | Context | Score |
|---|---|---|---|---|---|---|
| Requirements and planning | Turn a goal into a spec and sequenced tickets | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 |
| Architecture and design | Choose structure, interfaces and record decisions | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 |
| Plan critique | Stress-test a plan or design before building it | copilot:rubber-duck | `gpt-6-astra` | medium | 272K default | 71 |
| Codebase exploration | Find code and answer how-it-works questions | copilot:explore | `gpt-6.1-sol` | low | 272K default | 82 |
| Technical research | Investigate APIs, libraries and prior art with sources | copilot:research | `gpt-6.1-sol` | medium | 922K long_context | 72 |
| Feature implementation | Write new behaviour end to end | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 |
| Refactoring | Restructure code without changing behaviour | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 |
| Migrations and upgrades | Move code to a new framework, API or version | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 |
| Bug fixing | Reproduce, diagnose, repair and regress a defect | git-loopy:bugfix | `gpt-6-astra` | medium | 272K default | 70 |
| Performance work | Measure, find and remove a bottleneck | git-loopy:bugfix | `gpt-6-astra` | medium | 272K default | 70 |
| Incident triage | Diagnose a production failure under time pressure | git-loopy:bugfix | `gpt-6-astra` | medium | 272K default | 70 |
| Test authoring | Write unit, integration and regression tests | git-loopy:test | `gpt-6.1-sol` | medium | 272K default | 71 |
| Build, test and CI runs | Run suites and builds and report failures | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 |
| Code review | Find defects in a diff before it merges | copilot:code-review | `claude-opus-5.5` | high | 200K default | 53 |
| Security review | Find exploitable vulnerabilities in a change | copilot:security-review | `gpt-6-astra` | medium | 272K default | 70 |
| Documentation | Write READMEs, guides and reference docs | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 |
| Dependency and config maintenance | Bump dependencies and adjust configuration | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 |
| Release chores | Version, changelog and publish steps | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 |

## Skills

Each git-loopy-skills skill inherits its role's pick and names it in its `SKILL.md` header as `model`, `effort` and `context`, the settings to choose in `/model` before running it. The scorecard build automatically synchronizes these headers and same-named agents; **Now** records the pre-application header. Context fits the skill's own p95 main-session working set once it has 5 local runs, else its role's. **Now** reads each header under `~/code/github/bradcstevens/git-loopy-skills/skills`.

| Skill | Role | Model | Effort | Context | Score | Working set | Now |
|---|---|---|---|---|---|---|---|
| capacity | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 94K (copilot:task p95 of 27 runs) | claude-sonnet-5.5 low 200K |
| chief-of-staff | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| code-review | copilot:code-review | `claude-opus-5.5` | high | 200K default | 53 | 88K (copilot:code-review p95 of 215 runs) | claude-opus-5.5 medium 200K |
| codebase-audit | copilot:code-review | `claude-opus-5.5` | high | 200K default | 53 | 88K (copilot:code-review p95 of 215 runs) | claude-opus-5.5 medium 200K |
| codebase-design | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| create-readme | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| customize | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| deploy-model | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| design-control-loop | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| diagnosing-bugs | git-loopy:bugfix | `gpt-6-astra` | medium | 272K default | 70 | 174K (git-loopy:bugfix p95 of 19 runs) | claude-opus-5.5 medium 1M |
| domain-modeling | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| grill-me | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| grill-with-docs | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 377K (p95 of 10 /grill-with-docs runs) | claude-opus-5.5 medium 1M |
| grilling | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| handoff | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 186K (p95 of 11 /handoff runs) | claude-sonnet-5.5 low 936K |
| implement | git-loopy:implementation | `gpt-6.1-sol` | medium | 922K long_context | 71 | 401K (p95 of 54 /implement runs) | gpt-6-astra medium 1050K |
| implement-spec | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 | 204K (git-loopy:implementation p95 of 319 runs) | gpt-6-astra medium 272K |
| improve-codebase-architecture | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| jev-ultrafast | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 94K (copilot:task p95 of 27 runs) | claude-sonnet-5.5 low 200K |
| loop-me | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| mermaid-diagrams | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| microsoft-code-reference | copilot:research | `gpt-6.1-sol` | medium | 922K long_context | 72 | 233K (copilot:research profile estimate) | gpt-6-astra medium 1050K |
| microsoft-docs | copilot:research | `gpt-6.1-sol` | medium | 922K long_context | 72 | 233K (copilot:research profile estimate) | gpt-6-astra medium 1050K |
| microsoft-foundry | copilot:general-purpose | `gpt-6.1-sol` | medium | 272K default | 71 | 124K (copilot:general-purpose p95 of 52 runs) | gpt-6-astra medium 272K |
| model-scorecard | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 94K (copilot:task p95 of 27 runs) | claude-sonnet-5.5 low 200K |
| narrow-react-prop-types | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 | 204K (git-loopy:implementation p95 of 319 runs) | gpt-6-astra medium 272K |
| next | copilot:explore | `gpt-6.1-sol` | low | 922K long_context | 82 | 398K (p95 of 27 /next runs) | claude-sonnet-5.5 low 936K |
| playwright-cli | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 94K (copilot:task p95 of 27 runs) | claude-sonnet-5.5 low 200K |
| pr | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| preset | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| prototype | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 | 204K (git-loopy:implementation p95 of 319 runs) | gpt-6-astra medium 272K |
| push | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| release | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| release-assessment | copilot:task | `gpt-6.1-sol` | low | 272K default | 79 | 94K (copilot:task p95 of 27 runs) | claude-sonnet-5.5 low 200K |
| research | copilot:research | `gpt-6.1-sol` | medium | 922K long_context | 72 | 233K (copilot:research profile estimate) | gpt-6-astra medium 1050K |
| retro | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 682K (p95 of 16 /retro runs) | claude-opus-5.5 medium 1M |
| set-task-models | copilot:research | `gpt-6.1-sol` | medium | 922K long_context | 72 | 233K (copilot:research profile estimate) | gpt-6-astra medium 1050K |
| setup-git-loopy-skills | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| show-me | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| sync-model-roster | git-loopy:chore | `gpt-6.1-sol` | low | 272K default | 79 | 72K (git-loopy:chore p95 of 14 runs) | claude-sonnet-5.5 low 200K |
| tdd | git-loopy:test | `gpt-6.1-sol` | medium | 272K default | 71 | 162K (git-loopy:test p95 of 27 runs) | gpt-6-astra medium 272K |
| teach | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| to-handoff | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| to-questionnaire | git-loopy:planning | `gpt-6-astra` | medium | 272K default | 71 | 170K (git-loopy:planning profile estimate) | claude-opus-5.5 medium 1M |
| to-spec | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 472K (p95 of 7 /to-spec runs) | claude-opus-5.5 medium 1M |
| to-tickets | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 411K (p95 of 22 /to-tickets runs) | claude-opus-5.5 medium 1M |
| triage | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 378K (p95 of 5 /triage runs) | claude-opus-5.5 medium 1M |
| wait-what | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |
| wayfinder | git-loopy:planning | `gpt-6-astra` | medium | 1050K long_context | 71 | 337K (p95 of 5 /wayfinder runs) | claude-opus-5.5 medium 1M |
| wizard | git-loopy:implementation | `gpt-6.1-sol` | medium | 272K default | 71 | 204K (git-loopy:implementation p95 of 319 runs) | gpt-6-astra medium 272K |
| writing-for-agents | git-loopy:docs | `gpt-6-astra` | low | 272K default | 77 | 101K (git-loopy:docs p95 of 11 runs) | claude-sonnet-5.5 medium 200K |

## Evidence per role

| Role | II band | Benchmarks | Working set | Top three | Why |
|---|---|---|---|---|---|
| copilot:explore | 32–44 | lcr, omniscienceNonHallucination | 76K (p95 of 23 runs) | `gpt-6.1-sol` low 82, `gpt-6.1-terra` medium 77, `gpt-6-astra` low 77 | Read-only search and synthesis across many short lookups; latency decides the run. |
| copilot:task | 30–40 | terminalBench40, ifbench | 94K (p95 of 27 runs) | `gpt-6.1-sol` low 79, `claude-sonnet-5.5` medium 73, `gpt-6.1-terra` medium 73 | Runs bounded commands and reports the result faithfully. |
| copilot:general-purpose | 46–52 | terminalBench40, scicode | 124K (p95 of 52 runs) | `gpt-6.1-sol` medium 71, `gpt-6-astra` medium 69, `claude-opus-5.5` medium 62 | Autonomous multi-step coding with full tools; the same work as git-loopy implementation. |
| copilot:rubber-duck | 50–56 | hle, critpt, gdpvalNormalized | 150K (profile estimate) | `gpt-6-astra` medium 71, `gpt-6.1-sol` high 53, `gpt-6-astra` high 50; excludes Anthropic | Independent critique; a different vendor from the main session model supplies the independence. |
| copilot:code-review | 51–56 | scicode, terminalBench40, omniscienceNonHallucination | 88K (p95 of 215 runs) | `claude-opus-5.5` high 53, `claude-sonnet-5.5` max 29, `claude-sonnet-5.5` low 60; excludes OpenAI | Finds genuine defects with few false positives; reviews a different vendor's code. |
| copilot:research | 46–54 | hle, lcr, omniscienceNonHallucination, gdpvalNormalized | 233K (profile estimate) | `gpt-6.1-sol` medium 72, `gpt-6-astra` medium 70, `claude-opus-5.5` medium 61 | Searches, verifies and synthesises sources; long reads reward context reasoning and factual reliability. |
| copilot:security-review | 51–56 | scicode, terminalBench40, critpt, omniscienceNonHallucination | 188K (profile estimate) | `gpt-6-astra` medium 70, `claude-opus-5.5` high 54, `gpt-6-astra` high 50 | Finds exploitable defects without noise; a miss is silent. |
| git-loopy:planning | 51–56 | gdpvalNormalized, lcr, hle | 170K (profile estimate) | `gpt-6-astra` medium 71, `claude-opus-5.5` high 56, `gpt-6-astra` high 50 | Decides what gets built; a wrong plan passes every test. |
| git-loopy:review | 51–56 | scicode, terminalBench40, omniscienceNonHallucination | 188K (profile estimate) | `claude-opus-5.5` high 53, `claude-sonnet-5.5` low 60, `claude-sonnet-5.5` medium 55; excludes OpenAI | Judges whether work was built right, read-only: the Orchestrator alone publishes and closes (ADR-0072); cross-vendor review holds by construction (ADR-0048). |
| git-loopy:implementation | 46–52 | terminalBench40, scicode | 204K (p95 of 319 runs) | `gpt-6.1-sol` medium 71, `gpt-6-astra` medium 69, `claude-opus-5.5` medium 62 | Writes most of the code; tests make failure visible. Runs converged ~70% at II 46+ and 34% at II 34. |
| git-loopy:test | 46–51 | terminalBench40, scicode | 162K (p95 of 27 runs) | `gpt-6.1-sol` medium 71, `claude-opus-5.5` medium 62, `claude-sonnet-5.5` xhigh 54 | Authors meaningful tests and runs them; a weak test passes silently. |
| git-loopy:docs | 40–46 | lcr, omniscienceNonHallucination | 101K (p95 of 11 runs) | `gpt-6-astra` low 77, `gpt-6.1-terra` high 68, `claude-sonnet-5.5` high 64 | Source-grounded writing that doc tests check mechanically. |
| git-loopy:chore | 30–38 | terminalBench40 | 72K (p95 of 14 runs) | `gpt-6.1-sol` low 79, `claude-sonnet-5.5` medium 73, `claude-opus-5.5` low 72 | Bounded maintenance whose result is mechanically checked. |
| git-loopy:bugfix | 51–54 | terminalBench40, scicode, critpt | 174K (p95 of 19 runs) | `gpt-6-astra` medium 70, `claude-opus-5.5` high 56, `gpt-6.1-sol` xhigh 47 | Diagnosis; a weaker model ships a plausible wrong fix that goes green (ADR-0035). |

## Method

- **Candidates**: each current leaderboard variant whose name maps to a model id and effort the role's harness lists; git-loopy roles skip `max`, which git-loopy keeps as its retry rung.
- **Task-fit success** = band fit × (0.5 + 0.5 × mean of the role's benchmarks, normalised across the pool). Band fit is 1 inside the band, falls to 0 at 8 points below the floor, and to 0.5 at 20 points above the ceiling. The pick is the best-scoring in-band candidate.
- **Speed fields** are normalised across the harness's pool on a log scale; a missing value scores 0.5.
- **Context**: a subagent keeps the default tier unless its p95 working set passes the compaction trigger, then takes `long_context`. git-loopy roles use the default tier. A skill takes the subagent rule, because the Copilot CLI session that runs it chooses its own tier.
- Leaderboard latency ranks models; real agent turns think less, so read the speed fields as order, not seconds.

## Coverage gaps

- Retired on the leaderboard, so unscored: none.
- Not on the leaderboard: claude-haiku-4.5, claude-sonnet-5, gpt-5.3-codex, gpt-5.6-luna, gpt-5.6-sol, gpt-5.6-sol-fast, gpt-5.6-terra, gpt-6-sol, grok-4.6, mai-code-1.1-flash, mai-code-2-flash.
