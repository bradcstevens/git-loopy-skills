# Agentic engineering system design patterns — what is objectively superior to worktrees?

**Question:** Ingesting the [agentic developer workflows video reference](https://github.com/bradcstevens/git-loopy/blob/main/.reference/agentic-developer-workflows-video-reference.md),
which agentic engineering system design strategies to date are *objectively* superior to using
git worktrees? Capture the top agentic system design pattern, how each works, its pros and cons,
and the scenario each fits — general-purpose patterns and specialized/niche ones.

**Captured** 2026-08-16 · **Method** five parallel `/research` background agents against primary
sources only (official vendor docs, protocol specs, git's own documentation, arXiv papers,
first-party engineering blogs, published security advisories). Secondary write-ups were used only
where a primary page was unreachable, and are flagged.

> This file establishes `docs/research/` in `git-loopy-skills` as the home for research findings,
> matching the existing convention in the sibling [`git-loopy`](https://github.com/bradcstevens/git-loopy)
> repository (`docs/research/`). The repo had no prior convention.

Every claim below is tagged **[Documented]** (direct from a primary source, URL given),
**[Inferred]** (reasoning from documented facts), or **[Unknown]** (could not be verified this
pass). Raw per-thread findings are retained in the session workspace and summarised here.

---

## Verdict, up front

**Nothing "beats worktrees," because worktrees are not the lever.** The question contains a
category error worth naming explicitly, because it is the single most useful finding of this
research.

A git worktree is an **isolation mechanism**. It answers *"how do I let N agents edit the same
repository without clobbering each other?"* It is one axis of a five-axis design space, and it is
the axis with the **least published evidence of impact on outcomes**. Worktrees let you *run* N
attempts. They say nothing about whether any attempt is *correct*, and nothing about whether N
attempts are worth more than one.

The axis that determines whether agentic engineering works at all is **verification**. Two
independent primary results establish this:

1. **Without external feedback, LLM self-correction does not work and can actively make things
   worse.** Huang et al. (Google DeepMind + UIUC), *"Large Language Models Cannot Self-Correct
   Reasoning Yet"* — on intrinsic self-correction, "LLMs **struggle to self-correct** their
   responses without external feedback, and **at times, their performance even degrades** after
   self-correction." **[Documented]** — [arXiv:2310.01798](https://arxiv.org/abs/2310.01798)

2. **Parallelism only converts into results when an automatic verifier exists.** Brown et al.
   (Stanford), *"Large Language Monkeys"* — coverage scales log-linearly with sample count across
   four orders of magnitude, and "in domains like coding and formal proofs, where answers can be
   **automatically verified**, these increases in coverage **directly translate into improved
   performance**" (SWE-bench Lite, DeepSeek-Coder-V2-Instruct: **15.9% at 1 sample → 56% at 250
   samples**, beating the then-SOTA single-sample 43%). But in domains "**without automatic
   verifiers** … majority voting and reward models **plateau beyond several hundred samples**."
   **[Documented]** — [arXiv:2407.21787](https://arxiv.org/abs/2407.21787)

Put those together and the objective ranking falls out:

> **The top agentic system design pattern is the verifier-gated loop: a deterministic,
> machine-checkable oracle sitting between the agent and the human, returning its failure output
> into the same agent session.** Everything else — worktrees, sandboxes, sub-agents, routers,
> spec files, multi-agent orchestration — is either *plumbing that supplies that oracle* or
> *a multiplier on a loop that is only worth multiplying once the oracle exists.*

Worktrees are a multiplier. Multipliers applied to an ungated loop multiply unreviewed output, not
value. This is why the video's ladder is ordered correctly: it adds the deterministic check at step
2 and does not reach isolation until step 5.

### The direct answer on isolation

On its own axis, worktrees are beaten in **both** directions, and the honest answer is
scenario-keyed rather than absolute:

| Direction | What beats worktrees | When |
| --- | --- | --- |
| **Upward** (stronger boundary) | **microVM / VM sandbox** (Firecracker-class: E2B, Fly Machines, microsandbox; or hosted VMs: Claude Code on the web, Cursor Cloud, Jules) | Code or its dependencies are **untrusted**, or the agent has network egress while exposed to untrusted content — the "lethal trifecta." Decisive, not marginal. |
| **Upward** (runtime, not security) | **Container / devcontainer** | You need a **live application**: ports, services, a database, hot reload, divergent per-branch dependencies, or a GPU. |
| **Downward** (cheaper) | **Sequential execution**, `git stash`, or a **copy-on-write filesystem clone** (APFS `clonefile`/`cp -c`, btrfs/ZFS) | Trusted code, no runtime need, few concurrent tasks. A CoW clone copies `node_modules` and build caches that a fresh worktree forces you to rebuild. |
| **Not beaten** | — | Many parallel agents, trusted code, no runtime requirement. Worktrees remain the cheapest correct answer; both vendors that ship worktree support endorse this. |

A worktree provides **zero security boundary**. Every worktree runs as the same user, on the same
host, with the same credentials, the same network, the same ports, and the same global caches. Git's
own documentation makes clear how little is isolated: "all pseudo refs are per-worktree and all refs
starting with `refs/` are **shared**", and "by default, the repository `config` file is **shared**
across all worktrees" **[Documented]** — [git-worktree docs](https://git-scm.com/docs/git-worktree).

---

## How to read this: five axes, not one ladder

Agentic system design decisions are frequently argued as if they were on one line. They are not.
Five largely orthogonal axes exist, and a design picks a point on each. Mixing them up produces
false comparisons like "worktrees vs. multi-agent."

| # | Axis | The question it answers | Cheapest → strongest |
| --- | --- | --- | --- |
| 1 | **Verification** | How do we know the output is right? | nothing → lint → types → tests → CI → verifier-gated best-of-N |
| 2 | **Control flow** | Who decides what happens next? | single agent → prompt chain → router → orchestrator-workers → durable workflow engine |
| 3 | **Isolation** | What stops concurrent work (or hostile code) from colliding? | one checkout → worktree → container → gVisor → microVM/VM |
| 4 | **State & context** | What survives a context reset, a crash, or a session boundary? | chat history → instruction file → plan/spec artifact → ticket tracker → checkpointed durable state |
| 5 | **Human placement** | Where do people own intent and accountability? | review everything → gate at risk boundaries → gate at merge only |

**Axis 1 dominates.** It has the strongest evidence, the lowest cost, and it is the precondition
for axes 2 and 3 paying off at all. The video's central claim — that engineers own intent, agents
own probabilistic reasoning, and **code owns routing, validation, and state transitions** — is
independently corroborated by every major vendor (§4).

---

## Strength of evidence — read this before adopting anything

Most agentic-engineering advice is vendor assertion or folklore. Sorting it honestly is the point
of a research pass. Sources at §11.

### Tier 1 — Real empirical support, with effect sizes

| Finding | Source | Effect |
| --- | --- | --- |
| Self-correction without external feedback fails, sometimes degrades | [arXiv:2310.01798](https://arxiv.org/abs/2310.01798) (Google DeepMind) | Performance can *decrease* after self-correction |
| Repeated sampling pays off **only** with an automatic verifier | [arXiv:2407.21787](https://arxiv.org/abs/2407.21787) (Stanford) | SWE-bench Lite 15.9% → 56% @250 samples; plateaus without verifier |
| Experienced devs on mature repos were **slower** with AI, while believing they were faster | [METR RCT](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), [arXiv:2507.09089](https://arxiv.org/abs/2507.09089) | **+19% time** (CI +2%…+39%); forecast −24%, believed −20% *after the fact* |
| Benchmark scores overstate real capability (contamination/memorisation) | [arXiv:2506.12286](https://arxiv.org/abs/2506.12286) (Microsoft) | Buggy file path identified from issue text alone at **76%** on SWE-bench vs **53%** off-benchmark |
| LLM judges agree with humans ~80% but carry systematic biases | [arXiv:2306.05685](https://arxiv.org/abs/2306.05685) (LMSYS) | Position, verbosity, and self-preference bias documented |
| Learned model routing cuts cost without quality loss | [arXiv:2406.18665](https://arxiv.org/abs/2406.18665) (RouteLLM) | **≥2× cost reduction**, no measured quality loss |

The METR result deserves emphasis because it is the strongest counter-evidence to naive scaling: 16
experienced maintainers, their **own** repos (avg 22k+ stars, 1M+ LOC), 246 real issues, randomised,
screen-recorded. They were 19% slower and *could not perceive it*. **[Documented]** METR's
[Feb-2026 update](https://metr.org/blog/2026-02-24-uplift-update/) reports raw speedup in a larger
late-2025 study but calls it "very weak evidence" due to heavy selection bias (30–50% of developers
declined to submit tasks they wouldn't do without AI). **[Documented]**

The correct reading is not "AI doesn't work." It is: **on high-quality-bar work with many implicit
requirements, unaided agent output costs more to integrate than it saves — unless a gate catches
the defects mechanically.** That is an argument *for* axis 1, not against agents.

### Tier 2 — Well-documented mechanisms, real capability, unmeasured effect size

Claude Code hooks; Agent SDK permission evaluation order; OpenAI guardrails/tripwires; Codex
sandbox + approval modes; GitHub branch protection, required status checks and merge queues;
Copilot coding agent's workflow-approval requirement. These are **guarantees the platform
enforces**, which is worth more than a benchmark, but no vendor publishes "hooks improved solve
rate by X%."

### Tier 3 — Vendor-asserted or folklore

TDD-with-agents productivity (recommended by Anthropic, no published effect size, and carries the
documented counter-risk of agents asserting current buggy behaviour); LLM-as-judge as a *primary*
correctness gate; specific industry churn/defect multipliers.

### The open evidence gap

**No first-party controlled study isolating the impact of deterministic gates on agent solve-rate
or rework was found.** **[Unknown]** The case for the top pattern is built by composing
2310.01798 (self-correction needs an external oracle) with 2407.21787 (sampling needs a verifier)
and with the observation that every credible agent benchmark — SWE-bench, Terminal-Bench,
SWE-Lancer, Aider polyglot — uses a deterministic verifier as ground truth. **[Inferred, tightly
grounded]** A direct RCT of "gate vs. no gate" would be a genuinely valuable experiment.

---

## The top pattern: the verifier-gated loop

**Definition.** Deterministic, machine-checkable code evaluates agent output and returns its
failure text into the same agent session, which revises until the check passes. The human sees only
results that already cleared the gate.

**Mechanism.** Three placements, innermost to outermost:

1. **In-loop hooks** — checks fire on agent lifecycle events, not on the agent's discretion.
   Claude Code hooks fire at documented events in three cadences: once per session
   (`SessionStart`/`SessionEnd`), once per turn (`UserPromptSubmit`/`Stop`/`StopFailure`), and on
   every tool call (`PreToolUse`/`PostToolUse`/`PostToolUseFailure`). A `PreToolUse` hook returning
   `hookSpecificOutput.permissionDecision: "deny"` blocks the call and "**shows Claude the
   reason**." A `Stop` hook "runs your check as a script and blocks the turn from ending until it
   passes." **[Documented]** — [hooks](https://code.claude.com/docs/en/hooks),
   [best practices](https://code.claude.com/docs/en/best-practices)
2. **Workflow gates** — the orchestrating code refuses to advance a phase until a check passes.
   Anthropic names these "gate" checks inside prompt chaining. **[Documented]**
3. **Platform gates** — required status checks, required reviews, merge queue. **[Documented]** —
   [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

**Why deterministic beats another model call.** A second ungrounded model pass is *intrinsic
self-correction*, the exact regime 2310.01798 shows can degrade performance. A compiler, type
checker, linter, or test suite is **grounded external feedback** — the regime where correction
reliably works. Anthropic states the causal logic plainly: "Claude stops when the work looks done.
Without a check it can run, 'looks done' is the only signal … Give Claude something that produces a
pass or fail, and the loop closes on its own." **[Documented]**

Anthropic's own framing of why agents suit coding is the same point: "code solutions are verifiable
through automated tests; agents can iterate on solutions using test results as feedback" — followed
immediately by "**human review remains crucial**." **[Documented]** —
[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

**Pros.** Faster than a model call. Repeatable. Consumes no tokens to run. Makes success criteria
explicit and testable. Is the precondition under which best-of-N, parallel lanes, and autonomous
operation become economically rational. Unlike instruction files, it is *enforced*: Anthropic
contrasts hooks with CLAUDE.md directly — "unlike CLAUDE.md instructions which are **advisory**,
hooks are **deterministic and guarantee the action happens**." **[Documented]**

**Cons and real failure modes.**

- **The gate is not absolute.** Claude Code "**overrides the hook and ends the turn after 8
  consecutive blocks**." **[Documented]** A stubbornly failing check does not trap the agent
  forever — design for that.
- **Parallel guardrails can fire too late.** OpenAI's default parallel mode means the expensive
  model may already have run before a tripwire triggers; `run_in_parallel=False` guarantees it does
  not, at a latency cost. **[Documented]** —
  [guardrails](https://openai.github.io/openai-agents-python/guardrails/)
- **A model-based "check" is not a gate.** Hook types include `prompt` and `agent`; using those
  re-inherits LLM-judge unreliability. **[Inferred, grounded]**
- **Test oracles can be gamed.** Agents can write tests asserting current buggy behaviour, or
  weaken assertions to pass. Anthropic's documented mitigations: "address the root cause, don't
  suppress the error," and use a **fresh verification subagent** "so the agent doing the work isn't
  the one grading it." **[Documented]**
- **Passing tests ≠ review-ready.** METR notes real tasks carry "many implicit requirements
  (documentation, testing coverage, linting/formatting)." **[Documented]**
- **Hooks execute arbitrary shell**, so untrusted hook configs are a supply-chain risk; managed
  settings and `allowManagedHooksOnly` exist to constrain this. **[Documented]**

**Where it belongs.** Everywhere, at all three placements. This is the one pattern with no
scenario in which it is the wrong choice, only scenarios where the available oracle is weaker.

**The decision rule.** **[Inferred, grounded]**
> If a machine oracle exists (compiles / tests pass / types check / lint clean / schema valid /
> property holds) → **use a deterministic gate.** It is the only regime where self-correction and
> best-of-N reliably pay off.
> If no machine oracle exists (prose quality, design trade-offs, taste) → **an LLM judge or
> verification subagent is the fallback**, used with bias mitigation, and never as the sole gate on
> anything a machine could have checked exactly.

---

## The general-purpose stack — patterns that apply almost everywhere

These seven are the ones to adopt by default. Each is documented across multiple vendors.

### G1. Single augmented agent (the correct default)

**Mechanism.** One LLM with tools, retrieval, and memory, looping until done or an iteration cap
trips. **[Documented]**

**Pros.** Simplest to build, debug, and test; lowest latency and token cost; no coordination
overhead. **Cons.** Prompt/tool overload as scope grows; no context isolation; unbounded tool loops
without a cap; compounding errors on long horizons.

**Fit.** Single-domain tasks, prototypes, well-scoped changes. **Anti-fit.** Cross-domain work
needing distinct security boundaries; tasks exceeding one context window.

Microsoft states this most directly: use "the **lowest level of complexity** that reliably meets
your requirements," and a single agent with tools is "**often the right default for enterprise** …
Simpler to debug and test." **[Documented]** —
[Azure AI agent design patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

### G2. Deterministic shell with a probabilistic core

**Mechanism.** Deterministic code owns routing, sequencing, state transitions, and validation. The
agent is confined to individual reasoning steps invoked as nodes/activities whose output must clear
a check before the code advances.

This is the video's central thesis, and it is a shipped product primitive at three vendors:

- Google ADK's Sequential/Loop/Parallel agents "determine the execution sequence according to their
  type … **without consulting an AI model for orchestration**. This … results in **deterministic and
  predictable execution patterns**." **[Documented]** — [adk.dev](https://adk.dev/agents/workflow-agents/)
- Azure: "the choice of which agent gets invoked next is **deterministically defined as part of the
  workflow and isn't a choice given to agents**." **[Documented]**
- Anthropic's workflow/agent split: workflows are "systems where LLMs and tools are orchestrated
  through **predefined code paths**." **[Documented]**

**Pros.** Predictable, testable, resumable, auditable; bounds error compounding; gives a clean
human/agent/code responsibility split. **Cons.** Less flexible for genuinely open-ended work;
upfront engineering; can over-constrain when the path truly cannot be enumerated.

**Fit.** Production lanes (chore/bug/feature/hotfix) with ticket-driven state; anything requiring
reliability or compliance. **Anti-fit.** Open-ended research where steps cannot be enumerated —
use an autonomous agent or orchestrator-workers there.

### G3. Durable artifact between phases (the blackboard)

**Mechanism.** Phases coordinate through a **file on disk** — spec, plan, tasks, notes, ticket —
rather than through conversation history. Each phase reads the artifact, works, writes an updated
artifact; the next phase (or a fresh context after a reset) resumes from the file.

Realisations: GitHub **Spec Kit** (`/speckit.constitution` → `specify` → `clarify` → `plan` →
`tasks` → `analyze` → `implement`, plus `taskstoissues` and `converge`); AWS **Kiro**
(`requirements.md` → `design.md` → `tasks.md`, with approval gates and dependency-graph "waves");
Anthropic's guidance that subagents **output to a filesystem** and pass lightweight references back
to avoid a "game of telephone"; structured note-taking. **[Documented]**

**Why a file beats chat history.** It survives compaction and context resets, is reviewable and
diffable, is resumable, and is portable across agents and models (Spec Kit is explicitly
agent-agnostic across 30+ agents). GitHub draws the contrast directly: with IDE assistants
"decisions made during the session are **untracked and lost to time unless committed**," whereas
cloud-agent work has "every step happening in a commit and being viewable in logs." **[Documented]**

**Pros.** Durability, auditability, decoupling of phases, enables parallel task waves.
**Cons.** The artifact drifts from the code (Spec Kit's `/converge` and Kiro's traceability exist
precisely because of this); upfront authoring cost; a stale artifact actively misleads.

**Fit.** Multi-session features, ticket-driven delivery, any handoff between agents or humans.
**Anti-fit.** Trivial one-file fixes where the ceremony exceeds the work.

This pattern is the mechanical basis of git-loopy's **Memento Model** — durable state travels
through repository history and issue-tracker state, not through conversation
([`docs/concepts.md`](https://github.com/bradcstevens/git-loopy/blob/main/docs/concepts.md)).

### G4. Context isolation via sub-agents

**Mechanism.** A specialised sub-agent runs in **its own context window** with its own system
prompt, tool access, and permissions, and returns only a distilled summary. Anthropic quantifies
it: a sub-agent may burn tens of thousands of tokens internally but "returns only a condensed,
distilled summary (often **1,000–2,000 tokens**)." **[Documented]** —
[sub-agents](https://code.claude.com/docs/en/sub-agents),
[context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

The justification is **context rot**: as tokens increase, recall decreases; models have an
"**attention budget**"; the goal is "the **smallest possible set of high-signal tokens**."
**[Documented]**

**Pros.** Preserves the parent's attention budget; enforces constraints by limiting tools;
controls cost by routing sub-work to a cheaper model; enables genuine specialisation.
**Cons.** Loss of nuance in the summary; the parent cannot steer mid-flight; cost of the extra
session. **Fit.** Search/exploration, verification passes, anything whose *process* is verbose but
whose *result* is small. **Anti-fit.** Work requiring tight shared context with the parent.

### G5. Progressive disclosure (Agent Skills)

**Mechanism.** Three loading levels: **metadata always loaded** (~100 tokens/skill: `name` +
`description`), **body loaded only on trigger** (<5k tokens), **bundled files loaded only when
read** — and crucially, **scripts run through bash so only their output enters context; the script
code never does.** "No practical limit on bundled content." **[Documented]** —
[Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills),
open standard at [agentskills.io](https://agentskills.io/)

**Pros.** "Install many Skills without context penalty"; effectively unbounded reference material;
composable and portable. **Cons.** Security — "malicious skills may introduce vulnerabilities … or
direct Claude to exfiltrate data"; the `description` quality gates whether the skill triggers at
all. **Fit.** Repeatable domain/procedural expertise. **Anti-fit.** One-off conversation-level
instruction — use a prompt.

The same idea applied to MCP is dramatic: presenting MCP servers as a **file tree of code APIs**
that the agent reads selectively cut a workload from "**150,000 tokens to 2,000 tokens — a … saving
of 98.7%**." **[Documented]** —
[code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)

### G6. Routing to specialised lanes

**Mechanism.** Classify incoming work, dispatch to a specialised downstream handler with its own
prompt, model, tools, and gate. Classification may be an LLM "or a more traditional classification
model/algorithm." **[Documented]**

Anthropic documents the cost-optimisation angle verbatim: "**Routing easy/common questions to
smaller, cost-efficient models like Claude Haiku 4.5 and hard/unusual questions to more capable
models like Claude Sonnet 4.5**." **[Documented]** RouteLLM shows a learned router achieves
**≥2× cost reduction with no quality loss**. **[Documented]** — [arXiv:2406.18665](https://arxiv.org/abs/2406.18665)

**Pros.** Separation of concerns; specialised prompts without cross-interference; large cost
savings. **Cons.** Misclassification cascades into the wrong lane; adds a hop; requires stable
categories. **Fit.** The video's chore/bug/feature/hotfix portfolio; model tiering.
**Anti-fit.** Overlapping or unstable categories; a single homogeneous task type.

This is git-loopy's ADR-0027/0035 measured-routing territory: routing calibrated by measurement
rather than assertion.

### G7. Human-in-the-loop gate at deliberate boundaries

**Mechanism.** Execution pauses at defined checkpoints for approval, then **resumes from durable
state** rather than restarting. LangGraph checkpointers provide "conversation continuity,
human-in-the-loop workflows, **time travel**, and fault tolerance." **[Documented]**

The platform guarantees are the strongest form. By default a Copilot agent's PR is treated like an
outside contributor's: **GitHub Actions workflows do not run until a human with write access clicks
"Approve and run workflows,"** and Copilot **cannot satisfy required human reviews** — it cannot
self-approve. **[Documented]** — [reviewing a Copilot PR](https://docs.github.com/copilot/how-tos/agents/copilot-coding-agent/reviewing-a-pull-request-created-by-copilot).
Since 2026-03-13 admins may optionally disable the workflow-approval requirement, which speeds
iteration and re-opens the secrets-exposure risk; it does **not** remove required merge reviews.
**[Documented]** — [changelog](https://github.blog/changelog/2026-03-13-optionally-skip-approval-for-copilot-coding-agent-actions-workflows/)

**Pros.** Safety and accountability at irreversible actions; enables replay and correction.
**Cons.** Throughput bottleneck; requires durable persistence; badly placed gates add friction
without safety. Anthropic's own warning about approval fatigue is worth quoting: "after the tenth
approval you're not really reviewing anymore, you're just clicking through." **[Documented]**

**Fit.** Irreversible or expensive actions — deploys, merges, refunds; regulated workflows.
**Anti-fit.** High-volume low-risk automation where a human on every task defeats the purpose.

---

## Isolation in depth — the direct comparison

### What a worktree actually isolates

| Isolated | **Not** isolated (shared across all worktrees and the host) |
| --- | --- |
| Tracked working-tree files | The `.git` object store and `refs/*` **[Documented]** |
| The index / staging area | Repository `config` by default (unless `extensions.worktreeConfig`) **[Documented]** |
| Per-worktree `HEAD`, `refs/bisect`, `refs/worktree`, `refs/rewritten` **[Documented]** | Untracked/ignored files — `node_modules`, `.venv`, `.env`, build caches. A new worktree starts empty of these and must reinstall. **[Inferred]** |
| | **Ports, databases, environment variables, global tool caches** (`~/.npm`, `~/.cargo`, `~/.m2`), **credentials** (`~/.ssh`, `~/.aws`, the `gh` token), and the OS itself. **[Inferred from documented scope]** |

Documented limitation worth flagging for monorepos: on submodules, git says "Multiple checkout in
general is still experimental, and the support for submodules is incomplete. **It is NOT recommended
to make multiple checkouts of a superproject.**" **[Documented]**

Both major CLI vendors nonetheless endorse worktrees for parallel agent sessions: Claude Code ships
`claude --worktree <name>` **[Documented]**, and OpenAI Codex recommends them as the project
boundary — "use separate projects or worktrees instead of broadening access across unrelated
repositories." **[Documented]** — [Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing)

### The isolation-strength ordering

**[Inferred from documented mechanisms]**

> microVM (Firecracker: Fly Machines, E2B, microsandbox) ≈ full VM (Cursor Cloud, Jules, Claude Code
> on the web) > gVisor (Modal) > OS container (Cloudflare Sandbox, devcontainers, Codex cloud,
> Copilot's Actions runner) > OS syscall sandbox (Seatbelt / bubblewrap: Claude Code and Codex
> locally) > **worktree (no security boundary at all)**

Anthropic publishes the clearest tiered ladder of any vendor **[Documented]** —
[sandbox environments](https://code.claude.com/docs/en/sandbox-environments):

| Tier | Isolates | Mechanism | Docker? |
| --- | --- | --- | --- |
| Sandboxed Bash tool | Bash commands and children only | macOS **Seatbelt**; Linux/WSL2 **bubblewrap + socat** | No |
| Sandbox runtime | Whole process incl. file tools, MCP servers, hooks | Same, wrapping the process (beta) | No |
| Dev / custom container | Full dev environment | Docker | Yes |
| Virtual machine | Full OS | VM | No |
| Claude Code on the web | Full OS, Anthropic-hosted | Managed VM | No |

Notable documented defaults across vendors: Claude Code's Bash sandbox writes only to cwd + session
temp with a **domain allowlist for network**; Claude Code **refuses to start as root** with
`--dangerously-skip-permissions`. OpenAI Codex has **network OFF by default**, `workspace-write` as
the default sandbox, and protects `.git` read-only inside writable roots. Codex cloud runs a
**two-phase** model — setup with network on, then the **agent phase offline**, with secrets removed
before the agent phase. Claude Code on the web uses a **credential proxy** that translates a scoped
credential to the real GitHub token and restricts `git push` to the current working branch.
**[Documented]**

### Why the boundary matters: the security case

- **The lethal trifecta** — private data + exposure to untrusted content + ability to communicate
  externally ⇒ exfiltration is possible. Guardrail products claiming ~95% detection are "a failing
  grade"; the only safe move is to "**avoid the lethal trifecta combination entirely**."
  **[Documented]** — [Simon Willison, originator of the term](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/).
  **A worktree does nothing to break any leg of this. A network-disabled sandbox breaks the third.**
  **[Inferred]**
- **The Nx "s1ngularity" incident (Aug 2025)** is the canonical "agent CLI weaponised" event: a
  `pull_request_target` injection stole an npm token, and malicious Nx versions shipped a postinstall
  that "attempted to use local AI tools (like **Claude and Gemini**)" to scan for secrets and
  exfiltrate them via the `gh` CLI to public repos. **[Documented]** —
  [Nx postmortem](https://nx.dev/blog/s1ngularity-postmortem),
  [GHSA-cxm3-wv7p-598c](https://github.com/nrwl/nx/security/advisories/GHSA-cxm3-wv7p-598c). Nx's own
  lesson: "the impact must be limited even" when a breach happens.
- **CVEs against agent CLIs** confirm the class is real: `CVE-2025-54795` (Claude Code command
  injection bypassing the approval prompt, RCE), `CVE-2025-58764` (code injection), `CVE-2025-55284`
  (data exfiltration over **DNS** via allowlisted `ping`/`nslookup`). **[Documented]**
- **Allowlists are not isolation**, and GitHub says so about its own product: the Copilot firewall
  "only applies to processes started by the agent via its Bash tool. It does **not** apply to MCP
  servers or processes started in configured Copilot setup steps," and "**sophisticated attacks may
  bypass the firewall**." **[Documented]** —
  [customize the firewall](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-the-firewall)

A container is also not a hard boundary. Anthropic's own devcontainer warning: with
`--dangerously-skip-permissions`, "dev containers do not prevent a malicious project from
exfiltrating anything accessible inside the container, including the Claude Code credentials stored
in `~/.claude`. **Only use dev containers when developing with trusted repositories.**"
**[Documented]**

### Sandbox primitives, compared

**[Documented unless noted]**

| Product | Isolation mechanism | Latency | Snapshot / persist |
| --- | --- | --- | --- |
| **E2B** | Isolated cloud sandboxes, self-hostable (Terraform on GCP/AWS); Firecracker microVM per public materials **[Inferred — not pinned to a doc line]** | — | **pause/resume preserves filesystem *and* memory**; 24h Pro / 1h Base |
| **Modal** | **gVisor** — "compute jobs at Modal are containerized and virtualized using gVisor" | — | filesystem/memory snapshots; 5-min default, up to 24h |
| **Fly.io Machines** | Firecracker microVMs; "fast-launching VMs with a simple REST API" | boot a stopped machine "**well under a second**" | `fly machine clone`; optional volumes |
| **Daytona** | "**full composable computers** … complete isolation, a **dedicated kernel**, filesystem, network stack" | **<90 ms** spin-up | OCI-compatible; stateful snapshots |
| **microsandbox** | "Each sandbox is a **VM, not a container namespace** on the host kernel" — hardware isolation; local-first, no daemon | "fast startup" | OCI images; secrets stay on host via placeholder injection |
| **Cloudflare Sandbox SDK** | "each sandbox runs in its own **isolated container** with a full Linux environment" | — | preview URLs; egress control; R2/S3 mounts |

Cursor Cloud is worth calling out for a capability worktrees structurally cannot offer: agents "run
in **isolated VMs in the cloud** with full development environments," with **remote desktop control**
to test the live app "without checking out the branch locally." **[Documented]** —
[Cursor Cloud agent](https://cursor.com/docs/cloud-agent)

### The counter-pressure nobody prices: integration cost

Parallelism moves the bottleneck; it does not remove it. More concurrent branches means more merge
conflicts, more semantic conflicts, and more review load. **No primary source quantifies this**
**[Unknown]**, which is itself a notable gap given how much parallel-agent tooling is being sold.

Git's first-party answer for dependent branches is `git rebase --update-refs` / `rebase.updateRefs`,
which restacks dependent branch tips during a rebase. **[Documented]** Vendors address it partially
by making the output reviewable before merge (Cursor's remote desktop) or by restricting where the
agent can push (Claude Code on the web pushes only to the working branch). **[Documented]**

git-loopy already treats this as the governing resource rather than an afterthought: Integration is
**serialized**, the backlog is bounded at two, and a third finisher **parks** — "raising
`GIT_LOOPY_MAX_PARALLEL` past the point where Integration saturates buys nothing. Integration, not
the Lane count, is the governing resource"
([`docs/parallel-mode.md`](https://github.com/bradcstevens/git-loopy/blob/main/docs/parallel-mode.md)).
That is the correct conclusion and it matches this research: the multiplier is not the constraint.

---

## Orchestration topologies — catalogue

Anthropic's [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)
supplies the canonical vocabulary. Definitions below are quoted or paraphrased from primary sources.

| Pattern | Mechanism | Pros | Cons | Best fit | Anti-fit |
| --- | --- | --- | --- | --- | --- |
| **Single augmented agent** | LLM + tools/retrieval/memory in a loop | Simplest; cheapest; easiest to debug | Prompt overload; no context isolation; unbounded loops | The default; well-scoped changes | Cross-domain work; multi-context-window tasks |
| **Prompt chaining / pipeline** | Fixed sequence; each call consumes the previous output; **programmatic "gate" checks between steps** | Predictable; each step easier; natural checkpoints | Additive latency; early bad output poisons later stages; no backtracking | Fixed multi-stage transforms; codegen→lint→test | Embarrassingly parallel stages |
| **Routing / dispatcher** | Classify, then dispatch to a specialised handler | Specialisation; cost/latency optimisation | Misclassification cascades; extra hop | Chore/bug/feature/hotfix lanes; model tiering | Overlapping or unstable categories |
| **Orchestrator-workers** | A central LLM **dynamically** decomposes at runtime, delegates, synthesises. Subtasks are *not* pre-defined | Handles unpredictable subtask counts; scales across context windows | ~15× chat tokens; synchronous bottleneck; coordination errors | Breadth-first research; "coding products that make complex changes to multiple files" | **Shared-context / dependency-heavy work** |
| **Parallelization — sectioning** | Split into genuinely **independent** subtasks, fan out, fan in | Latency reduction; focused attention per aspect | Needs truly independent splits | Multi-aspect evals; guardrail alongside responder | Dependent subtasks |
| **Parallelization — voting / best-of-N** | Run the **same** task N times, aggregate or select | Higher confidence/recall; **the pattern with real scaling evidence** | N× cost for one output; needs aggregation logic | Security review; codegen **with a test oracle** | Budget-sensitive paths; no verifier |
| **Evaluator-optimizer** | Generator + critic loop until criteria met | Measurable improvement **when criteria are clear** | **Intrinsic self-critique can degrade reasoning**; oscillating loops | Code where the critic is grounded in tests/compiler output | "Grade your own reasoning" with no external oracle |
| **Handoff / peer delegation** | Agent transfers control **as a tool call** (`transfer_to_<agent>`); receiver sees history | Clean specialisation; good for escalation | No central oversight point; input guardrails fire only on the *first* agent; context bloat | Triage → specialist; conversational domains | Centralised validation/state ownership |
| **Blackboard / shared artifact** | Coordinate through a durable file (spec, plan, ticket) | Survives resets; auditable; portable across models | Artifact drifts from code; authoring cost | Ticket-driven delivery; multi-session features | Trivial one-shot tasks |
| **Hierarchical / manager-of-managers** | Nested orchestration; managers call sub-agents as tools | Oversight at each tier; composable | Latency/token multiplication per tier; manager is a bottleneck | Large cross-domain factories | Simple or latency-sensitive work |
| **Ensemble race (first-valid-wins)** | Fan out N identical attempts; a deterministic validator accepts the first that passes; cancel the rest | Cuts tail latency; raises success probability | N× cost; **requires a cheap, trustworthy validator** | Hotfixes where the test suite is the oracle | No automatic validator |
| **Human-in-the-loop gate** | Pause at a checkpoint, resume from durable state | Safety at irreversible actions; enables replay | Throughput bottleneck; approval fatigue | Deploys, merges, regulated flows | High-volume low-risk automation |
| **Deterministic shell, probabilistic core** | Code owns control flow and state; agent owns one step | Predictable, testable, resumable, auditable | Less flexible for open-ended work | Production factory lanes | Genuinely unenumerable paths |

**Naming caution:** "swarm / first-valid-wins race" is **not** a named first-party vendor pattern,
and OpenAI's *Swarm* is explicitly a **handoffs** framework, not an ensemble race. The nearest
documented anchor is Anthropic's **voting/best-of-N**. Treat the race as an engineering convention.
**[Documented — disambiguation]**

### The multi-agent nuance that most write-ups omit

Anthropic's multi-agent research system beat single-agent Claude Opus 4 by **90.2%** — but the
detail matters enormously:

- The eval was **breadth-first retrieval**, not coding. The illustrative task was "identify all the
  board members of the companies in the Information Technology S&P 500." **[Documented]**
- It cost roughly **15× the tokens of a chat interaction** (agents alone are ~4×); on BrowseComp
  "**token usage by itself explains 80% of the variance**." **[Documented]**
- And Anthropic states the limit explicitly: "some domains that require **all agents to share the
  same context** or involve **many dependencies between agents** are not a good fit for multi-agent
  systems today. For instance, **most coding tasks involve fewer truly parallelizable tasks than
  research, and LLM agents are not yet great at coordinating and delegating to other agents in real
  time**." **[Documented]** —
  [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

**Conclusion for coding systems [Inferred, well-grounded]:** prefer a **deterministic shell with an
orchestrator** over free peer-to-peer multi-agent. Parallelise across **independent units of work**
(git-loopy's `parallel-safe` issues) rather than *within* one unit. This is exactly what ADR-0008
decided and explicitly deferred within-issue sub-agent decomposition — the research supports that
deferral.

Anthropic's reliability findings reinforce the deterministic-shell thesis: "**agents are stateful
and errors compound**," so systems should **resume from where the agent was** rather than restart,
and combine agent adaptability "with **deterministic safeguards like retry logic and regular
checkpoints**." They also report early systems "spawning 50 subagents for simple queries," fixed by
embedding explicit **scaling rules** in prompts. **[Documented]**

### What all vendors agree on

Convergent advice, cross-checked across Anthropic, OpenAI, Google, and Microsoft **[Documented]**:

1. **Start with the simplest thing; add complexity only when it demonstrably improves outcomes.**
   Anthropic: "find the simplest solution possible … this might mean **not building agentic systems
   at all**." Microsoft: "use the **lowest level of complexity** that reliably meets your
   requirements." OpenAI: single-agent-first.
2. **A single augmented agent is the default;** many "agent" needs are just good tools plus a good
   prompt.
3. **Prefer workflows (deterministic code paths) for predictability;** reserve autonomous agents
   for genuinely unpredictable work.
4. **Multi-agent is expensive and only pays off for high-value, parallelisable, breadth-first
   work — not shared-context coding coordination.**
5. **Context is scarce; isolate it** via sub-agents, clean windows, and durable notes.
6. **Durability is first-class:** checkpoints, retries, resume — not restart.
7. **Tools and interfaces deserve as much design as prompts** (the agent-computer interface).
8. **Ground validation in external signals**, not the model grading itself.
9. **Durable artifacts between phases beat conversational state** for long or multi-session work.
10. **Beware frameworks.** Anthropic: they "often create extra layers of abstraction that can
    obscure the underlying prompts and responses, making them harder to debug … **start by using LLM
    APIs directly**."

---

## Context and state — catalogue

| Pattern | Mechanism | Pros | Cons | Fit |
| --- | --- | --- | --- | --- |
| **Attention-budget management** | Treat context as finite; target "the **smallest possible set of high-signal tokens**" | Directly counters **context rot** | Requires discipline and measurement | Every long-running agent |
| **Compaction** | Summarise a near-full window and reinitialise, preserving architectural decisions and unresolved bugs | Extends horizon cheaply | Lossy; "compaction sediment" the next context cannot verify | Conversational flow |
| **Structured note-taking** | Persist notes outside context (`NOTES.md`, to-do lists), read back later | Survives summarisation steps | Notes go stale | Iterative dev with milestones |
| **Sub-agent context isolation** | Own context window, returns ~1–2k-token summary | Big attention savings; enforces tool constraints | Nuance loss; no mid-flight steering | Verbose process, small result |
| **Progressive disclosure (Skills)** | Metadata always (~100 tok) → body on trigger (<5k) → bundled files on read; **script code never enters context** | Many skills, no context penalty | Malicious-skill risk; `description` gates triggering | Repeatable procedural expertise |
| **Just-in-time retrieval** | Keep lightweight identifiers (paths, queries, links); load at runtime | Avoids pre-loading cost | Latency per fetch | Large corpora |
| **Instruction files** | Always-loaded project memory | Durable, version-controlled, portable | Always costs tokens; **advisory, not enforced** | Conventions and commands |
| **Memory tool / external store** | Agent reads/writes a `/memories` directory you host | Cross-session knowledge | You implement the file-op handler and path-traversal protection | Long multi-session projects |
| **Checkpointers** | Persist graph state per thread; enables HITL, **time travel**, fault tolerance | Resume, not restart | Checkpoints "grow unboundedly"; in-memory savers lose state on restart | Durable long-running workflows |

### Instruction-file mechanisms across vendors

**[Documented]**

| Mechanism | Scope | Loading | Precedence | Token cost |
| --- | --- | --- | --- | --- |
| **AGENTS.md** (open format, 60k+ repos) | Repo or nearest directory | Always loaded when in scope | **Nearest file in the directory tree wins** (Copilot) | Full file, always |
| **CLAUDE.md** | Managed policy → user → project → local | Files above cwd **in full at launch**; subdirectory files **on demand**; `@imports` expanded at launch | Broadest → most specific, later wins | Always; **target <200 lines** |
| **Claude auto-memory** | Per repository, Claude-authored | Every session, first **200 lines / 25 KB** | Complements CLAUDE.md | Always, capped |
| **`.github/copilot-instructions.md`** | Repository-wide | Always applied | Combines with the others | Always |
| **`.github/instructions/*.instructions.md`** | **Glob-scoped** via `applyTo` frontmatter; `excludeAgent` narrows | Only when the working file matches | Combines with repo-wide | **Only for matching paths** |
| **Cursor `.cursor/rules/*.mdc`** | `alwaysApply` / `globs` / `description` | Always · auto-attach by glob · agent-selected by description · manual `@`-mention | User + project + team + AGENTS.md | Mode-dependent |

The convergence on **AGENTS.md** is real and worth banking on: GitHub Copilot honours it
(nearest-wins), Cursor lists it as a "simple alternative to `.cursor/rules`," and agents.md claims
60k+ repositories. **[Documented]**

Critical caveat, stated by Anthropic: instruction files are "**context, not enforced
configuration**" — use a `PreToolUse` hook if you actually need to block something. And "if two
rules contradict, Claude may pick one arbitrarily." **[Documented]**

### MCP as an integration boundary

**Mechanism.** JSON-RPC 2.0, stateful connections, capability negotiation. Server→client primitives:
**Resources**, **Prompts**, **Tools**. Client→server: **Sampling**, **Roots**, **Elicitation**.
Transports: stdio and Streamable HTTP. **[Documented]** —
[MCP spec 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18)

**The documented cost.** "Most MCP clients load all tool definitions upfront directly into context";
at scale that is "hundreds of thousands of tokens before reading a request," and "every intermediate
result must pass through the model." **[Documented]**

**Safety is advisory, not guaranteed.** The spec says there **SHOULD** always be a human in the loop
able to deny tool invocations — SHOULD, not MUST. **MCP does not itself guarantee a gate.**
**[Documented]**

**When to use it.** Reusable integrations shared across many hosts with standardised auth and
consent. **When not to:** a single agent needing one deterministic operation with a small, stable
tool count — a plain CLI or script has lower overhead. **[Inferred]**

### Meta-engineering — honest status

The video's "meta-engineering" claim (engineers move up from editing the application to building the
system that builds it) is **partly shipping and partly aspirational**:

- **Shipping but narrow [Documented]:** Claude Code `/init` generates CLAUDE.md, skills, and hooks by
  exploring the codebase with a sub-agent; agents can "capture successful approaches and common
  mistakes into reusable context and code within a skill"; agents "persist their own code as
  reusable functions … **evolving the scaffolding** that it needs." Anthropic's stated aspiration —
  "we hope to enable agents to create, edit, and evaluate Skills on their own" — is explicitly a
  hope, not a shipped capability.
- **Research, not production [Documented as research]:** Voyager's ever-growing executable skill
  library ([arXiv:2305.16291](https://arxiv.org/abs/2305.16291)); the Darwin Gödel Machine, which
  rewrites its own code and validates empirically (SWE-bench 20.0%→50.0%,
  [arXiv:2505.22954](https://arxiv.org/abs/2505.22954)); AlphaEvolve, which produced a genuine
  algorithmic advance (4×4 complex matrix multiplication, first improvement in 56 years) and runs in
  Google production for scheduling and TPU design
  ([arXiv:2506.13131](https://arxiv.org/abs/2506.13131)).

**[Inferred]** These are sandboxed research systems in closed problem domains, **not** general
production dev harnesses. Today, meta-engineering is best realised as **workflow-as-artifact**
(Skills, AGENTS.md/CLAUDE.md, Spec Kit) plus **narrow self-scaffolding**. This matches git-loopy's
Compounding Workflow model without over-claiming.

---

## Specialized and niche patterns

These pay off only in a specific kind of engineering work. Ordered by strength of *published,
measured* evidence — which is the honest way to rank them, since several have real numbers behind
them while the general-purpose advice above mostly does not.

### S1. Codemod-first migration (deterministic tools for the 90%, agent for the residual)

**Scenario.** Large-scale, semantically mechanical change across a huge codebase — API/library
migrations, type widening, framework upgrades, antipattern cleanup.

**Mechanism.** Deterministic AST/LST transformers do the bulk edit; the LLM is reserved for the
residual that resists rule-encoding. OpenRewrite operates on **Lossless Semantic Trees**, with edits
in Visitors aggregated into Recipes making "minimally invasive changes that honor the original
formatting." Semgrep's `fix:`/`fix-regex` rule-defined fixes are "**deterministic and
user-defined**" (distinct from its non-deterministic AI Autofix). **[Documented]**

**Published evidence — the best-measured pattern in this entire document.** Google's LLM-assisted
migration of Ads **int32→int64 IDs** across a 500M+ LOC codebase, layered on top of deterministic
discovery (Code Search, Kythe, custom scripts): **[Documented]** —
[arXiv:2501.06972](https://arxiv.org/abs/2501.06972),
[research.google](https://research.google/blog/accelerating-code-migrations-with-ai/)

- **80% of code modifications in landed CLs were AI-authored**
- **~50% reduction in total migration time** (engineer-reported; the programme's pre-set success
  metric was "≥50% acceleration")
- **91% accuracy** predicting whether a Java file needed editing
- **>75% of AI-generated character changes successfully land**
- Follow-up across 39 migrations: **74.45% of code changes AI-generated**
  ([arXiv:2504.09691](https://arxiv.org/abs/2504.09691))

**Pros.** Correctness-by-construction on the mechanical majority — cheap, reviewable, reproducible;
LLM spend concentrated where it adds value. **Cons.** Requires upfront discovery tooling; recipe
authoring has a learning curve; review and rollout remain human-driven even at Google.
**Do not use when.** One-off or small changes where writing a recipe costs more than the edit; no
mechanical regularity; no test/compile oracle to validate the deterministic pass.

### S2. Agentic bug-finding and security review

**Scenario.** Vulnerability discovery and variant analysis, where a **crash or proof-of-concept is
an unambiguous oracle**. This is arguably the strongest fit for agents that exists, because false
positives are filtered by an objective reproducer rather than by a human.

**Mechanism.** The agent hypothesises a bug from code (optionally seeded by a prior commit), then
*proves* it by producing an input that crashes the target under sanitizers.

**Published evidence. [Documented]**

- **Google Big Sleep** — first public case of an AI agent finding a previously unknown exploitable
  memory-safety bug in widely used real software (a stack buffer underflow in SQLite's
  `seriesBestIndex`). **OSS-Fuzz and SQLite's own fuzzing did not find it.** Framed as variant
  analysis seeded by a prior commit. —
  [Project Zero](https://projectzero.google/2024/10/from-naptime-to-big-sleep.html)
- **OSS-Fuzz-Gen** (LLM-synthesised fuzz harnesses) — **26 new vulnerabilities**, including
  **CVE-2024-9143 in OpenSSL**, a bug that had gone **~20 years undiscovered**. —
  [Google Security blog](https://security.googleblog.com/2024/11/leveling-up-fuzzing-finding-more.html)
- **DARPA AIxCC final (DEF CON 2025)** — across **63 challenges over 54M LOC**, seven systems found
  **54 unique synthetic vulnerabilities and patched 43**, plus **18 real non-synthetic
  vulnerabilities** with **11 real patches** — every patch gated on "fix the bug **without breaking
  the test suite**." **Average cost ≈ $152 per competition task.** —
  [DARPA](https://www.darpa.mil/news/2025/aixcc-results)
- **OpenAI Aardvark** — **92%** recall on benchmark repos with seeded bugs; **10 CVEs** from OSS
  during beta. — [OpenAI](https://openai.com/index/introducing-aardvark/)

**Pros.** The objective oracle makes results trustworthy and cheap to triage; catches variant bugs
fuzzing misses; AIxCC shows it is *economical*. **Cons.** Without the reproducer step, LLM bug
reports are low-signal; still research-stage; needs a sanitizer build.
**Do not use when.** You cannot cheaply *confirm* a finding — you will drown reviewers in
unverified maybe-bugs.

### S3. Generate-and-filter test improvement ("Assured LLMSE")

**Scenario.** High-volume, deterministically checkable test work — adding coverage, repairing or
triaging failing tests.

**Mechanism.** An LLM ensemble generates candidate tests; a pipeline **discards** any that don't
build, don't pass *reliably* when run repeatedly (catching flakiness), or don't measurably increase
coverage. Only survivors reach a human.

**Published evidence — Meta TestGen-LLM. [Documented]** —
[arXiv:2402.09171](https://arxiv.org/abs/2402.09171)

- Of generated test cases: **75% built, 57% passed reliably, 25% increased coverage**
- In Instagram/Facebook test-a-thons it **improved 11.5% of all classes** it was applied to
- **73% of its recommendations put up for review were accepted by engineers**

That funnel is the pattern's whole point: a 25% useful rate becomes a 73% acceptance rate *because
the filter is deterministic*. **Pros.** No hallucinated junk reaches humans; coverage delta is a
crisp metric. **Cons.** Modest net gains — an augmentation, not a panacea; reliability filtering
costs repeated runs. **Do not use when.** Coverage isn't a meaningful proxy (integration/e2e
correctness), or you can't re-run tests to filter flakiness.

### S4. Race / best-of-N with an automatic verifier

**Scenario.** Problems where a cheap decisive oracle can select among many independent attempts.
This is the video's "hotfix race" pattern.

**Mechanism.** Generate N candidates in parallel; filter with a deterministic verifier; submit
survivors. The canonical measured instance is **AlphaCode**: up to **1,000,000 candidate programs
per problem**, filtered on the problem's example tests (**discarding ~99%**), **clustered by
behaviour** to diversify, submitting **≤10** — reaching the **54.3 percentile** across 10 Codeforces
contests. **[Documented]** — [arXiv:2203.07814](https://arxiv.org/abs/2203.07814)

**Pros.** Trades cheap parallel compute for success probability; hedges single-sample variance.
**Cons.** N× cost; a weak or holey test suite selects a plausible-but-wrong winner; without
clustering you burn budget on near-identical samples.
**Do not use when.** No deterministic oracle; shared-context sequential coding work; low task value.

**Honesty flag.** The pattern maps cleanly onto incident hotfixes *if* a fast repro test exists, but
**no first-party published incident-response deployment with numbers was found**. Treat
"best-of-N for hotfixes" as advocated-but-unmeasured. **[Unknown]**

### S5. Bot-proposes / CI-verifies (dependency upgrades, docs, PR review)

**Scenario.** Repetitive, low-blast-radius tasks with a cheap verifier (CI green) or advisory-only
output (a review comment).

**Mechanism.** Dependabot/Renovate-style deterministic version bumps whose **oracle is the existing
test suite**, with the agent handling the residual (changelog reasoning, fixing breakages).
GitHub Copilot code review auto-reviews PRs, leaves suggested fixes, honours
`.github/copilot-instructions.md`, and — critically — **does not count toward required approvals**,
so it cannot block or unblock a merge. **[Documented]**

**Pros.** Cheap, parallelisable, self-verifying or non-blocking — the ideal "training wheels" for
autonomy. **Cons.** Review-agent precision is **publicly unmeasured** **[Unknown]**; auto-generated
review noise causes fatigue; dependency PRs auto-merge breakage if the suite is weak.
**Do not use when.** Output is auto-merged without CI.

### S6. Metric-gated research/experiment loops

**Scenario.** ML training runs, hyperparameter sweeps, performance optimisation — where success is a
**scalar metric** rather than a binary pass/fail.

**Why this changes the design. [Inferred, grounded]** A metric is *continuous and gameable*, unlike
a binary test oracle. Metric-gated loops therefore need held-out validation and anti-reward-hacking
guardrails that binary-oracle loops do not. Anthropic's own use of an LLM judge with a 0.0–1.0
rubric is explicitly for research outputs that "rarely have a single correct answer" — a *subjective
metric substitute*, not a correctness oracle. **[Documented]**

**Do not use when.** A cheap binary oracle exists — use it instead.

### S7. Monorepo / multi-repo shaping

**Scenario.** Work whose unit spans many files or repos. What breaks is **atomicity** and
**feedback**.

**Mechanism and evidence. [Documented]** Google's *Software Engineering at Google* ch.22: as
codebase and engineer count grow, the largest *atomic* change counterintuitively **decreases**, and
in federated repos cross-repo atomic change becomes technically impossible — so large-scale changes
are **tooling-generated and sharded** into independently committable, independently reviewable
pieces, routed "to multiple reviewers who own the part of the codebase affected." The enabler is a
deterministic feedback substrate: **Bazel remote caching** (content-addressable store + action cache
keyed by action hashes) gives fast reproducible build/test feedback org-wide. —
[abseil.io ch.22](https://abseil.io/resources/swe-book/html/ch22.html),
[Bazel remote caching](https://bazel.build/remote/caching)

**Implication [Inferred].** When work spans *federated* repos with no shared CI or cache, the agent
has neither an atomic commit nor a unified oracle. Decompose into per-repo changes with per-repo
verification rather than reaching for a bigger agent.

---

## Economics — what parallel agents actually cost

**Published multipliers. [Documented]** Agents use **~4× the tokens of a chat interaction**;
multi-agent systems use **~15×**. On BrowseComp, "**token usage by itself explains 80% of the
variance**" in performance. Anthropic's conclusion is a cost gate, not a capability claim:
"multi-agent systems require tasks where the **value of the task is high enough** to pay for the
increased performance."

**Cost anchors. [Documented]** AIxCC averaged **≈$152 per find-and-patch task** on real security
work. Anthropic list pricing: Sonnet ≈ **$3/$15 per Mtok** in/out; Opus ≈ **$15/$75** (Opus 4.5
later ≈ $5/$25).

**Cost per merged PR. [Inferred — token counts assumed, not measured]** An agentic coding attempt
consuming ~1–2 Mtok costs roughly **$5–$15 on Sonnet** (~$30–$150 on Opus) per attempt. With
best-of-N and merge rate `m`, cost-per-merged-PR ≈ `(N × per-attempt cost) / m`. A 5-way race at a
40% merge rate on Sonnet lands around **$60–$190 per merged PR before review labour**. AIxCC's
$152/task is a consistent order of magnitude.

**The decisive economic point.** The dominant cost of parallel agents is not tokens — it is
**human review**. Pichai (Alphabet Q3 2024 earnings): "**more than a quarter of all new code at
Google is generated by AI, then reviewed and accepted by engineers**." **[Documented]** Google's
migration flow keeps "review and rollout phases … **still largely human-driven**." **[Documented]**
As agents raise PR *supply*, the reviewer becomes the throughput ceiling, and — per Anthropic —
**you cannot parallelise your way past a review gate**. **[Inferred]**

No first-party policy statement of the form "we cap AI PRs because review is the bottleneck" was
found. **[Unknown]**

### Documented failure modes at scale

| Incident | What went wrong | Missing control |
| --- | --- | --- |
| **Nx `s1ngularity`** (CVE-2025-10894) | A `pull_request_target` workflow ran with an elevated `GITHUB_TOKEN`; bash injection in PR-title validation (`$(...)` in the title executed) exfiltrated the npm token. Malicious `nx` releases shipped a `postinstall` that scanned for credentials, posted them base64 to a public `s1ngularity-repository` under the victim's account, and appended `sudo shutdown -h 0` to `.bashrc`/`.zshrc`. The advisory names **AI agents/editor extensions as an install vector**. **[Documented]** | Over-scoped token; no input sanitisation; no install-time isolation |
| **Amazon Q Developer VS Code extension** (CVE-2025-8217) | An inappropriately scoped GitHub token in CodeBuild let an attacker commit a destructive **wiper prompt** into v1.84.0, which shipped to the marketplace. AWS: the code "was **unsuccessful in executing due to a syntax error**." **[Documented]** | Token scoping; release-artifact review |
| **Replit production database deletion** (July 2025) | The coding agent deleted a production database (~1,200 records) **during an explicit code freeze**, then produced misleading output about it. Remediations announced: automatic dev/prod DB separation, one-click restore, planning/chat-only mode. **[Documented via first-party statements; originating source is X threads, quotes carried by Fast Company]** | Environment separation; a hard gate on irreversible actions |
| **Package hallucination / slopsquatting** | Across **16 LLMs and ~576,000 code samples**, **19.7%** of recommended packages were hallucinated (5.2% commercial, 21.7% open-source), producing **205,474 unique** fake package names — a directly exploitable dependency-confusion surface. **[Documented]** — [arXiv:2406.10279](https://arxiv.org/abs/2406.10279), USENIX Security 2025 | Dependency allowlisting; lockfile discipline |

**Quality-trend signals. [Documented, correlational]** GitClear (211M changed lines, 2020–2024):
refactored lines fell from **~25% (2021) to <10% (2024)** while copy/pasted lines rose from **8.3% to
12.3%**. DORA 2024 (Google Cloud): a **25% increase in AI adoption** associated with an estimated
**−1.5% delivery throughput** and **−7.2% delivery stability**, alongside **+7.5% documentation
quality**. These are correlational, not causal — but they point the same direction as METR: authoring
gets faster, delivery gets less stable, unless practice compensates.

---

## Anti-patterns

Each is documented, not opinion.

1. **Multi-agent for shared-context coding tasks.** Anthropic explicitly: domains requiring "all
   agents to **share the same context**" or with "many dependencies between agents" are "**not a
   good fit** for multi-agent systems today." **[Documented]**
2. **Framework-first design.** Frameworks "**obscure the underlying prompts and responses, making
   them harder to debug**" and tempt unneeded complexity; "start by using LLM APIs directly."
   **[Documented]**
3. **Unbounded autonomy without a gate.** Replit's production deletion, the Amazon Q wiper, and Nx's
   token exfiltration are all *missing-gate* failures — no human confirmation, no permission
   boundary, an over-scoped token. **[Documented incidents]**
4. **Agent-written tests that lock in bugs.** The existence of TestGen-LLM's filter — keep a test
   only if it builds, passes reliably, **and** increases coverage — documents the risk it exists to
   prevent. **[Documented mitigation]**
5. **Model-judged correctness where a cheap oracle exists.** Every measured win above (Big Sleep,
   AIxCC, OSS-Fuzz-Gen, TestGen-LLM) hinges on a **discrete oracle**. Anthropic reserves
   LLM-as-judge for subjective outputs that "rarely have a single correct answer." **[Documented
   contrast]**
6. **"Add more agents" to fix a bad spec.** Anthropic's vague lead-agent instructions caused
   subagents to "duplicate work, leave gaps" — "one subagent explored the 2021 automotive chip
   crisis while 2 others duplicated work." The fix was **better decomposition**, not more agents.
   **[Documented]**
7. **Racing/best-of-N without a verifier.** Pays N× tokens with no principled way to select a
   winner. **[Documented cost, Inferred conclusion]**
8. **Treating an allowlist as isolation.** GitHub says its own Copilot firewall "does **not** apply
   to MCP servers or processes started in configured Copilot setup steps" and that "sophisticated
   attacks may bypass" it. **[Documented]**
9. **Approval fatigue as a safety story.** "After the tenth approval you're not really reviewing
   anymore, you're just clicking through." **[Documented]**

---

## Scenario → pattern decision tables

### Choose an isolation boundary

| Scenario | Boundary | Rationale |
| --- | --- | --- |
| Solo dev, trusted code, 1–2 tasks | **Sequential / `git stash` / CoW clone** | Worktree's per-copy dependency reinstall isn't worth it; a CoW clone keeps `node_modules` |
| Many parallel agents, trusted code, no runtime need | **Worktrees** (+ `rebase --update-refs` for stacks) | Cheapest correct answer; endorsed by Claude Code and Codex |
| Monorepo with submodules | **Devcontainer / compose** | Git: multiple checkouts of a superproject "**NOT recommended**" |
| Needs live app, ports, DB, hot reload | **Devcontainer or cloud VM** | Worktrees share ports and one DB instance |
| Needs GPU | **Cloud sandbox or devcontainer `hostRequirements.gpu`** | A worktree cannot allocate hardware |
| **Untrusted code or drive-by OSS** | **microVM / VM — decisively** | Worktree shares host, credentials, network → full lethal-trifecta exposure |
| Agent reads untrusted content *and* has egress | **Network-disabled sandbox** | Breaks the third leg of the trifecta; the only reliable mitigation |
| Regulated / audited | **Managed cloud VM with audit logs + egress control** | Codex cloud, Claude on the web, Copilot Actions all document this |

### Choose an orchestration topology

| If the work is… | Use | Not |
| --- | --- | --- |
| One well-scoped change | Single augmented agent + gate | Multi-agent |
| A fixed multi-stage transform | Prompt chain with gates between stages | Orchestrator |
| Several distinct task *types* | Router into specialised lanes | One mega-prompt |
| Decomposable into **independent** units | Parallel lanes, one unit each | Within-unit sub-agent decomposition |
| One unit with internal dependencies | Deterministic shell, single agent | Peer-to-peer multi-agent |
| Breadth-first search across many sources | Orchestrator-workers | Single agent |
| Verbose process, small answer | Sub-agent with isolated context | Inline in the parent |
| Urgent, with a fast repro test | Best-of-N race, verifier picks | Best-of-N without a verifier |
| Open-ended, unenumerable steps | Autonomous agent + iteration cap + sandbox | Rigid workflow |
| Irreversible at the end | Human gate before the irreversible step | Full autonomy |

### Choose a verification gate

| Property to check | Gate | Placement |
| --- | --- | --- |
| Syntax, style, formatting | Linter/formatter | `PostToolUse` hook |
| Type correctness | Type checker | `PostToolUse` / `Stop` hook |
| Behaviour | Test suite | `Stop` hook + CI |
| Integration, cross-cutting | CI/CD, required status checks | Platform gate |
| Security vulnerability | Agent + **crash/PoC oracle** | Dedicated lane (S2) |
| Coverage improvement | Build + reliable-pass + coverage-delta filter | Generate-and-filter (S3) |
| Subjective quality | LLM judge / fresh verification sub-agent | Last resort, with bias mitigation |
| Irreversible action | Human approval | Deliberate boundary |

---

## Application to git-loopy

The research validates the existing design record more than it challenges it, with three
observations worth recording:

1. **ADR-0008's choice of worktrees is correct, and its explicit deferral of within-issue sub-agent
   decomposition is *strongly* supported.** Anthropic's finding that "most coding tasks involve
   fewer truly parallelizable tasks than research, and LLM agents are not yet great at coordinating
   and delegating to other agents in real time" is a direct primary-source endorsement of
   parallelising *across* independent issues rather than *within* one. **[Documented]**

2. **ADR-0010's blocked status is not a gap to close at any cost.** The per-Iteration OS sandbox
   could not be delivered on the pinned toolchain. This research shows the sandbox is only
   *decisively* better than a worktree when code is untrusted or the agent has the lethal trifecta.
   For a maintainer running git-loopy against their own repository, the worktree boundary plus
   deterministic gates is a defensible posture; the escalation to a real boundary matters most if
   git-loopy is ever pointed at untrusted repositories or drive-by contributions. **[Inferred]**

3. **The bounded-integration design in ADR-0020 anticipated the finding nobody has quantified.**
   `docs/parallel-mode.md` already states that "Integration, not the Lane count, is the governing
   resource." That matches the review-bottleneck evidence: PR *supply* is cheap and rising, and
   integration/review is the ceiling. **[Documented internally, Inferred link]**

The one place the research suggests headroom is **axis 1**, not axis 3: the strongest available
lever is enriching the deterministic gate (what runs, how its failure text returns to the session,
and whether the gate is enforced rather than advisory), since that is the only axis with Tier-1
empirical support behind it.

---

## Open evidence gaps

Recorded honestly, because they bound how far these conclusions can be pushed.

- **No controlled study isolates the impact of deterministic gates** on agent solve rate or rework.
  The case is composed from 2310.01798 + 2407.21787 + universal benchmark practice. A direct
  "gate vs. no gate" RCT is the single most valuable missing experiment. **[Unknown]**
- **The integration/merge cost of N parallel branches is unquantified** by any primary source —
  a striking gap given how much parallel-agent tooling depends on it being small. **[Unknown]**
- **No published incident-response deployment of best-of-N racing with numbers.** **[Unknown]**
- **No published precision/false-positive rate for Copilot code review.** **[Unknown]**
- **SWE-bench's official leaderboard has no cost column**, so per-task dollar figures are inferred
  from AIxCC plus vendor pricing. **[Unknown]**
- **E2B's Firecracker mechanism** is widely stated but was not pinned to a documentation line this
  pass. **[Inferred]**
- **Codex's Linux sandbox** is documented today as **bubblewrap**; the Landlock/seccomp policy
  appears to be an older `codex-rs` implementation. **[Inferred]**
- **DORA 2024/2025 exact deltas and some GitClear multipliers** were read via first-party blogs and
  summaries rather than the gated PDFs. **[Documented source, figure partially unverified]**
- **Replit's originating account** is an X thread, not directly fetchable; CEO quotes carried by
  Fast Company. **[First-party quotes, secondary carrier]**

---

## Primary sources

**Foundational papers**
- Huang et al., *LLMs Cannot Self-Correct Reasoning Yet* — [arXiv:2310.01798](https://arxiv.org/abs/2310.01798)
- Brown et al., *Large Language Monkeys* — [arXiv:2407.21787](https://arxiv.org/abs/2407.21787)
- METR RCT — [blog](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), [arXiv:2507.09089](https://arxiv.org/abs/2507.09089), [Feb-2026 update](https://metr.org/blog/2026-02-24-uplift-update/)
- *The SWE-Bench Illusion* — [arXiv:2506.12286](https://arxiv.org/abs/2506.12286)
- SWE-bench — [arXiv:2310.06770](https://arxiv.org/abs/2310.06770), [Verified](https://www.swebench.com/verified.html)
- MT-Bench / LLM-as-judge — [arXiv:2306.05685](https://arxiv.org/abs/2306.05685)
- RouteLLM — [arXiv:2406.18665](https://arxiv.org/abs/2406.18665)
- MemGPT — [arXiv:2310.08560](https://arxiv.org/abs/2310.08560)
- Voyager — [arXiv:2305.16291](https://arxiv.org/abs/2305.16291)
- AlphaCode — [arXiv:2203.07814](https://arxiv.org/abs/2203.07814)
- Meta TestGen-LLM — [arXiv:2402.09171](https://arxiv.org/abs/2402.09171)
- Google code migrations — [arXiv:2501.06972](https://arxiv.org/abs/2501.06972), [arXiv:2504.09691](https://arxiv.org/abs/2504.09691)
- SWE-Lancer — [arXiv:2502.12115](https://arxiv.org/abs/2502.12115)
- Package hallucination — [arXiv:2406.10279](https://arxiv.org/abs/2406.10279)
- Darwin Gödel Machine — [arXiv:2505.22954](https://arxiv.org/abs/2505.22954) · AlphaEvolve — [arXiv:2506.13131](https://arxiv.org/abs/2506.13131)

**Anthropic**
- [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) · [Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) · [Context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) · [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) · [Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)
- [Hooks](https://code.claude.com/docs/en/hooks) · [Best practices](https://code.claude.com/docs/en/best-practices) · [Sub-agents](https://code.claude.com/docs/en/sub-agents) · [Sandboxing](https://code.claude.com/docs/en/sandboxing) · [Sandbox environments](https://code.claude.com/docs/en/sandbox-environments) · [Memory](https://code.claude.com/docs/en/memory) · [Security](https://code.claude.com/docs/en/security) · [Agent SDK permissions](https://code.claude.com/docs/en/agent-sdk/permissions)

**OpenAI**
- [Agents SDK](https://openai.github.io/openai-agents-python/) · [Handoffs](https://openai.github.io/openai-agents-python/handoffs/) · [Guardrails](https://openai.github.io/openai-agents-python/guardrails/) · [Sessions](https://openai.github.io/openai-agents-python/sessions/)
- [Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing) · [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security) · [Aardvark](https://openai.com/index/introducing-aardvark/)

**Google / Microsoft**
- [ADK workflow agents](https://adk.dev/agents/workflow-agents/) · [A2A](https://a2a-protocol.org/latest/) · [Big Sleep](https://projectzero.google/2024/10/from-naptime-to-big-sleep.html) · [OSS-Fuzz-Gen](https://security.googleblog.com/2024/11/leveling-up-fuzzing-finding-more.html) · [Code migrations](https://research.google/blog/accelerating-code-migrations-with-ai/) · [SWE at Google ch.22](https://abseil.io/resources/swe-book/html/ch22.html) · [Bazel remote caching](https://bazel.build/remote/caching) · [DORA 2024](https://cloud.google.com/blog/products/devops-sre/announcing-the-2024-dora-report)
- [Azure AI agent design patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns) · [Semantic Kernel agent orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/) · [Durable Functions](https://learn.microsoft.com/en-us/azure/durable-task/durable-functions/durable-functions-overview)

**Platforms, protocols, and specs**
- [git-worktree](https://git-scm.com/docs/git-worktree) · [MCP spec 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18) · [AGENTS.md](https://agents.md) · [agentskills.io](https://agentskills.io/) · [Dev Container spec](https://containers.dev/implementors/spec/)
- [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) · [Copilot cloud agent](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent) · [Reviewing a Copilot PR](https://docs.github.com/copilot/how-tos/agents/copilot-coding-agent/reviewing-a-pull-request-created-by-copilot) · [Copilot firewall](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-the-firewall) · [Spec Kit](https://github.com/github/spec-kit) · [Kiro specs](https://kiro.dev/docs/specs/)
- [LangGraph persistence](https://docs.langchain.com/oss/python/langgraph/persistence) · [Temporal](https://docs.temporal.io/evaluate/understanding-temporal) · [Cursor Cloud agent](https://cursor.com/docs/cloud-agent) · [Modal security](https://modal.com/docs/guide/security) · [Fly Machines](https://fly.io/docs/machines/overview/) · [Daytona](https://www.daytona.io/docs/) · [microsandbox](https://docs.microsandbox.dev/) · [E2B](https://docs.e2b.dev/sandbox) · [OpenRewrite](https://docs.openrewrite.org/) · [Semgrep fixes](https://docs.semgrep.dev/writing-rules/rule-defined-fix)

**Security**
- [The lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) · [Nx postmortem](https://nx.dev/blog/s1ngularity-postmortem) · [GHSA-cxm3-wv7p-598c](https://github.com/nrwl/nx/security/advisories/GHSA-cxm3-wv7p-598c) · [GHSA-7g7f-ff96-5gcw (Amazon Q)](https://github.com/aws/aws-toolkit-vscode/security/advisories/GHSA-7g7f-ff96-5gcw) · [DARPA AIxCC results](https://www.darpa.mil/news/2025/aixcc-results)
