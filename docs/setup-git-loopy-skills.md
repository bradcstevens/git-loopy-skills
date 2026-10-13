Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=setup-git-loopy-skills
```

```bash
npx skills update setup-git-loopy-skills
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/setup-git-loopy-skills)

## What it does

`setup-git-loopy-skills` answers three questions about one repo: where issues live, what the triage labels are called, and where the domain docs sit. It records the answers as markdown files under `docs/agents/`. It also scaffolds the repository hooks that complete an in-session chain route and re-enter `/next`.

Those files are the only thing that varies between repos. The skills themselves are identical everywhere. They read `docs/agents/issue-tracker.md` at run time and do what it says. That is why the set is not tied to GitHub, and why you never edit a skill file to point it at another tracker. Invoking it with "link the skills to a custom issue tracker" works with anything you can connect to programmatically, with no changes to the skills.

It is a prompt-driven skill, not a deterministic script. It reads your `git remote`, `AGENTS.md` or `.github/copilot-instructions.md`, and `GLOSSARY.md`, proposes what it found, and waits for you to confirm before it writes anything. It also checks for legacy `GLOSSARY.md` and `GLOSSARY-MAP.md` files and offers a history-preserving migration.

## When to reach for it

You invoke this by typing `/setup-git-loopy-skills`; the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) won't reach for it on its own. Its metadata marks it non-invokable on purpose, so no other skill can fire it for you.

Reach for it once per repo, before the first use of any other engineering skill. If [triage](./triage.md), [to-spec](./to-spec.md), [to-tickets](./to-tickets.md) or [wayfinder](./wayfinder.md) start guessing where your issues go, or apply labels your tracker doesn't have, this repo has not been set up yet. You can run it in a repo halfway through a project. The skill reads what is already there, so no earlier work is lost.

## Prerequisites

It writes into the repo you run it in:

| It writes | Where |
| --- | --- |
| `issue-tracker.md` | `docs/agents/` |
| `domain.md` | `docs/agents/` |
| `triage-labels.md` | `docs/agents/`, only when the `triage` skill is installed |
| An `## Agent skills` block | whichever of `.github/copilot-instructions.md` or `AGENTS.md` already exists |
| `git-loopy-chain.json` and its resolver | `.github/hooks/` |
| The bundled `agentStop` helper and invocation logger | `.github/hooks/` |
| A `.git-loopy/` runtime-state ignore entry | `.gitignore`, if absent |

You commit the config and hook scaffold. There is no user-level or global mode. The config lives in the repo, so every repo gets its own copy.

Install `/next` alongside this skill before setup. Setup resolves its sibling `next/scripts/chain.sh` from the active skill installation rather than assuming the consumer repo is the skill source. If the executable or bundled helper is missing, it stops without writing a hook.

The committed JSON names a repository-relative resolver, not a machine-specific absolute path. Setup previews that exact JSON for approval and rewrites the same files on re-runs rather than adding duplicates. The resolver finds the installed chain at run time. Each clone should run setup after installing the skills; repositories configured before `chain.sh` moved into `next/scripts/` need to re-run it.

The helper and chain script record ledger lock owner start times in UTC, regardless of the machine's timezone. Re-run setup after updating the skills to refresh the copied helper in existing consumer repos; updating the installed skill alone does not replace that copy.

> Copilot silently skips repository hooks in folders outside its `trustedFolders` setting. Add the repository path (or an appropriate parent) to that setting before relying on the chain; otherwise a fresh clone can appear to have a broken trigger with no error.

## The three decisions

It starts each section with the recommended answer, and skips any question its exploration already answered. Most runs need only two confirmations.

| Decision | What it proposes | When it asks |
| --- | --- | --- |
| **Issue tracker** | the one matching your `git remote` | always, because this is the one real choice |
| **Triage labels** | keep the five canonical names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) | only if the `triage` skill is installed |
| **Domain docs** | single-context: one `GLOSSARY.md` plus `docs/adr/` at the root | only if it spots monorepo signals, and then it offers a multi-context `GLOSSARY-MAP.md` |

The tracker options:

| Option | Where issues live | Needs |
| --- | --- | --- |
| **GitHub** | the repo's GitHub Issues | the `gh` CLI |
| **GitLab** | the repo's GitLab Issues | the `glab` CLI |
| **Local markdown** | files under `.scratch/<feature>/` in this repo | nothing, not even a remote |
| **Other** | wherever you say | one paragraph from you describing the workflow |

The first three ship as templates in the skill and work out of the box. Local markdown is a full option, not a fallback. The skill supports a solo project with no remote. One caveat: don't use local markdown if you use GitHub. They are alternatives, so pick one.

