Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=create-readme
```

```bash
npx skills update create-readme
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/create-readme)

## What it does

`create-readme` writes a `README.md` for the project. It reviews the whole project and workspace, then produces a structured, appealing and concise README. It takes its structure, tone and content from a short list of well-regarded example READMEs named in the skill.

The rules it follows:

- Use GitHub Flavored Markdown and GitHub admonition syntax where it helps.
- Do not overuse emojis.
- Leave out LICENSE, CONTRIBUTING and CHANGELOG sections, since those have dedicated files.
- If the project has a logo or icon, use it in the header.

## When to reach for it

`create-readme` is a standalone tool. It is **not on the idea → ship flow**: nothing in that chain invokes it and it does not feed the chain. Use it when a project has no README, or when the current one is stale or thin and you want a fresh start.

## Common questions

**Does it overwrite an existing README?** It creates a README for the project, so check `git diff` before keeping the result if one already exists.

**Does it need network access?** Its example READMEs are fetched from public URLs listed in the skill, so reading them needs access. The README itself is built from your repo.

**Can it write a license or contributing section?** No. It leaves those out on purpose.

## It's working if

- `README.md` explains what the project is, how to install it and how to use it, and matches what is actually in the repo.
- It is concise, with few emojis and no LICENSE, CONTRIBUTING or CHANGELOG sections.
- A project logo, if one exists, appears in the header.
