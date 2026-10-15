---
name: to-spec
description: Turn the current conversation into a spec and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed.
model: claude-opus-5.5
effort: medium
context: 1M
disable-model-invocation: false
---

This skill takes the current conversation context and codebase understanding and produces a spec. Do NOT interview the user; just synthesize what you already know.

The issue tracker and triage label vocabulary should have been provided to you. If not, tell the user to run `/setup-git-loopy-skills`.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout the spec, and respect any ADRs in the area you're touching.

2. Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better - the ideal number is one.

Check with the user that these seams match their expectations.

3. Write the spec using the template below, then publish it to the project issue tracker. Apply the `ready-for-agent` triage label - no need for additional triage.

### Bound deliberate host load

Any acceptance criterion or testing decision that demands **deliberate host load** (stress loops, CPU burners, or extra concurrent command copies) must state its bounds in the spec and require them to be carried into each resulting ticket. "Oversubscribe the CPU about 2x" alone is insufficient. Require:

- On macOS, `taskpolicy -c utility <command>` to protect the operator's foreground; `nice` is not a substitute. Do not run load if the clamp cannot be applied, and never raise inherited priority.
- A total concurrency ceiling of at most about 2x the logical CPUs, counting child workers and extra command copies.
- A wall-clock cap per invocation: an explicit issue-specific cap, otherwise 30 minutes. A cutoff before completion is **inconclusive**, never a pass; a completed invocation reports its actual result.
- No escalation beyond those bounds to force a reproduction: record observations and stop.
- Cleanup after completion, failure, or interruption: reap the processes started and their descendants, check survivors with `pgrep`, establish ownership before ending them by PID, and report cleanup or uncertain ownership.

Ordinary feedback loops declared in `AGENTS.md`, including their built-in test workers, are not deliberate load. They inherit the Run's Host yield policy without an additional clamp or time cap and run to completion; process cleanup still applies. Reject or rewrite an unbounded load criterion before publishing, and preserve tighter bounds already agreed in the conversation.

<spec-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this spec.

## Further Notes

Any further notes about the feature.

</spec-template>

## Decomposition handoff

Publish every decision the decomposition needs in the spec issue before handing
off: the next session must be able to draft from that durable spec alone.

From the repository root, check `/next`'s existing configuration test (tracker
instructions and chain hook present), plus `git-loopy` on `PATH`:

```bash
test -f docs/agents/issue-tracker.md &&
test -f .github/hooks/git-loopy-chain.json &&
command -v git-loopy >/dev/null 2>&1
```

If the check succeeds, close by giving the human `git-loopy plan <spec>` with
`<spec>` replaced by the published spec issue URL. This starts a **fresh,
interactive Planner session** in this repository; git-loopy selects its runtime
through planning Routing. Stop here rather than decomposing in this conversation
or launching an AFK subagent. A launch failure is a blocker to report, not a
reason to silently switch to same-session decomposition.

Otherwise, run `/to-tickets` on the spec issue in this conversation, preserving
the non-git-loopy flow.

At the conclusion of a `/to-spec` session, run `/next`.
