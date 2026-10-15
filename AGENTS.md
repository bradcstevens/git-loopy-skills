# AGENTS.md

Guidance for coding agents working in this repository.

## Feedback loops

Run the loops your change touches before committing. A git-loopy **Integration**
also runs every row below, top to bottom and fail-fast, over the merged worktree,
so each row is a blocking gate and none may reach the network. Commands are
relative to the repository root and resolve their tools through `PATH`.

| Loop | Command | When to run |
| --- | --- | --- |
| Skill validation and script suites | `scripts/validate-skills.sh` | Any change under `skills/`, `profiles/`, `docs/`, `scripts/`, `.github/agents/` or `.github/hooks/`, or edits `.gitignore` |
| README skill index | `node scripts/build-readme.mjs --check` | Any change that adds, removes, renames or re-describes a skill, changes its invocation mode, adds or removes `docs/<skill>.md`, or edits `scripts/build-readme.mjs`, `.gitignore` or `README.md` |

## Skill headers

Every `SKILL.md` names the GitHub Copilot model, reasoning effort and context size
to choose in `/model` before running the skill, directly after its `description`:

```yaml
model: claude-opus-5.5
effort: medium
context: 1M
```

These values are generated, so do not hand-tune them. `skills/model-scorecard/profiles.json`
maps each skill to the role whose work it is, `/model-scorecard` scores that role and fits
the context to the skill's measured runs (`references/skill-headers.json`), and its build
automatically runs `skills/set-task-models/sync_skill_headers.py --write` to update the
headers and `.github/agents/<skill>.agent.md`. `/set-task-models` uses that same projection
with its decision map. A new skill needs a `skills` entry in `profiles.json`, a header and
a generated same-named agent. Run the projection rather than hand-tuning them.

Agent `model` and `reasoning-effort` are runtime fields. Context is advisory metadata,
not an agent runtime setting: each agent includes an exact CLI launch command applying
all three settings. Preserve hand-written agent instructions outside the generated
`model-scorecard` block. The `*-agent` chain carriers remain independently managed.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus the non-renameable `parallel-safe`, `priority`, and `idea` assertions. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
