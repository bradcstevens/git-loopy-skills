# Evidence and decisions

## Source plan

| Source ID | Starting surface | Use and qualification |
| --- | --- | --- |
| `aa` | https://artificialanalysis.ai/ | Intelligence components, terminal execution, knowledge work, context reasoning, effort, latency, output tokens. Record estimated composites. |
| `huggingface` | https://huggingface.co/spaces/ArtificialAnalysis/LLM-Performance-Leaderboard | Inspect whether it still embeds AA. A mirror is one evidence lineage, not independent corroboration. |
| `arena` | https://arena.ai/leaderboard | Separate Agent, WebDev/Code, and Text; preserve configuration, intervals, sample counts, and preliminary/AutoEval labels. |
| `benchlm` | https://benchlm.ai/ | Inspect task-specific evaluations and their originating reports. A composite or mirrored provider result is not a new independent experiment. |
| `llm-stats` | https://llm-stats.com/leaderboards/llm-leaderboard | Separate its own preference data from aggregated benchmarks. Preserve scale, effort gaps, and snapshot changes. |

Supplement with primary benchmark methods and provider effort guidance:
https://developers.openai.com/api/docs/guides/reasoning,
https://platform.claude.com/docs/en/build-with-claude/effort,
https://ai.google.dev/gemini-api/docs/thinking, and GitHub's CLI reference.
Provider API capabilities do not establish Copilot's selectable settings.

Use public HTML, documented APIs, or browser rendering when a page returns a
skeleton. Record access barriers instead of circumventing them. Match public
aliases only with a first-party mapping, retaining both names. Give each source's
access time and its stated snapshot date; unknown dates remain unknown.

For each measurement retain the exact model/variant, effort, context workload,
metric, score/unit, sample count, confidence interval, harness, evaluator,
estimated flag, URL, and a bounded supporting excerpt. Mark unavailable fields
explicitly. Preserve disagreeing snapshots instead of constructing a synthetic
head-to-head. Refresh a result used to justify a change during the current run.

Rank only licensed candidates. Show the scope of every rank. Use within-benchmark
comparisons before composites; do not average different rating scales, benchmark
versions, harnesses, retry budgets, or task splits. Small numerical differences
with overlapping uncertainty are not decisive.

## Role fit

| Role | Work to optimize | Relevant evidence |
| --- | --- | --- |
| Copilot `explore` | Targeted repository reading and synthesis | Retrieval/context reasoning, tool reliability, first-answer latency |
| Copilot `task` | Run bounded commands; report failures faithfully | Instruction fidelity and latency; terminal engineering is an upper bound on difficulty |
| Copilot `general-purpose`; git-loopy `implementation` | Autonomous coding with full tools | Repository/terminal task completion, recovery, constraints followed |
| Copilot `rubber-duck` | Independent critique of a proposed approach | Reasoning and counterexample quality; provider diversity, not chat popularity alone |
| Copilot `code-review`; git-loopy `review` | Find genuine defects and evaluate changes | Defect detection/repair evidence, false-positive discipline, repository safety constraints |
| Copilot `research` | Search, verify, and synthesize sources | Browsing, factual reliability, tool workflows, long-document reasoning and synthesis |
| Copilot `security-review` | Identify exploitable defects without noise | Defensive detection precision/recall where available; offensive benchmarks are only indirect evidence |
| git-loopy `planning` | Design and sequence implementable work | Constraint reasoning, decomposition, ambiguity management, coherent plans |
| git-loopy `test` | Author meaningful tests and run them | Test generation, mutation/bug detection, repository coding; not merely command speed |
| git-loopy `docs` | Produce accurate source-grounded documentation | Factual fidelity, code comprehension, organization, appropriate tool use |
| git-loopy `chore` | Maintenance changes with bounded risk | Instruction fidelity, dependency/config correctness, regression avoidance |
| git-loopy `bugfix` | Reproduce, diagnose, repair, and regress | Bug repair and repository execution; not the same as read-only review |

Inspect the live runner's contracts before using this matrix. Shared review
profiles inherit write-safety restrictions from git-loopy even though Copilot's
built-in reviewer is read-only. Planning is not automatically rubber-duck;
documentation is not automatically research; maintenance is not automatically
the command-running task agent.

Use component evidence and provider guidance when a direct role benchmark is
missing, label the inference, and reduce confidence. An unmeasured model is
unranked, not poor. Prefer a supported, evidenced choice over a speculative
upgrade. Price per API token is not the user's Copilot charge, and API TTFT is not
whole-agent completion time. Largest advertised context is not effective context
quality; account for actual inputs, tool history, and output/reasoning headroom.

## Manifest contract

Write one UTF-8 JSON object as `decision.json`. The guard is read-only and uses
only Python's standard library. Its inventory/source freshness limit is 24 hours;
refresh stale observations rather than rewriting their timestamps. Use
`--as-of <ISO timestamp with timezone>` only to supply the runtime's authoritative
current time, not to make stale evidence pass.

| Field | Shape |
| --- | --- |
| `schema_version` | `1` |
| `inventory` | `observed_at` (timezone-qualified ISO), `source` (runtime/picker observation), `builtin_agents` (all discovered built-ins), `models` (map below) |
| `sources` | Map including all five source IDs above; each has `url`, `accessed_at`, `status` (`ok`, `partial`, `blocked`), and `notes` including provenance/snapshot limitations |
| `evidence` | Map of evidence ID to `model`, `source` (source ID), and `finding` (measurement or qualified primary-source finding); retain the additional measurement fields described above |
| `coverage_gaps` | Map of selectable model IDs without evidence to a specific explanation |
| `profiles` | Map of profile ID to `model`, `effort` (supported string, or JSON `null` when the model exposes no effort control), `context` (`default` or `long_context`), `evidence` (non-empty evidence-ID list), `rationale`, and `confidence` (`high`, `medium`, `low`) |
| `copilot` | Map of every inventoried built-in to a profile ID |
| `git_loopy` | Map of all seven task types to profile IDs |
| `equivalence_groups` | Arrays of qualified roles, e.g. `["copilot:code-review", "git_loopy:review"]`; include both shared groups from SKILL.md |

Each inventory model has `selectable` (boolean), `efforts` (supported string
array), and `context_tiers` (supported tier array). Keep unavailable models in the
inventory if useful, but evaluate and select only entries with `selectable: true`.
For a model with no effort control, record an empty `efforts` array and use a null
profile effort; do not invent `none` support.

All members of an equivalence group reference the same profile ID. Other roles
may also share it when justified. Every selected profile must cite evidence for
its own exact model from an accessible source. Evidence can be incomplete: the
written rationale must identify proxy metrics, unknown effort, and uncertainty.
Record role contracts, active restrictions, escalation rules, and unsupported
target features alongside the manifest in `findings.md`; the mechanical guard
cannot decide whether the research supports the conclusion.

## Evidence gate

Before proceeding to application, establish all of these:

1. Every source was attempted and every selectable model has evidence or a gap.
2. At least two distinct usable evaluation lineages inform the comparison;
   mirrors and aggregators repeating an experiment count once.
3. Each role has a cited rationale and a supported triple; proposed changes
   satisfy active repository constraints, or are explicitly blocked.
4. Context and effort choices are labeled as deployment judgments where no
   controlled comparison exists. Security-review recommendations carry the
   specific limits of the available defensive evidence.
5. The current and proposed tables, same-role bindings, and confidence are saved;
   no missing score was treated as zero or a missing model replaced by a guess.
