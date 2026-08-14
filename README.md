# git-loopy skills

Agent skills for git-loopy: an engineering workflow from idea to ship.

Every skill is a directory under [`skills/`](skills) containing a `SKILL.md`. They install into any
agent supported by the [`skills` CLI](https://www.skills.sh) — GitHub Copilot CLI, Claude Code,
Codex, Cursor, and others.

The engineering workflow here is primarily inspired by
[mattpocock/skills](https://github.com/mattpocock/skills), adapted and extended for this toolchain.
These skills are in turn sourced into and used by
[git-loopy](https://github.com/bradcstevens/git-loopy) — see [Provenance](#provenance).

## Install

```bash
# every skill in this repo
npx skills add bradcstevens/git-loopy-skills

# a single skill
npx skills add bradcstevens/git-loopy-skills --skill=next

# see what's here without installing anything
npx skills add bradcstevens/git-loopy-skills --list
```

Installs land in the current project by default (`.agents/skills/` for GitHub Copilot, Codex and
Cursor; `.claude/skills/` for Claude Code). Add `-g` to install globally for your user, and
`-a <agent>` to target one agent:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=next -g -a github-copilot -y
```

To pull down later changes:

```bash
npx skills update
```

## Start here

Two skills are worth installing first:

- **[`next`](docs/next.md)** — the router. It reads the live state of your work and names the one
  action to take now, the skill that performs it, and the exact invocation. Model-invoked, so the
  agent reaches for it on its own; you can also ask for `/next` directly.
- **[`/setup-agent-skills`](docs/setup-agent-skills.md)** — run once per repo, before the first use
  of any other engineering skill. It records where your issues live, what your triage labels are
  called, and where domain docs sit; the rest of the skills read that config.

The main flow runs idea → ship: `/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement` →
`/code-review`. Everything else is either an on-ramp onto that flow or a standalone you reach for on
its own.

## Skills

Skills marked `automatic` are model-invoked — the agent reaches for them on its own when the
situation matches. The rest you invoke by name.

<!-- skills:start -->

| Skill | Invoke | What it does |
| --- | --- | --- |
| batch-grill-me | `/batch-grill-me` | A relentless interview that asks every frontier question at once, round by round. |
| [code-review](docs/code-review.md) | automatic | Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes — Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). |
| codebase-audit | automatic | Deep audit before GitHub push: removes junk files, dead code, security holes, and optimization issues. |
| [codebase-design](docs/codebase-design.md) | automatic | Shared vocabulary for designing deep modules. |
| [continuation](docs/continuation.md) | automatic | Present git-loopy's published Continuation guidance, reconciled from durable records. |
| [copilot-handoff](docs/copilot-handoff.md) | `/copilot-handoff` | Hand the current conversation off to a fresh background GitHub Copilot CLI session that picks up the work immediately. |
| create-readme | automatic | Create a README.md file for the project |
| [diagnosing-bugs](docs/diagnosing-bugs.md) | automatic | Diagnosis loop for hard bugs and performance regressions. |
| [domain-modeling](docs/domain-modeling.md) | automatic | Build and sharpen a project's domain model. |
| grill-me | `/grill-me` | A relentless interview to sharpen a plan or design. |
| [grill-with-docs](docs/grill-with-docs.md) | `/grill-with-docs` | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| [grilling](docs/grilling.md) | automatic | Grill the user relentlessly about a plan, decision, or idea. |
| [handoff](docs/handoff.md) | `/handoff` | Compact the current conversation into a handoff document for another agent to pick up. |
| [implement](docs/implement.md) | `/implement` | Implement a piece of work based on a spec or set of tickets. |
| [improve-codebase-architecture](docs/improve-codebase-architecture.md) | `/improve-codebase-architecture` | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| [loop-me](docs/loop-me.md) | `/loop-me` | Grill me about specs for the workflows I want to build, within this workspace. |
| microsoft-code-reference | automatic | Look up Microsoft API references, find working code samples, and verify SDK code is correct. |
| microsoft-docs | automatic | Understand Microsoft technologies by querying official documentation. |
| microsoft-foundry | automatic | Deploy, evaluate, and manage Foundry agents end-to-end: Docker build, ACR push, hosted/prompt agent create, container start, batch eval, continuous eval, prompt optimizer workflows, agent.yaml, dataset curation from traces. |
| [next](docs/next.md) | automatic | Route the engineering workflow from live project state. |
| playwright-cli | automatic | Automates browser interactions for web testing, form filling, screenshots, and data extraction. |
| [prototype](docs/prototype.md) | automatic | Build a throwaway prototype to answer a design question. |
| push | `/push` | Publish current work by staging intended changes, committing, pushing, and opening a pull request when needed. |
| [research](docs/research.md) | automatic | Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. |
| [resolving-merge-conflicts](docs/resolving-merge-conflicts.md) | automatic | Use when you need to resolve an in-progress git merge/rebase conflict. |
| [setup-agent-skills](docs/setup-agent-skills.md) | `/setup-agent-skills` | Configure this repo for the engineering skills — set up its issue tracker, triage label vocabulary, and domain doc layout. |
| [tdd](docs/tdd.md) | automatic | Test-driven development. |
| [teach](docs/teach.md) | `/teach` | Teach the user a new skill or concept, within this workspace. |
| [to-questionnaire](docs/to-questionnaire.md) | `/to-questionnaire` | Turn a decision you can't fully answer into a questionnaire for someone else to fill in. |
| [to-spec](docs/to-spec.md) | `/to-spec` | Turn the current conversation into a spec and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed. |
| [to-tickets](docs/to-tickets.md) | `/to-tickets` | Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker — edges as text in one file per ticket locally, or native blocking links on a real tracker. |
| [triage](docs/triage.md) | `/triage` | Move issues and external PRs through a state machine of triage roles — categorise, verify, grill if needed, and write agent-ready briefs. |
| [wait-what](docs/wait-what.md) | `/wait-what` | Stop — that last message did not land, so re-pitch it. |
| [wayfinder](docs/wayfinder.md) | `/wayfinder` | Plan a huge chunk of work — more than one agent session can hold — as a shared map of decision tickets on your issue tracker, and resolve them one at a time until the way to the destination is clear. |
| wizard | automatic | Generate an interactive bash wizard that walks a human through steps only they can perform. |
| [writing-for-agents](docs/writing-for-agents.md) | automatic | Writing documents for agents. |
| writing-great-skills | `/writing-great-skills` | Reference for writing and editing skills well — the vocabulary and principles that make a skill predictable. |

<!-- skills:end -->

## Repo layout

```
skills/<name>/SKILL.md    the skill itself — this is what `npx skills add` installs
skills/<name>/agents/     per-agent interface and policy overrides
docs/<name>.md            the long-form write-up: what it does, when to reach for it, where it fits
scripts/                  maintainer tooling (see below)
```

## Development

```bash
scripts/validate-skills.sh    # check frontmatter, naming and docs links
node scripts/build-readme.mjs # regenerate the skill index above
scripts/list-skills.sh        # list every SKILL.md path
scripts/link-skills.sh        # symlink all skills into ~/.copilot/skills for local testing
```

`scripts/link-skills.sh` is a maintainer convenience for working on skills in place — it symlinks
this repo into the agent skills directory, so a `git pull` is enough to pick up changes. It is not a
supported installer; use `npx skills add` for that.

## Provenance

**Upstream inspiration — [mattpocock/skills](https://github.com/mattpocock/skills).** The
engineering set here (the idea → ship flow, the grill/spec/tickets/implement/review chain, and the
deep-module and domain vocabulary that runs underneath it) is primarily inspired by that repo, which
is MIT licensed. Skills have been renamed, rewritten, and extended for this toolchain — most
visibly, its `/ask` router is replaced by the state-reading [`next`](docs/next.md), and
`/setup-matt-pocock-skills` by [`setup-agent-skills`](docs/setup-agent-skills.md). Anything Azure,
Microsoft, or Copilot-CLI specific originates here rather than upstream.

**Downstream consumer — [git-loopy](https://github.com/bradcstevens/git-loopy).** This repo is the
source of record for the skills; git-loopy — the Ralph AFK coding loop starter kit for the GitHub
Copilot CLI — sources them in and drives them from its autonomous implementation runners. Changes
land here first and flow to git-loopy from there.

Some skills carry git-loopy's **Workflow Continuation contract**: they hand a typed request to
git-loopy's own `git-loopy continuation` command, so the next session reads a record of what
happened rather than reconstructing one. Those are `code-review`, `continuation`, `grill-with-docs`,
`implement`, `prototype`, `push`, `research`, `resolving-merge-conflicts`, `to-spec`, `to-tickets`,
`triage` and `wayfinder`. Eleven of them publish a record when they finish a transition they own;
`continuation` is the reader — it reconciles those records into one recommendation and writes
nothing.
Each carries its request as a fenced JSON template behind a
`<!-- continuation-request: NAME -->` marker, and git-loopy's test suite executes those exact
templates against the real command — so a template edited here is a contract change there, and this
repo is still where it is authored. Without a git-loopy distribution installed, the rest of each
skill stands on its own; only the step that runs the command needs it. The contract itself is
specified in git-loopy's `docs/continuation-contract.md`.

## License

[MIT](LICENSE). Portions are derived from
[mattpocock/skills](https://github.com/mattpocock/skills), also MIT licensed; its copyright notice
is retained in [LICENSE](LICENSE).
