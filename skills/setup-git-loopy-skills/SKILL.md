---
name: setup-git-loopy-skills
description: Configure this repo for the engineering skills — set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills.
disable-model-invocation: true
---

# Setup Git Loopy Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them
- **Chain hook** — the repository-scoped `subagentStop` hook that completes an in-session route

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` at the repo root — does it exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use
- `.github/hooks/git-loopy-chain.json` — does the chain hook already exist?
- Is the `triage` skill installed? (a `triage` skill folder alongside this one, or `triage` in your available skills.) This decides whether Section B runs at all.
- Monorepo signals — a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. Present only in a genuinely large multi-package repo; their absence means single-context, which is almost every repo.

### 2. Present findings and ask

Summarise what's present and what's missing. Then take the sections in order — one section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip the section entirely when exploration already settled it (Section B when `triage` isn't installed, Section C when there's no monorepo).

**Before the sections, check chain prerequisites.**

Resolve the installed chain script before drafting any files. Start with the directory that
contains this installed `setup-git-loopy-skills` skill, then use its sibling
`next/chain.sh`; never assume that the current repository is the skill source. A local
`.agents/skills` installation takes precedence over a user installation. The candidate must
be an executable regular file. If no sibling chain script exists, tell the user that `/next`
must be installed alongside this skill and stop without writing a hook.

Set `setup_skill_dir` to the directory holding the active `SKILL.md`, then resolve and verify:

```bash
chain_script="$(cd "$setup_skill_dir/../next" && pwd)/chain.sh"
[ -f "$chain_script" ] && [ -x "$chain_script" ] ||
  { echo "Install /next beside /setup-git-loopy-skills before enabling the chain." >&2; exit 1; }
```

Also give this warning before proceeding:

> Copilot silently does not run repository hooks in an untrusted folder. Verify that this
> repository's absolute path, or a parent path, is in Copilot's `trustedFolders` setting
> before relying on the chain. A fresh clone outside a trusted folder will otherwise look as
> though the hook trigger failed, with no error.

**Section A — Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-tickets`, `triage`, and `to-spec` read from and write to it — they need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub** — issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab** — issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown** — issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.) — ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`. The GitHub and GitLab templates carry a "PRs as a request surface" flag, defaulted **off** — leave it off and don't raise it; a user who wants external PRs in the triage queue can flip the flag in the file later.

**Section B — Triage label vocabulary.** Skip this section entirely if the `triage` skill isn't installed (exploration told you) — an uninstalled skill needs no labels.

If it is installed, ask exactly one question:

> Do you want to keep the default triage labels? (recommended: **yes**)

The defaults are the five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. On **yes**, write them as-is. Only if the user says no — usually because their tracker already uses other names (e.g. `bug:triage` for `needs-triage`) — collect the overrides so `triage` applies existing labels instead of creating duplicates.

Two further labels are written either way, and are **not** part of that question: `parallel-safe` and `priority`. Neither is a triage role, neither is renameable — the runner reads those exact strings — and neither is ever inferred. `parallel-safe` asserts an issue is safe to work concurrently; `priority` asserts it should be worked ahead of older ones. Eligible issues are otherwise worked oldest first, by creation date, so a newly filed issue does not jump the queue unless a human labels it `priority`, and `priority` reorders only: it never substitutes for `ready-for-agent`, the AFK-ready body discriminator, or `parallel-safe`.

Ensure both exist in the tracker. Inside a git-loopy project, `git-loopy init` creates whichever labels are absent and leaves existing ones untouched; otherwise use the create-or-update commands in [triage-labels.md](./triage-labels.md).

**Section C — Domain docs.** Default to **single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. This fits almost every repo; write it without asking.

Offer **multi-context** — a root `CONTEXT-MAP.md` pointing to per-context `CONTEXT.md` files — only when exploration found monorepo signals. Then confirm which layout they want.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/domain.md`, and `docs/agents/triage-labels.md` (the last only when `triage` is installed)
- `.github/hooks/git-loopy-chain.json`, with the resolved absolute chain-script path and its `complete` argument

Let them edit before writing.

### 4. Write

**Pick the file to edit:**

- If `AGENTS.md` exists, edit it.
- If it doesn't exists, create it.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Include the `### Triage labels` sub-block, and write `docs/agents/triage-labels.md`, only when `triage` is installed and Section B ran. When it isn't, both are omitted.

Then write the docs files using the seed templates in this skill folder as a starting point:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md) — GitLab issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md) — local-markdown issue tracker
- [triage-labels.md](./triage-labels.md) — label mapping (only if `triage` is installed)
- [domain.md](./domain.md) — domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

Create `.github/hooks/git-loopy-chain.json` from the approved draft. It must be valid JSON
with version `1`, a single `subagentStop` command hook, and a `bash` command that invokes the
resolved absolute `next/chain.sh` with `complete`. The hook receives the event payload on
standard input, so do not add a redirection or a wrapper that changes it. Use Python's
`json` and `shlex` modules to quote the resolved path when building the draft rather than
hand-escaping it.

Build the draft once, then display that exact file:

```bash
hook_draft="$(mktemp "${TMPDIR:-/tmp}/git-loopy-chain.XXXXXX")"
python3 - "$chain_script" "$hook_draft" <<'PY'
import json
import shlex
import sys

chain_script, hook_draft = sys.argv[1:]
hook = {
    "version": 1,
    "hooks": {
        "subagentStop": [{
            "type": "command",
            "bash": f"{shlex.quote(chain_script)} complete",
        }],
    },
}
with open(hook_draft, "w", encoding="utf-8") as hook_file:
    json.dump(hook, hook_file, indent=2)
    hook_file.write("\n")
PY
cat "$hook_draft"
```

Only after the user approves that displayed JSON, write it in place:

```bash
mkdir -p .github/hooks
mv "$hook_draft" .github/hooks/git-loopy-chain.json
```

Always write the same `git-loopy-chain.json` path. If it already exists, replace only that
file with the approved hook rather than creating another hook file. The hook belongs in the
repository and should be committed with the other setup output. Re-running setup on another
clone updates the absolute installed-script path for that clone. If the user rejects the draft,
delete `"$hook_draft"` and leave the existing hook unchanged.

### 5. Done

Tell the user the setup is complete and which engineering skills will now read from these
files. State the hook path and the resolved chain script. Remind them that repository hooks
run only in trusted folders. Mention they can edit `docs/agents/*.md` directly later —
re-running this skill is only necessary if they want to switch issue trackers, update the
installed script path, or restart from scratch.
