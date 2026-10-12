# Sync rules

How a skill synced from mattpocock/skills is written here. This file is the single source of these
rules for the upstream-sync loop; spec #85 recorded the same decisions for the first sync.

## Scope

- In scope: upstream's `engineering/` and `productivity/` buckets, and the upstream skills
  `.github/upstream-sync.json` lists under `also_in_scope` or maps through `renames`.
- Out of scope: the rest of `misc/` and `in-progress/`. A spec names them under *Out of Scope*;
  nothing tickets them.
- Not synced: skills with no upstream counterpart (`release`, `set-task-models`, `sync-model-roster`,
  `codebase-audit`, `create-readme`, `mermaid-diagrams`, `playwright-cli`, `jev-ultrafast`, the
  `microsoft-*` skills, `design-control-loop`, `narrow-react-prop-types`, `show-me`, and any later
  local-only skill). `/push` changes only where a ticket says so.
- Upstream repository machinery is never copied: changesets, publishing, bucket READMEs, `SCOPE.md`,
  `.out-of-scope/`.

## Kept here on purpose

These are the only differences a synced file may keep. An evidence comment names each remaining
hunk by one of these headings.

- **Skill names.** `next` (upstream `ask-matt`), `setup-git-loopy-skills` (upstream
  `setup-matt-pocock-skills`), and `handoff` (the background launcher, upstream's `claude-handoff`
  re-platformed). Upstream's document-writing `handoff` lives here as `to-handoff`.
- **The chain overlay.** The *Record the ...* and *Owning the transition* sections, evidence
  comments, and closing hand-offs through `/next`, plus what the chain depends on: code-review's
  `reviewed_head` pin and `review-clean` record, and implement committing and pushing before review.
- **git-loopy runner integration.** to-tickets gives each ticket `ready-for-agent`, exactly one
  `task-type:` label and a separate `parallel-safe` decision; specs are labelled `ready-for-human`;
  triage never makes a planning document agent-ready.
- **Invocation the chain needs.** `implement`, `to-spec` and `to-tickets` stay model-invoked. Every
  other skill follows upstream.
- **Microsoft additions.** code-review and research point at `/microsoft-docs` and
  `/microsoft-code-reference`.
- **The dark-mode-only HTML report** in improve-codebase-architecture.

## Taken from upstream

- **No em-dashes** anywhere in a synced file, overlay text included. Rewrite the sentence; never swap
  the character for another.
- **Cross-skill calls** read *Call the Skill tool with "x"*, one skill per call. A user-invoked skill
  is never called that way: tell the user to run `/x`.
- **`GLOSSARY.md` and `GLOSSARY-MAP.md`**, not `CONTEXT.md` and `CONTEXT-MAP.md`; domain-modeling's
  format reference is `GLOSSARY-FORMAT.md`.
- **Descriptions and `agents/openai.yaml`** follow upstream, quoting included.
- **Docs pages** are re-synced from upstream's page for the same skill, keeping this repo's
  Quickstart header and Source link, pointing skill links at this repo's pages, and describing the
  overlay where it applies.

## Claude Code to GitHub Copilot CLI

| Upstream says | Here |
| --- | --- |
| `CLAUDE.md` | `AGENTS.md` or `.github/copilot-instructions.md` |
| `~/.claude/` (global `CLAUDE.md`, settings, skills) | `~/.copilot/` (`copilot-instructions.md`, `instructions/*.instructions.md`, `settings.json`, `skills/`) |
| `.claude/settings.json` | `.github/copilot/settings.json` |
| `.claude/skills/` | `.github/skills/` |
| Claude Code hooks | `.github/hooks/*.json` |
| `.claude-plugin/plugin.json`, `marketplace.json` | `.github/plugin/plugin.json`, `.github/plugin/marketplace.json` |
| `claude --bg --name ...`, `claude agents` | `/handoff`'s detached `copilot -p ... -n ...`, `copilot --resume` |
| Claude Code session transcripts | `~/.copilot/session-state/<id>/events.jsonl`, `/chronicle` |
| Scheduled tasks | Copilot CLI `/every` schedules |
| "Claude" as a harness in examples | "Copilot CLI" |
| `/setup-matt-pocock-skills`, `/ask-matt` | `/setup-git-loopy-skills`, `/next` |

Copilot CLI honours `disable-model-invocation` and `argument-hint`, so frontmatter carries over.

## Layout and retirements

- Skills stay flat: `skills/<name>/`. git-loopy pins this repo with `skills_directory: skills`, and
  the chain, its tests, the README generator and plugins expect immediate subdirectories.
- A skill upstream deletes is retired here in its own ticket, with whatever replaces its route.
  Its docs page stays and opens with an archived notice.
- `README.md`'s skill index is generated. After any merge that touches it, regenerate it with
  `node scripts/build-readme.mjs`; never hand-merge it.
