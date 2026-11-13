Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=codebase-audit
```

```bash
npx skills update codebase-audit
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/codebase-audit)

## What it does

`codebase-audit` is a final, line-by-line review before code goes to GitHub. It reads the whole codebase and **fixes problems as it finds them** rather than only listing them. Its passes cover:

- **Junk files**: OS files, logs, temp files, build output, dependencies, backups and secrets-bearing files such as `.env` and keys. It also repairs `.gitignore` and makes sure `.env.example` has keys but no values.
- **Source files**: dead code, vague names, magic numbers, debug statements, TODOs, loose types and logic gaps such as missing null checks and unhandled promises.
- **Security**: hardcoded secrets, injection, auth and authorization gaps, data exposure and vulnerable dependencies. A secret in the code is a critical blocker.
- **Scalability, architecture and performance**: N+1 queries, unbounded queries, god files, duplicated logic and blocking work.
- **Documentation and tests**: README essentials, useful comments, no stray `test.only` or unexplained skips.

It finishes by running the app and tests, then prints a report of files removed, code changes, security issues, scalability fixes, a final status and scores.

## When to reach for it

`codebase-audit` is a standalone tool. It is **not on the idea → ship flow**: no skill in that chain calls it and it does not call into the chain. Use it before the first push, before making a repository public, before a production deployment, or when you ask to "clean up the code" or "optimize everything".

## Common questions

**Does it only report?** No. It edits and deletes. If it is unsure whether something should be removed, it asks you first, and it asks before removing IDE folders such as `.vscode/`. Review the diff afterwards.

**Is it a security review?** It includes a security pass, but it is not a substitute for a dedicated review. The skill itself points to deeper tools for that.

**Does it replace environment-specific validation?** No. Treat the output as a thorough cleanup, not as sign-off from testing or expert review.

## It's working if

- Junk files and secrets are gone from the tree and `.gitignore` covers them.
- Every finding is either fixed or called out, and critical security issues are flagged as blockers.
- The app starts, the tests pass and the final report states the status and scores.
