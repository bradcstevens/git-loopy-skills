# AGENTS.md

Guidance for coding agents working in this repository.

## Feedback loops

Run the loops your change touches before committing. A git-loopy **Integration**
also runs every row below, top to bottom and fail-fast, over the merged worktree,
so each row is a blocking gate and none may reach the network. Commands are
relative to the repository root and resolve their tools through `PATH`.

| Loop | Command | When to run |
| --- | --- | --- |
| Skill validation and script suites | `scripts/validate-skills.sh` | Any change under `skills/`, `docs/`, `scripts/` or `.github/hooks/` |
| README skill index | `node scripts/build-readme.mjs --check` | Any change that adds, removes, renames or re-describes a skill, or edits `README.md` |

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus the non-renameable `parallel-safe`, `priority`, and `idea` assertions. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