"Other" is a full option too. It is how Jira, Linear, Azure DevOps and Beads all work. You describe the workflow, the skill records your prose in `docs/agents/issue-tracker.md`, and the downstream skills follow the prose. Users have already built this: a Jira-over-[MCP](https://www.aihero.dev/ai-coding-dictionary/mcp) variant, a Gitea CLI shaped like `gh`, a hand-built local dashboard.

In git-loopy, the label config also records the non-renameable `parallel-safe`, `priority`, and `idea` assertions and the closed seven-label `task-type:` taxonomy. These are not triage roles. Humans apply the assertions; setup only ensures the label names exist. Tickets carry exactly one task-type label for their dominant risk.

## Common questions

**Do I have to use GitHub?**

No. GitHub, GitLab and local markdown under `.scratch/` all ship as ready-made templates, and anything else works through the "other" path. This is the most-repeated question, in roughly these words: *"hard locked to github"*, *"can I use GitLab / Jira"*, *"what about Azure DevOps"*. The answer is always the same: setup chooses the tracker, not the skill.

**Do I need to re-run it after updating the skills?**

The direct answer after v1.1 was yes. The skill's own closing message is softer. It tells you to re-run only to switch trackers or start over. Both are defensible. The seed templates change between versions, so a `docs/agents/issue-tracker.md` from an older release can go out of date against the skills that now read it. If a downstream skill does something different from what the docs describe, re-run setup. It is cheap. Re-run it to refresh the chain hook scaffold too.

**Which instruction file does it edit on Copilot CLI?**

It edits `.github/copilot-instructions.md` if it exists, otherwise `AGENTS.md`. It checks which file exists and updates the `## Agent skills` block in place, preserving surrounding instructions. If neither file exists, it asks which to create rather than picking one. It never creates a second instruction file just for setup.

**Does it create my triage labels?**

Yes. When `triage` is installed and you confirm the vocabulary, setup creates each configured label GitHub or GitLab lacks. It uses your overridden strings, not only the five defaults, and includes the fixed assertions and task-type labels. It lists existing names with pagination and preserves their colors and descriptions. Listing or creation errors are reported, not treated as a successful setup.

This skill does not create [wayfinder](./wayfinder.md)'s `wayfinder:map` and `wayfinder:<type>` labels. Create them before the first wayfinder run on a GitHub repo. Local markdown needs only the mapping, not remote label creation.

**What happens to my old `CONTEXT.md`?**

Setup offers to move it to `GLOSSARY.md` with `git mv` only when the destination is absent, so Git can follow its history. The same applies to `CONTEXT-MAP.md` with `git mv` to `GLOSSARY-MAP.md` and per-context files referenced by a map. It previews the exact moves and updates the map and relevant instruction/config references after you accept. It does not overwrite an existing glossary or copy and delete an untracked source. If you decline, it leaves the files alone and records the legacy paths in the domain configuration.

**Can I configure the other skills' behaviour here ([grilling](https://www.aihero.dev/ai-coding-dictionary/grilling) cadence, question format, tone)?**

No. It configures three things: tracker, labels, doc layout, plus the git-loopy chain hooks. Users have asked to make it the place for per-user preferences. The answer is that skills stay opinionated and take no per-user config. Preferences belong in your `AGENTS.md` or `.github/copilot-instructions.md` as plain instructions, which every skill already reads.

**Can I keep the config in `~/.copilot` instead of committing it to every repo?**

Not today. A user who runs the skills across many repos has an open request for this, but no user-level mode exists. Every repo carries its own `docs/agents/`.

**Isn't it strange to have a skill that configures the other skills?**

One long-standing complaint says yes, in these words: *"having a skill to set up the other skill does not feel right to me: that means the LLM is configuring its own skills."* The trade-off is real. Without a setup step, every skill that touches issues would need its own copy of the tracker instructions. The output is markdown you can read and edit, and that limits the risk. You can read every file it wrote and change it by hand. Make day-to-day changes that way, not with another run.

## It's working if

- `docs/agents/issue-tracker.md` and `docs/agents/domain.md` exist, plus `triage-labels.md` if `triage` is installed.
- An `## Agent skills` section appears in the instruction file your harness reads, with a one-line summary pointing at each of those files.
- The tracker it proposed matches the remote you use, and the label strings match labels that exist in your tracker.
- Afterwards, `/to-tickets` publishes without asking you where issues live, and `/triage` applies labels rather than inventing them.
- `.github/hooks/git-loopy-chain.json` invokes `complete` for `subagentStop` and `reenter` for `agentStop` through the repository-relative resolver, and the repository is trusted.
- Any accepted glossary migration is staged as a rename with its content preserved and references updated.
- Nothing in the skill files themselves changed. If setup edited a `SKILL.md`, something went wrong.

## Where it fits

`setup-git-loopy-skills` is the **run-once setup** for the engineering flow, the precondition everything else assumes rather than a step in the chain. Its neighbours are its readers: [triage](./triage.md), which applies the label vocabulary written here; [to-spec](./to-spec.md) and [to-tickets](./to-tickets.md), which publish into the tracker named here; and [wayfinder](./wayfinder.md), which reads the "Wayfinding operations" section of the same tracker file to learn how to store maps and child [tickets](https://www.aihero.dev/ai-coding-dictionary/ticket). [domain-modeling](./domain-modeling.md) later fills in the domain-doc layout that setup records. It creates `GLOSSARY.md` and ADRs only when you resolve a term or decision, so a repo with no domain docs after setup is normal. For which skill to reach for next, [next](./next.md) routes the whole set.
