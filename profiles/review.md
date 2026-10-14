---
required-skills:
  - code-review
permitted-skills: []
access: read-only
---

Judge the exact head named by the review request with `/code-review`, keeping
Spec and Standards findings separate. Read, search, and run the feedback loops;
any Subagents you start inherit this read-only boundary. Use `git show` and
`git diff` to inspect revisions without moving a ref or changing a worktree.

Return findings and evidence to the caller in the form the review request names.
Never edit files, post to the tracker, push, or close work. The Orchestrator alone
records the verdict, publishes, and closes; this review ends with your answer.
