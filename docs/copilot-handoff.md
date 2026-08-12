Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=copilot-handoff
```

```bash
npx skills update copilot-handoff
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/copilot-handoff)

## What it does

`copilot-handoff` compacts the current conversation the same way [handoff](./handoff.md) does — then, instead of leaving a document for someone to open later, it **launches a fresh GitHub Copilot CLI session in the background** with that summary as its prompt. The work carries on immediately, in the same working directory, while you keep your own session.

The summary goes to a file in your OS temporary directory purely as plumbing — it stops the shell mangling a multi-line prompt — and the background session is launched detached:

```bash
nohup copilot -p "$(cat "${TMPDIR:-/tmp}/copilot-handoff-<slug>.md")" \
  -n "<descriptive name>" --allow-all-tools --no-ask-user \
  > "${TMPDIR:-/tmp}/copilot-handoff-<slug>.log" 2>&1 &
```

The command returns straight away. You follow the run with `tail -f <log path>` and pick the session up interactively later with `copilot --resume="<descriptive name>"`.

## When to reach for it

You invoke this by typing `/copilot-handoff` — the agent won't reach for it on its own. Pass a note about what the next session is for and the summary is tailored to it.

Reach for it when the next stretch of work doesn't need you in the loop: a long refactor, a test suite to get green, a chore you'd rather not watch. When you *do* want a human to read the write-up before anything else happens — you're wrapping for the day, or handing to a colleague — use [handoff](./handoff.md) instead.

## What the summary carries

- **The live thread** — what's in flight and why, minus anything already written down elsewhere.
- **Suggested skills** — a pointer to the skills the background agent should reach for to continue.
- **References, not copies** — links and paths to the specs, plans, ADRs, issues, and diffs that hold the settled detail.
- **Redacted secrets** — API keys, passwords, and PII stripped, because the summary *becomes the agent's prompt*.

Three flags carry the weight. `-n`/`--name` is not decoration: a detached session has no terminal to identify it, so the name is how you find it again in `copilot --resume` and `/session`. `--allow-all-tools` is required, because non-interactive mode has no one to approve a tool call. `--no-ask-user` stops the agent stalling on a question nobody is there to answer.

## Where it fits

`copilot-handoff` sits at the same seam as [handoff](./handoff.md) — between two sessions — and differs only in what crosses it: a running agent rather than a document. It pairs with the artifact-producing skills it points at rather than repeats, most obviously [to-spec](./to-spec.md) and [to-tickets](./to-tickets.md), since a background agent with a spec to work from needs very little else. When you're unsure which skill fits the moment, [next](./next.md) routes you.
