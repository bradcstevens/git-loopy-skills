---
name: handoff
description: Launch a `/next` recommendation — its prompt and its sized runtime — as a background agent. Use when `/next` routes to `/implement`, or work moves to a fresh session that runs on its own.
---

A `/next` recommendation is the seed: its prompt and its `Runtime` line are what this skill launches. If that output isn't the last part of this conversation, run `/next` before anything else.

[`handoff.sh`](handoff.sh) owns the launch — the flags, the detachment, the log path, and the evidence that the session started. Your work is the prompt it carries and the runtime it splices.

## 1. Write the prompt to a file

Write it with your file-creation tool to a path outside the repository, such as `$TMPDIR/handoff-prompt.txt`, clear of any worktree another agent owns. Reaching the session as a file means no shell re-quotes it, so an apostrophe, a `#`, and a line break all survive the trip.

Open with the `/next` prompt verbatim, then spend the rest on what the records lack: the constraints `/next` gathered from live state, such as the worktree to work in and the files it shares with work in flight. Reference specs, plans, ADRs, issues, commits and diffs by path or URL, so the settled detail stays where it already lives.

When the user passed arguments, treat them as a description of what the next session is for and tailor the prompt to it.

**Done when:** the file holds the whole prompt, every record it leans on is named by path or URL, every live-state constraint is written down, and credentials, keys and personal data are absent — the prompt is stored with the session.

## 2. Launch the session

Run the launcher from the current working directory, by its path beside this file, splicing in the three flags of the `Runtime` line:

```bash
<this skill's directory>/handoff.sh \
  --name "<a few bare words drawn from the action>" \
  --model "<model>" --effort "<level>" --context "<default | long_context>" \
  --prompt-file "$TMPDIR/handoff-prompt.txt"
```

Name the session, because a detached session has no terminal to identify it and that name is how the user finds it again.

When `/next` returned `Fresh session in a new worktree`, still launch from the current directory: the prompt opens with the `git worktree add` that moves the agent before it writes.

The launcher returns one JSON object naming the outcome:

- `launched` — the session is running. Go to step 3.
- `rejected` — the CLI refused a flag, and `log_head` names it. Correct the runtime and launch again.
- `exited` — the session ended inside the settle window. Read its `log` first: a run that finished its work needs no relaunch, while a startup failure does.

**Done when:** the launcher has returned `"status":"launched"`.

## 3. Report the session

Give the user the `log` path that follows the run and the `resume` command that rejoins it, both returned by the launcher.

At the conclusion of a `/handoff` session, run `/next`.
