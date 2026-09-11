---
name: handoff
description: Launch a `/next` recommendation — its prompt and its sized runtime — as a background agent, then watch it to its exit and route on. Use when `/next` routes to `/implement`, when work moves to a fresh session that runs on its own, or when a detached run needs watching to completion.
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

When `/next` returned `Fresh session in a new worktree`, still launch from the
current directory: its prompt opens with the `chain.sh claim` that makes the
worktree and moves the agent before it writes.

The launcher returns one JSON object naming the outcome:

- `launched` — the session is running. Go to step 3.
- `rejected` — the CLI refused a flag, and `log_head` names it. Correct the runtime and launch again.
- `exited` — the session ended inside the settle window. Read its `log` first: a run that finished its work needs no relaunch, while a startup failure does.

**Done when:** the launcher has returned `"status":"launched"`.

## 3. Report the session

Give the user the `log` path that follows the run and the `resume` command that rejoins it, both returned by the launcher.

## 4. Watch the session to its exit

The launcher returns while the session is still working, so its exit is the only signal that the workstream has moved. Watch for that exit whenever `/next` is this skill's successor — the ordinary case, where the detached session carries the very workstream this conversation is routing.

Two launches route elsewhere and take no watch: one the user asked for on its own, because they will pick the result up themselves, and one that bridges into another harness or directory, where that session's own conclusion routes what follows. Name where the successor went, and finish at step 3.

Otherwise arm the watch on the `pid` and `log` the launcher returned:

```bash
while ps -p <pid> >/dev/null 2>&1; do sleep 20; done
tail -40 "<log>"
```

Write the pid into the loop as a bare number tested by `ps -p`: a `kill -0 "$PID"` liveness check is the reflex form of this wait, and the harness refuses it. Run the loop in the background, in async mode, so this turn can end while it keeps waiting. Keep it attached to this conversation, since waking this conversation is the whole job and a detached watcher wakes nobody.

End the turn once the watch is running. The runtime wakes this session when the loop exits. Tell the user that `/next` follows that exit on its own, and that closing the conversation ends the watch while the session keeps going.

**Done when:** the watch is running in the background against the launched pid and the turn has ended, or the successor was named as living elsewhere.

## 5. Route from the exited session

A wake means the session is over, not that it worked. Read the tail the watch printed, reaching into the log when the tail is thin, and say in a sentence how the run ended: the work finished, abandoned mid-flight, or the process killed.

At the conclusion of a `/handoff` session, run `/next` on the state the exited session left, rather than the state it was launched to reach.
