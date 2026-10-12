# Response template

Your final message is published by the workflow: as the pull request body for `implement`, as a
pull request comment for `fix` and `iterate`, and in the run summary for `plan` and
`downstream-plan`. The workflow appends the closing keyword and the `/iterate` footer itself, so do
not write either.

Lead with the outcome, keep it scannable, and put the riskiest thing first.

## `implement` (pull request body)

```markdown
## <ticket title>

Syncs #<ticket> (spec #<spec>) with mattpocock/skills `<sha12>` (<release>).

| Path | Change | Upstream basis |
| --- | --- | --- |
| `skills/<name>/SKILL.md` | <what changed> | `<upstream path>` at the pin |

### Remaining differences from upstream
- `<path>`: <the hunk>. Kept by: <heading in sync-rules.md>

### Validation
- `scripts/validate-skills.sh`: PASS
- `node scripts/build-readme.mjs --check`: PASS

### Review
- `/code-review` at `<head sha>`: clean, recorded on #<ticket> | <n> finding(s) remediated, re-reviewed at `<head sha>`

### Merge danger
- **Door:** two-way | one-way (<why>)
- **Blast radius:** <who notices: chain routing, a skill's behaviour, git-loopy's next pin move>
```

For a git-loopy pin move, replace the table with the proof and the pin:

```markdown
## Move the skill pin to git-loopy-skills `<sha12>`

Carries spec #<spec>: mattpocock/skills `<sha12>` (<release>).

- **Proof:** `python -m git_loopy.skill_candidate` against `<sha12>`: PASS (was: <contracts it broke before the runner changes>)
- **Runner changes:** <PROMPT.md copies, Required Skills, test snapshot, README table, upgrade notes>
- **Pin:** `skill_source.json` `<old sha12>` to `<new sha12>`

### Validation
- Python suite: PASS

### Merge danger
- **Door:** one-way for operators: every Run refreshes its catalog from the pin.
- **Blast radius:** <saved policies naming retired skills, custom PROMPT.md files>
```

## `fix` and `iterate` (pull request comment)

```markdown
<one sentence: what was missing or asked, and what you did>

- <change>
- Validation: <commands>: PASS
- Review: `/code-review` at `<new head sha>`: <clean | findings>
- Memory: <unchanged | added "<entry>">
```

## `plan` and `downstream-plan` (run summary)

```markdown
Planned mattpocock/skills <release>: spec #<n> with <k> ticket(s).

| Ticket | Title | Task type | Parallel-safe | Blocked by |
| --- | --- | --- | --- | --- |

- Out of scope: <upstream skills and why>
- git-loopy follow-up: <owner/repo#n>
```

When you stop early, answer with the blocker first: what is missing, who can provide it, and what
state you left the branch, ticket or pull request in.
