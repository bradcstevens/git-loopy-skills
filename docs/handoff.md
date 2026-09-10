Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=handoff
```

```bash
npx skills update handoff
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/handoff)

## What it does

`handoff` takes the recommendation [next](./next.md) just made — its prompt and its sized runtime — and **launches a fresh GitHub Copilot CLI session in the background** to carry it out. The work starts immediately, in the same working directory, while you keep your own session. If `/next` hasn't just run, `handoff` runs it first, because its output is the seed.

The session is launched by [`handoff.sh`](https://github.com/bradcstevens/git-loopy-skills/blob/main/skills/handoff/handoff.sh), which takes the runtime `next` sized and the path to a file holding the prompt:

```bash
handoff.sh --name "<descriptive name>" \
  --model "<model>" --effort "<level>" --context "<default | long_context>" \
  --prompt-file "$TMPDIR/handoff-prompt.txt"
```

It returns straight away with one JSON object naming the outcome — `launched`, `rejected` (the CLI refused a flag), or `exited` (the session ended within seconds) — along with the log path and the resume command. You follow the run with `tail -f <log path>` and pick the session up interactively later with `copilot --yolo --resume="<descriptive name>"`.

## When to reach for it

You invoke this by typing `/handoff` when work needs to outlive this session: a long refactor, a
separate harness or directory, a colleague, or a mid-phase side task. Pass a note about what the next
session is for and the prompt is tailored to it. It remains distinct from `/next`'s chain: the chain
spawns an in-session, ledger-backed subagent only for an AFK-safe allowlisted route, while `handoff`
launches a detached session that survives its caller, is followed through its log, and is resumed by
its session name.

Reach for it when the next stretch of work doesn't need you in the loop: a long refactor, a test suite to get green, a chore you'd rather not watch. When you'd rather run the step yourself, [next](./next.md) already hands you the same launch as one copyable `Command` block for your own terminal.

## What the prompt carries

- **The `/next` prompt, verbatim** — written to a file rather than a command line, so an apostrophe, a `#`, and a line break all reach the agent intact as one argument.
- **What the records lack** — the constraints `/next` gathered from live state, such as the worktree to work in and the files it shares with work in flight.
- **References, not copies** — links and paths to the specs, plans, ADRs, issues, and diffs that hold the settled detail.
- **Redacted secrets** — API keys, passwords, and PII kept out, because the prompt is stored with the session.

Three flags carry the weight, and the launcher fixes two of them for you. `--yolo` is required, because non-interactive mode has no one to approve a tool call, and `--no-ask-user` keeps the agent working on its own, since a question it raises reaches nobody. `--name` is the one you choose, and it is not decoration: a detached session has no terminal to identify it, so the name is how you find it again in `copilot --resume` and `/session`.

`nohup ... &` reports success whether the session started or died on a rejected flag, so the log is the only evidence either way — the launcher watches it for a few seconds and reports `rejected` or `exited` rather than a session that was never alive. It launches from a subshell, so the session is reparented away from the caller's process tree and outlives it.

## Where it fits

`handoff` sits at the seam between two sessions, and what crosses it is a running agent rather than a document. It is the background half of [next](./next.md)'s recommendation: same prompt, same sized runtime, launched for you instead of handed to you. It pairs with the artifact-producing skills those recommendations point at, most obviously [to-spec](./to-spec.md) and [to-tickets](./to-tickets.md), since a background agent with a spec to work from needs very little else.
