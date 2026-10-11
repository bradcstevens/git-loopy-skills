# git-loopy-skills vs mattpocock/skills

How each skill in [mattpocock/skills](https://github.com/mattpocock/skills), read through the fork
[bradcstevens/mattpocock-skills](https://github.com/bradcstevens/mattpocock-skills), maps onto this
repo: the closest skill here, how far the two have drifted apart, and which upstream skills have no
counterpart here. It is organised by the folders upstream sorts its skills into — `engineering`,
`productivity`, `misc`, `in-progress` and `deprecated`.

**Compared:** the fork at `49dd158` (2026-10-09), level with upstream `main` (release 1.3.1 plus
unreleased changesets), against this repo at `231919d`. Snapshot taken 2026-10-10; both sides keep
moving. Short SHAs are upstream commits unless the text says they are this repo's, and
`mattpocock/skills#N` are upstream pull requests.

## How to read this

### Rating

| Rating | Meaning |
| --- | --- |
| **Identical** | Byte-for-byte the same `SKILL.md` and bundled files. |
| **Semi-identical** | Same instructions. The differences are cosmetic: punctuation, `CONTEXT.md` vs `GLOSSARY.md`, how one skill names another, description wording. An agent behaves the same. |
| **Minor differences** | Same process. A sentence or a few lines differ, or a bundled file has drifted; behaviour shifts at the edges. |
| **Several differences** | Same purpose and skeleton, but whole sections are added, removed or rewritten. Behaviour visibly diverges. |
| **Significant differences** | Same goal, but largely rewritten or re-platformed. Most of the text is not shared. |
| **Partial overlap** | Shares a name or a source with a skill here, but that skill does a different job. Most of what the upstream skill does is missing here. |
| **Missing** | No counterpart here. |

### Columns

- **Similarity** — word-level similarity of the two `SKILL.md` bodies (frontmatter excluded, case
  and punctuation ignored), from Python's `difflib.SequenceMatcher.ratio()`. 100% is the same words
  in the same order.
- **Kept / added** — how much of upstream's text survives, in order, in the copy here, and how much
  of the copy here is not in upstream. `96% / 34%` reads "keeps nearly all of upstream, and a third
  of it is new".
- **Invocation** — `user` (reachable only when typed: `disable-model-invocation: true`) or `model`
  (the model may reach for it on its own), upstream → here.
- **Forked from** — the upstream commit whose version of each file is closest to the copy here,
  found by comparing against every historical version of the file. *Exact copy* means
  byte-identical to that commit. Whatever upstream changed after it is drift this repo has not
  picked up.

The rating is a judgement made from reading the diffs. The numbers support it but do not decide
it, and for one-line skills they mean nothing.

### Differences that apply almost everywhere

These are not repeated per skill:

1. **Em-dashes.** Upstream removed every em-dash on 2026-08-19 (`3216582`). Every copy here
   predates that. No skill here is byte-identical to upstream, and for some the em-dashes are the
   only difference.
2. **`CONTEXT.md`, not `GLOSSARY.md`.** Upstream renamed its domain-doc convention to `GLOSSARY.md`
   / `GLOSSARY-MAP.md` (`d80fa0f`, released in 1.3.0). This repo keeps `CONTEXT.md` /
   `CONTEXT-MAP.md`, and `domain-modeling/CONTEXT-FORMAT.md`. The files are named differently; the
   process is the same.
3. **How one skill calls another.** Upstream now writes *Call the Skill tool with "x"* (`d28dfdc`,
   `fcf0071`) and stopped skills handing off to other user-invoked skills (`1dab982`). Copies here
   say "run `/x`" and hand off freely.
4. **Renamed hubs.** `/setup-matt-pocock-skills` is `/setup-git-loopy-skills` here, and `/ask-matt`
   is replaced by `/next`.
5. **The chain overlay.** Nine upstream-derived skills gain a *Record the …* section — once the
   artifact is durable (committed, pushed, published), post one evidence comment on the ticket —
   and most gain a closing line naming the skill to run next. That is what lets `/next` drive the
   flow; see [Skill connections](./skill-connections.md). `implement`, `to-spec` and `to-tickets`
   are model-invoked here, where upstream they are user-invoked.
6. **Quoted descriptions.** Upstream quotes descriptions that contain colons (`5c89081`). Cosmetic.

## Summary

| Rating | Count | Upstream skills |
| --- | --- | --- |
| Identical | 0 | — |
| Semi-identical | 5 | [codebase-design](#codebase-design), [domain-modeling](#domain-modeling), [grill-me](#grill-me), [to-questionnaire](#to-questionnaire), [loop-me](#loop-me) |
| Minor differences | 8 | [diagnosing-bugs](#diagnosing-bugs), [improve-codebase-architecture](#improve-codebase-architecture), [tdd](#tdd), [wizard](#wizard), [grilling](#grilling) (as `batch-grill-me`), [teach](#teach), [wait-what](#wait-what), [writing-for-agents](#writing-for-agents) |
| Several differences | 8 | [code-review](#code-review), [grill-with-docs](#grill-with-docs), [prototype](#prototype), [research](#research), [to-spec](#to-spec), [to-tickets](#to-tickets), [triage](#triage), [wayfinder](#wayfinder) |
| Significant differences | 4 | [ask-matt](#ask-matt) (→ `next`), [implement](#implement), [setup-matt-pocock-skills](#setup-matt-pocock-skills) (→ `setup-git-loopy-skills`), [claude-handoff](#claude-handoff) (→ `handoff`) |
| Partial overlap | 2 | [pr](#pr) (→ `show-me`), [handoff](#handoff) (→ `handoff`, a different job) |
| Missing | 11 | implement-spec, retro, git-guardrails-claude-code, migrate-to-shoehorn, scaffold-exercises, setup-pre-commit, chief-of-staff, setup-ts-deep-modules, writing-beats, writing-fragments, writing-shape — see [Missing here](#missing-here) |

Of upstream's 38 skills, 27 have a counterpart here. Two defects in this repo turned up along the
way: a [`prototype`](#prototype) reference file overwritten by its sibling, and a broken anchor in
[`wayfinder`](#wayfinder).

## Engineering

> Upstream: *"Skills I use daily for code work."* 20 skills: 11 user-invoked, 9 model-invoked.

| Upstream skill | Closest here | Rating | Similarity | Kept / added | Invocation |
| --- | --- | --- | --- | --- | --- |
| [ask-matt](#ask-matt) | `next` | Significant differences | 5% | 6% / 96% | user → model |
| [code-review](#code-review) | `code-review` | Several differences | 78% | 96% / 34% | model |
| [codebase-design](#codebase-design) | `codebase-design` | Semi-identical | 100% | 100% / 0% | model |
| [diagnosing-bugs](#diagnosing-bugs) | `diagnosing-bugs` | Minor differences | 97% | 98% / 4% | model |
| [domain-modeling](#domain-modeling) | `domain-modeling` | Semi-identical | 97% | 97% / 3% | model |
| [grill-with-docs](#grill-with-docs) | `grill-with-docs` | Several differences | — ¹ | — ¹ | user |
| [implement](#implement) | `implement` | Significant differences | 20% | 52% / 88% | user → model |
| implement-spec | — | Missing | | | user |
| [improve-codebase-architecture](#improve-codebase-architecture) | `improve-codebase-architecture` | Minor differences | 97% | 97% / 4% | user |
| [pr](#pr) | `show-me` (and `push`) | Partial overlap | 72% | 64% / 18% | model |
| [prototype](#prototype) | `prototype` | Several differences | 79% | 100% / 34% | model |
| [research](#research) | `research` | Several differences | 42% | 99% / 73% | model |
| retro | — | Missing | | | user |
| [setup-matt-pocock-skills](#setup-matt-pocock-skills) | `setup-git-loopy-skills` | Significant differences | 60% | 93% / 56% | user |
| [tdd](#tdd) | `tdd` | Minor differences | 98% | 96% / 1% | model |
| [to-spec](#to-spec) | `to-spec` | Several differences | 78% | 97% / 35% | user → model |
| [to-tickets](#to-tickets) | `to-tickets` | Several differences | 73% | 96% / 41% | user → model |
| [triage](#triage) | `triage` | Several differences | 78% | 98% / 36% | user |
| [wayfinder](#wayfinder) | `wayfinder` | Several differences | 89% | 94% / 14% | user |
| [wizard](#wizard) | `wizard` | Minor differences | 100% | 100% / <1% | model |

¹ Upstream's body is one line, so the numbers are meaningless.

### `ask-matt`

**Here:** [`next`](../skills/next/SKILL.md) · **Significant differences** ·
[upstream](https://github.com/bradcstevens/mattpocock-skills/tree/main/skills/engineering/ask-matt)

- Upstream's router is a static map of the skill set — main flow, on-ramps, codebase health,
  vocabulary, phase boundaries, standalones — that answers "which skill fits?". This repo removed
  its copy (`9a02742`, "Remove the ask skill in favour of next") and wrote `next` instead: a
  model-invoked router that reads live state (tracker, branch, diff, worktrees), names one action,
  and, when the chain gate allows, reserves and spawns it through `chain.sh` and its helpers. Skill
  choice lives in `next/SKILL-SELECTION.md`.
- **Shared:** `next/PHASE-BOUNDARIES.md` is an exact copy of `ask-matt/PHASE-BOUNDARIES.md` at
  `fa1e322` (2026-08-05); upstream has since only removed its em-dashes.
- Upstream's router also routes to `implement-spec`, `pr` and `retro`, which have no counterpart
  here.

### `code-review`

**Here:** [`code-review`](../skills/code-review/SKILL.md) · **Several differences** · forked from
`c0d6901` (2026-08-06)

- **Same core:** two parallel sub-agent reviews, Standards and Spec, of the diff since a fixed
  point, reported side by side.
- **Added here:** pins `reviewed_head` on entry and diffs against it rather than a moving `HEAD`.
  *Record the review*: refuse to publish if the worktree or PR head moved, require the head to be on
  the remote, post the findings as one ticket comment, and on a clean head emit a `review-clean`
  record through `scripts/review-clean-record.py`. Clean heads go to `/push`, findings back to
  `/implement`. Microsoft-technology code is pointed at `/microsoft-code-reference` and
  `/microsoft-docs`.
- **Upstream since:** mattpocock/skills#1208 — search the repo for every standards doc
  (`CODING_STANDARDS.md` or `CONTRIBUTING.md` must be on the list), and issue both sub-agent calls
  together, in the foreground.

### `codebase-design`

**Here:** [`codebase-design`](../skills/codebase-design/SKILL.md) · **Semi-identical** · exact
copies: `SKILL.md` at `ee8bae4` (2026-06-17), `DEEPENING.md` at `221ffca`, `DESIGN-IT-TWICE.md` at
`c0d6901`

- Never edited here. Upstream has since only removed em-dashes, and renamed `CONTEXT.md` in
  `DESIGN-IT-TWICE.md`.

### `diagnosing-bugs`

**Here:** [`diagnosing-bugs`](../skills/diagnosing-bugs/SKILL.md) · **Minor differences** · exact
copy of `bda79a3` (2026-08-06)

- Never edited here. **Upstream since:**
  - mattpocock/skills#1209 — if the red was forced by mutating code or a fixture, `diff` against a
    pristine copy to prove the mutation landed before trusting it.
  - Phase 6 lost its post-mortem hand-off to `/improve-codebase-architecture` (`1dab982`). The copy
    here still has it.

### `domain-modeling`

**Here:** [`domain-modeling`](../skills/domain-modeling/SKILL.md) · **Semi-identical** · exact
copies: `SKILL.md` at `ee8bae4` (2026-06-17), `ADR-FORMAT.md` and `CONTEXT-FORMAT.md` at `221ffca`

- Never edited here. Upstream has since renamed `CONTEXT-FORMAT.md` to `GLOSSARY-FORMAT.md`, and
  reworded the description to trigger on "discussing codebase terminology, writing or editing a
  GLOSSARY.md, or recording or editing an ADR", dropping "when another skill needs to maintain the
  domain model".

### `grill-with-docs`

**Here:** [`grill-with-docs`](../skills/grill-with-docs/SKILL.md) · **Several differences** · forked
from `658d53e` (2026-05-31)

- **Same core:** a `grilling` session using `domain-modeling`.
- **Added here:** *Record the decision* — commit the ADR or `CONTEXT.md` entry, then post one
  resolution comment on the grilled issue naming the ADR commit. Never answer your own grilling
  questions. Close the issue when nothing is left open; otherwise name the live question. A grilling
  nested inside `/triage` or `/wayfinder` records nothing of its own. Then runs `/next`.

### `implement`

**Here:** [`implement`](../skills/implement/SKILL.md) · **Significant differences** · forked from
`386d4ff` (2026-07-02)

- **Same core:** build the spec or tickets with `tdd` at agreed seams, typecheck and run single
  tests as you go, run the full suite once at the end, then review with `code-review`.
- **Changed here:** model-invoked. **Commits and pushes before review**, and the review targets that
  exact pushed head; upstream reviews first, then commits. *Record the implementation*: an evidence
  comment naming the head SHA. Never widen your own authority — stop at logins, MFA, secrets and
  consent prompts. An acceptance criterion only a human can judge leaves the ticket open.
- **Upstream since:** mattpocock/skills#1196 — fetch a passed ticket reference and state its title
  before starting, and ask if the reference is ambiguous.

### `improve-codebase-architecture`

**Here:** [`improve-codebase-architecture`](../skills/improve-codebase-architecture/SKILL.md) ·
**Minor differences** · forked from `45afd80` (2026-07-13)

- **Added here:** one line running `/next` after the grilling. `HTML-REPORT.md` is re-themed to
  **dark mode only** — dark Mermaid theme variables and a fixed slate/emerald palette, with no light
  theme.
- **Upstream since:** harness-neutral sub-agent dispatch (`14bfbbd`) and prose trims (`c0d6901`).

### `pr`

**Here:** [`show-me`](../skills/show-me/SKILL.md), and in part [`push`](../skills/push/SKILL.md) ·
**Partial overlap**

- Upstream `pr` (new on 2026-09-17, graduated in 1.3.0) is the shape of a pull request body:
  **Summary**, the smallest visual that makes the change clear; **Evidence**, before and after,
  screenshots first and execution output second; **Merge Danger**, a one-way or two-way door plus
  the blast radius.
- Its Summary guidance is Dex Horthy's HumanLayer `show-me`, credited in its `CREDITS.md`. `show-me`
  here is that same HumanLayer skill, imported directly into this repo (`83c1c4f`, 2026-09-14) and
  model-invoked — hence the 72%. It explains things visually in conversation; it does not write PR
  bodies.
- `/push` opens the pull request, but builds the body from the commit range, validation results and
  issue references, without the Summary / Evidence / Merge Danger shape.

### `prototype`

**Here:** [`prototype`](../skills/prototype/SKILL.md) · **Several differences** · forked from
`6bcbcb0` (2026-07-17)

- **Added here:** *Owning the transition, or not* — a prototype nested inside another skill records
  nothing; one invoked on its own ticket pushes the throwaway branch, posts the verdict and closes
  the ticket, or leaves it open when inconclusive. Then `/to-spec` if the verdict settles what to
  build. `LOGIC.md` is an exact copy.
- **Defect here:** `UI.md` is byte-identical to `LOGIC.md`. The UI-variations guide was overwritten
  in this repo's `f7343d1` (2026-08-12, "Add the wizard skill and settle spec terminology"), so
  "What should this look like?" questions are sent to logic-prototype instructions. The original
  survives upstream, and in this repo's history at `be5cad8:skills/prototype/UI.md`.
- **Upstream since:** em-dashes only.

### `research`

**Here:** [`research`](../skills/research/SKILL.md) · **Several differences** · forked from
`0d74d01` (2026-07-01)

- **Same core:** read high-trust primary sources and write one Markdown file, citing each claim,
  where the repo already keeps such notes.
- **Added here:** always use `/microsoft-docs` for Microsoft technologies. *Owning the transition,
  or not* — research nested inside another skill hands back its file path, commit and branch;
  research invoked on its own ticket commits the findings, posts a resolution comment and closes
  the ticket, or posts partial findings and leaves it open. Then `/to-spec` or `/implement`.
- **Upstream since:** em-dashes only.

### `setup-matt-pocock-skills`

**Here:** [`setup-git-loopy-skills`](../skills/setup-git-loopy-skills/SKILL.md) · **Significant
differences** · forked from `c66bdee` (2026-08-05)

- **Same core:** explore, then configure the issue tracker, triage labels and domain-doc layout one
  section at a time. `domain.md` and the three `issue-tracker-*.md` files are exact copies of
  `221ffca` and `a2f9333`.
- **Added here:** a fourth scaffold, **chain hooks** — `.github/hooks/git-loopy-chain.json`
  (`subagentStop` → `complete`, `agentStop` → `reenter`), a repo-relative resolver and logger, the
  bundled `git-loopy-agent-stop.py`, a check that `/next`'s `chain.sh` is installed alongside, and a
  trusted-folder warning. `triage-labels.md` adds the non-renameable `parallel-safe` and `priority`
  labels, created by `git-loopy init`.
- **Upstream since:** mattpocock/skills#1197 — create any configured triage label the tracker lacks,
  and fix the `gh` / `glab` tracker commands. External PRs are listed through the REST pulls
  endpoint (`e0efb6e`), and the tracker docs gained sub-issue operations (`cffab50`).

### `tdd`

**Here:** [`tdd`](../skills/tdd/SKILL.md) · **Minor differences** · exact copy of `8a475c4`
(2026-08-05)

- Never edited here; `mocking.md` and `tests.md` are identical to upstream today.
- **Upstream since:** mattpocock/skills#1192 — give each proposed seam a one-line note on what it
  catches and what it misses.

### `to-spec`

**Here:** [`to-spec`](../skills/to-spec/SKILL.md) · **Several differences** · forked from `a2f9333`
(2026-08-03)

- **Changed here:** model-invoked. The spec is a **planning document**, labelled `ready-for-human`
  and never `ready-for-agent`; upstream applies `ready-for-agent`. *Record the specification*: one
  evidence comment on the spec issue. Then runs `/to-tickets`.
- **Upstream since:** only the sweeps listed above.

### `to-tickets`

**Here:** [`to-tickets`](../skills/to-tickets/SKILL.md) · **Several differences** · forked from
`44eed54` (2026-07-10)

- **Changed here:** model-invoked. *Label each published ticket*: the AFK-ready label, exactly one
  `task-type:` label from a closed set of seven, and a separate `parallel-safe` decision, both also
  recorded in the ticket template. *Record the decomposition*: link every ticket to the spec as a
  native sub-issue and every blocking edge as a native `blocked_by` dependency, then post an evidence
  comment; close the spec only as cleanup. Then runs `/next`.
- **Upstream since:** tickets attached to their parent as sub-issues (`cffab50`, `9e2abf8`),
  converging with this repo, and redundant ticket-implementation instructions dropped (`ed37663`).

### `triage`

**Here:** [`triage`](../skills/triage/SKILL.md) · **Several differences** · forked from `bfdaef8`
(2026-07-29)

- **Added here:** *Planning documents are never agent-ready* — an issue titled `PRD:` or `Spec:`
  refuses or loses `ready-for-agent`, even on a maintainer override, and is routed to `/to-tickets`.
  *Record the triage outcome* for each state role. Then runs `/next`. `AGENT-BRIEF.md` and
  `OUT-OF-SCOPE.md` are exact copies of `e00eadb`.
- **Upstream since:** multi-skill steps written as separate Skill-tool calls (`447ca70`), plus the
  sweeps.

### `wayfinder`

**Here:** [`wayfinder`](../skills/wayfinder/SKILL.md) · **Several differences** · forked from
`38d62e7` (2026-07-29)

- **Added here:** a charting step that publishes the transition; *Record progress on the map*; and
  *Reaching the destination* — a map is finished only when its destination is durably met and no
  open ticket or fog remains, and a specification destination hands off to `/to-spec`.
- **Defect here:** step 6 links to `#publish-the-wayfinding-transition`, but no heading matches it;
  the section is *Record progress on the map*.
- **Upstream since:** mattpocock/skills#1181 — a map and its tickets carry only `wayfinder:` labels,
  never triage labels; cross-references are written with real ids in the second pass; research
  branches are pushed but never opened as PRs; a ticket is resolved as the type its label names.

### `wizard`

**Here:** [`wizard`](../skills/wizard/SKILL.md) · **Minor differences** · exact copies of `cb7db0e`
(2026-08-06)

- Never edited here. `SKILL.md` differs only by em-dashes, but upstream's `template.sh` has had two
  rounds of fixes since: readline, `.env` quoting, symlinks, EOF handling and the opener warning
  (`868c4cf`), then mattpocock/skills#1237.

## Productivity

> Upstream: *"General workflow tools, not code-specific."* 7 skills: 5 user-invoked, 2
> model-invoked.

| Upstream skill | Closest here | Rating | Similarity | Kept / added | Invocation |
| --- | --- | --- | --- | --- | --- |
| [grill-me](#grill-me) | `grill-me` | Semi-identical | — ¹ | — ¹ | user |
| [grilling](#grilling) | `batch-grill-me` | Minor differences | 91% | 84% / 2% | model → user |
| | `grilling` (same name) | Several differences | 88% | 86% / 11% | model |
| [handoff](#handoff) | `handoff` (a different job) | Partial overlap | 8% | 33% / 96% | user → model |
| [teach](#teach) | `teach` | Minor differences | 99% | 97% / 0% | user |
| [to-questionnaire](#to-questionnaire) | `to-questionnaire` | Semi-identical | 100% | 100% / 0% | user |
| [wait-what](#wait-what) | `wait-what` | Minor differences | 80% ² | 69% / 3% | user |
| [writing-for-agents](#writing-for-agents) | `writing-for-agents` | Minor differences | 99% | 99% / <1% | model → user |

¹ Upstream's body is one line, so the numbers are meaningless. ² A one-paragraph skill, so one
added clause moves the number a long way.

### `grill-me`

**Here:** [`grill-me`](../skills/grill-me/SKILL.md) · **Semi-identical** · exact copy of `cbf6db4`
(2026-05-31)

- One line each: "Run a `/grilling` session." here, *Call the Skill tool with "grilling".*
  upstream. Same behaviour.

### `grilling`

**Here:** [`batch-grill-me`](../skills/batch-grill-me/SKILL.md) (closest) and
[`grilling`](../skills/grilling/SKILL.md) (same name) · both forked from `a4b2009` (2026-07-16)

Upstream interviews in **rounds**. It asks the whole frontier — every question whose prerequisites
are settled — at once, in a pinned format (`❓ **Q1** - **title**`, the body, then the recommendation
after `➡️`, with a rule between questions), and words each question so "yes" accepts the
recommendation.

- **`batch-grill-me` — Minor differences.** Upstream's `grilling` as of the round-by-round rewrite,
  renamed and made user-invoked. It lacks the pinned question format (`294a2c9` through `85f83d3`)
  and the "yes accepts" wording (mattpocock/skills#1193).
- **`grilling` — Several differences.** The same fork, plus "Ask the questions one at a time …
  Asking multiple questions at once is bewildering." — which contradicts the rounds paragraph it
  keeps — and a hand-off to `/to-spec`. It lacks the same upstream additions.

### `handoff`

**Here:** [`handoff`](../skills/handoff/SKILL.md), which does a different job · **Partial overlap**

- Upstream writes a handoff **document** to the OS temp directory for a fresh agent to read —
  suggested skills, references instead of duplicated content, secrets redacted, tailored to the
  arguments — and launches nothing.
- `handoff` here **launches** a `/next` recommendation as a detached background Copilot CLI session
  through `handoff.sh`, with the model, tier and context from `/next`'s runtime line, then watches it
  to exit and routes on. It keeps the document's rules, but its upstream counterpart is
  [`claude-handoff`](#claude-handoff), not this skill.

### `teach`

**Here:** [`teach`](../skills/teach/SKILL.md) · **Minor differences** · exact copies: `SKILL.md` at
`aa024cb` (2026-06-17), the four `*-FORMAT.md` files at `2bf7005`

- Never edited here. **Upstream since:** mattpocock/skills#1183 — workspace paths resolve from the
  directory `/teach` was run in, and the correct quiz answer moves between positions.

### `to-questionnaire`

**Here:** [`to-questionnaire`](../skills/to-questionnaire/SKILL.md) · **Semi-identical** · `0f2bdbd`
(2026-07-28) with one whitespace change

- Upstream has since only removed em-dashes.

### `wait-what`

**Here:** [`wait-what`](../skills/wait-what/SKILL.md) · **Minor differences** · forked from
`50777fc` (2026-08-05)

- Description punctuation reworded here. **Upstream since:** "follow `GLOSSARY-MAP.md` to the right
  one if the repo has more than one" (`d6cd26f`); the copy here doesn't handle a repo with several
  contexts.

### `writing-for-agents`

**Here:** [`writing-for-agents`](../skills/writing-for-agents/SKILL.md) · **Minor differences** ·
forked from `f054def` (2026-07-28)

- **Changed here:** user-invoked, where upstream lets the model reach for it "when creating or
  editing skills, or modifying AGENTS.md or CLAUDE.md"; the description is reworded as a reference,
  and `CLAUDE.md` is dropped from the body. `SKILL-MECHANICS.md` differs only in whitespace.
- **Upstream since:** em-dashes only.

## Misc

> Upstream: *"Tools I keep around but rarely use, not promoted in the plugin."* 4 skills, all
> model-invoked. None is here.

| Upstream skill | Closest here | Rating |
| --- | --- | --- |
| git-guardrails-claude-code | — | Missing |
| migrate-to-shoehorn | — | Missing |
| scaffold-exercises | — | Missing |
| setup-pre-commit | — | Missing |

What each one does is in [Missing here](#missing-here).

## In progress

> Upstream's beta channel: *"excluded from the plugin and the top-level README until they
> graduate"*. 7 skills, all user-invoked. Its README lists six; `chief-of-staff` is present but
> unlisted.

| Upstream skill | Closest here | Rating | Similarity | Kept / added | Invocation |
| --- | --- | --- | --- | --- | --- |
| chief-of-staff | — | Missing | | | user |
| [claude-handoff](#claude-handoff) | `handoff` | Significant differences | 8% | 21% / 95% | user → model |
| [loop-me](#loop-me) | `loop-me` | Semi-identical | 100% | 100% / 0% | user |
| setup-ts-deep-modules | — | Missing | | | user |
| writing-beats | — | Missing | | | user |
| writing-fragments | — | Missing | | | user |
| writing-shape | — | Missing | | | user |

### `claude-handoff`

**Here:** [`handoff`](../skills/handoff/SKILL.md) · **Significant differences**

- **Same idea:** write a summary of the conversation to a temp file and launch a fresh **background**
  agent seeded with it (`claude --bg --name …`).
- **Re-platformed here** for Copilot CLI and the chain: the seed is a `/next` recommendation rather
  than a free summary, `handoff.sh` owns the detached launch, log path and proof the session
  started, and the session is watched to exit and routed on.

### `loop-me`

**Here:** [`loop-me`](../skills/loop-me/SKILL.md) · **Semi-identical** · exact copy of `bfdaef8`
(2026-07-29)

- Upstream has since only removed em-dashes. Still beta upstream, but a regular skill with a docs
  page here.

## Deprecated

Upstream's `deprecated/` folder is empty: *"a retired skill is deleted, and the changeset that
removes it names whatever replaced it."* The retirements that matter here:

- **`resolving-merge-conflicts`** was deleted upstream in 1.3.0 (mattpocock/skills#1120: *"It's no
  longer needed, and nothing replaces it"*). This repo still ships it, extended with the chain
  overlay (about 61% similar to upstream's last version), and `/next` routes merge conflicts to it.
- Earlier upstream renames are already followed here: `to-prd` → `to-spec`, `to-issues` and
  `to-plan` → `to-tickets`, `decision-mapping` → `wayfinder`, `review` → `code-review`, `diagnose` →
  `diagnosing-bugs`, `writing-great-skills` → `writing-for-agents`. None of the skills upstream
  deleted outright (`ubiquitous-language`, `design-an-interface`, `qa`, `request-refactor-plan`,
  `caveman`, `zoom-out`, `write-a-skill`, `edit-article`, `obsidian-vault`) is here either.

## Missing here

Upstream skills with no counterpart here, or only a partial one — candidates to research.

| Upstream skill | Folder · invocation | What it does | Nearest thing here | Worth knowing |
| --- | --- | --- | --- | --- |
| **implement-spec** | engineering · user | Implements a whole spec in one run: treats its tickets as a task graph, runs implementer sub-agents in their own worktrees across the ready frontier, merges each onto one integration branch through a merger sub-agent, then runs `code-review` | `/implement` works one ticket at a time; the git-loopy runner works `parallel-safe` tickets concurrently, outside this repo | Graduated in 1.3.0; upstream's router offers it as the parallel alternative to `implement` |
| **retro** | engineering · user | Looks back at a session and proposes changes to the agent's environment, most severe first: navigation pointers, automated checks (a mechanical violation gets a lint rule, pre-commit hook or CI job), coding standards, steering files, tool economy, no-ops, information access | None — `codebase-audit` audits code, not the agent's environment | Upstream's router runs it last in the main flow, after `code-review`, and after a `diagnosing-bugs` fix |
| **pr** *(partial)* | engineering · model | Shapes a PR body: Summary visual, before/after Evidence, Merge Danger | `show-me` covers the Summary visuals; `/push` opens the PR with a plain body | Could become `/push`'s PR-body format rather than a new skill. HumanLayer also publishes a `visual-pr` plugin |
| **handoff** *(partial)* | productivity · user | Writes a handoff document for a fresh agent, then stops | `handoff` here launches and watches a background session instead | The name is taken here, so it would need another |
| **chief-of-staff** | in-progress · user | Pursues a long-running goal in one session by coordinating background sub-agents and suggesting recurring schedules, on two tracks: finish the task, and improve the agents' environment for the next one | `/next` and the chain; `design-control-loop` and `build-iterated-agentic-loop` for scheduled loops | Beta, and unlisted in upstream's README |
| **setup-ts-deep-modules** | in-progress · user | Wires dependency-cruiser into a TypeScript repo so each package is a deep module, reachable only through its entry points; ships the config | `codebase-design` supplies the vocabulary, not the enforcement | TypeScript only; beta |
| **writing-fragments** | in-progress · user | Writing, explore: grills you for raw fragments and appends them to one document | `grilling` supplies the interview mechanics | First of a three-skill writing pipeline; beta |
| **writing-beats** | in-progress · user | Writing, exploit: assembles raw material into a journey of beats, one beat at a time | — | Beta |
| **writing-shape** | in-progress · user | Writing, exploit: shapes raw material into an article paragraph by paragraph, arguing format choices | — | Beta |
| **git-guardrails-claude-code** | misc · model | Installs Claude Code hooks (`scripts/block-dangerous-git.sh`) that block `push`, `reset --hard`, `clean`, `branch -D` and the like before they run | `setup-git-loopy-skills` writes Copilot CLI hooks, but for chaining, not safety | Claude Code-specific; a port would target `.github/hooks` |
| **migrate-to-shoehorn** | misc · model | Migrates test files from `as` type assertions to `@total-typescript/shoehorn` | — | TypeScript; niche |
| **scaffold-exercises** | misc · model | Scaffolds course exercise directories — sections, problems, solutions, explainers — that pass linting | — | Specific to Matt's course tooling |
| **setup-pre-commit** | misc · model | Sets up Husky pre-commit hooks with lint-staged (Prettier), type checking and tests | — | JS/TS; the kind of guardrail `retro` recommends |

## Here but not upstream

Skills here that no current upstream skill maps to:

- **`resolving-merge-conflicts`** — an upstream skill, since deleted upstream (see
  [Deprecated](#deprecated)).
- **From HumanLayer**, imported into this repo alongside `show-me` (`83c1c4f`, 2026-09-14):
  `build-iterated-agentic-loop`, `design-control-loop`, `narrow-react-prop-types`.
- **Everything else:** `push`, `release`, `model-fit`, `sync-model-roster`, `codebase-audit`,
  `create-readme`, `mermaid-diagrams`, `playwright-cli`, `jev-ultrafast`,
  `microsoft-code-reference`, `microsoft-docs`, `microsoft-foundry`.

Not counted: `azure-mcaps-resource-deployment` is git-ignored, so local only, and
`skills/git-loopy-config/` is an empty directory.

## Reproducing this comparison

```bash
gh repo clone bradcstevens/mattpocock-skills /tmp/mattpocock-skills
```

Strip the frontmatter from each `SKILL.md`, split the body into lowercase words, and compare with
`difflib.SequenceMatcher(None, upstream_words, here_words, autojunk=False).ratio()`. The closest
skill here for each upstream skill was found by scoring it against every skill here on shared
four-word runs, then confirmed by reading both. Each file's fork point is the version, among those
in `git log --follow -- <path>`, closest to the copy here.
