Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=improve-codebase-architecture
```

```bash
npx skills update improve-codebase-architecture
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/improve-codebase-architecture)

## What it does

`improve-codebase-architecture` surveys a codebase for **deepening opportunities**. These are places where a shallow module (an interface nearly as complex as the thing it hides) could become a deep one. It writes them up as a self-contained HTML report, and then [grills](https://www.aihero.dev/ai-coding-dictionary/grilling) you through the one you pick.

It never changes application code. It produces a conversation and one HTML file in your OS temp directory, and may update the glossary or record an ADR during the grilling loop. You do the refactor later, in a separate [session](https://www.aihero.dev/ai-coding-dictionary/session), through the normal build flow. This makes it a survey, not a refactoring tool, so you can run it on a codebase you are not ready to touch yet.

Two filters stop the report from becoming generic cleanup advice. First, every candidate must pass the **deletion test**: if you removed this module, would its complexity move behind a smaller interface, or spread across the callers? Only the first case gets a card. Second, unless you point it at a specific area, it reads recent commit history first and focuses the scan on paths that change often. A deepening in code that nobody touches is a refactor that never pays back.

## When to reach for it

You invoke this by typing `/improve-codebase-architecture`; the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) will not reach for it on its own.

It is not a step in the main build loop. You run it periodically to queue up more work that improves the codebase. People use it in four situations:

| Situation | How it is used |
| --- | --- |
| Routine upkeep | Run it every few days, or when you have a spare moment, so the structure does not decay between features. |
| Before a big build | Point it at the [spec](https://www.aihero.dev/ai-coding-dictionary/spec) and ask "how can we make this change easy?" This is the most effective prompt for it. |
| Brownfield audit | Run it on a large, unstructured or [vibe-coded](https://www.aihero.dev/ai-coding-dictionary/vibe-coding) repo to find out what shape it is in. |
| Legacy test work | Use it to find the missing seams before you write tests against untestable code. |

Where it is confusable with siblings:

- To design one module you have already chosen, use [codebase-design](./codebase-design.md). This skill finds the module to work on, and `codebase-design` is where you design it.
- For a whole effort too big to hold in one session, use [wayfinder](./wayfinder.md).
- For "this specific thing is broken," use [diagnosing-bugs](./diagnosing-bugs.md). If that diagnosis finds no good seam to lock the bug down, you can start this survey yourself; diagnosis does not invoke it.

## Prerequisites

None to run it. If `GLOSSARY.md` or ADRs in `docs/adr/` exist, it reads them and uses your domain's own nouns. A candidate then reads as "deepen the Order intake module," not "refactor the FooBarHandler."

It writes in two places. The report goes to `<tmpdir>/architecture-review-<timestamp>.html`, outside the repo. During the grilling loop it adds or sharpens terms in `GLOSSARY.md`, and creates that file if it does not exist. It also offers to record a rejected candidate as an ADR, so a future run does not suggest it again.

## Depth, and the report that hunts for it

The skill rests on one idea: **depth**. A deep module puts a lot of behaviour behind a small, stable interface. A shallow module exposes its implementation through an interface nearly as wide as the code beneath it. The report looks for three forms of shallowness:

- Pure functions extracted only for testability, while the real bugs are in how callers use them (no **locality**).
- Modules that leak across their **seams**.
- A concept you cannot understand without opening five files.

For each one, it proposes the deepening that fixes it.

Each candidate is a card with the files involved, the friction, a plain-English solution, the benefit in terms of **locality** and **leverage**, a before/after diagram, and a strength badge.

| Badge | What it means for you |
| --- | --- |
| `Strong` | The deletion test passes clearly and the friction is real. Take these seriously. |
| `Worth exploring` | Plausible deepening, but the payoff depends on where the code is going next. |
| `Speculative` | Included for completeness. You can ignore most of these. |

The report ends with a **Top recommendation**, the candidate it would do first. Then the skill stops and asks which candidate you want to explore. At that point you have decided nothing, and no code has changed.

Here the report is **dark mode only**: one dark palette for the page, candidate cards, badges and Mermaid diagrams, with no light variant or theme toggle.

## What happens after you pick one

When you pick a candidate, a [grilling](./grilling.md) session starts on it. It covers the constraints, what goes behind the seam, which tests survive, and what the deepened interface should look like. The output of that session is a decision, not a refactor diff. At its conclusion the skill calls [next](./next.md), which takes the decision into [grill-with-docs](./grill-with-docs.md) as an idea. From there the normal flow applies: [to-spec](./to-spec.md), then [to-tickets](./to-tickets.md), then [implement](./implement.md).

## Common questions

**It grilled me for an hour about one idea instead of showing me options. Can I turn that off?**

Yes. Say so when you invoke it ("don't grill me, just show the report"). This is the most common complaint about the skill. One user liked it as "a convenient way to get a thorough analysis of improvements," but after the grilling loop was added, found it "borderline unusable." In their sessions it proposed a single solution and then asked "10's or 100's of questions." The design intent is that the report comes first, and the grilling starts only on a candidate you chose. But weaker [models](https://www.aihero.dev/ai-coding-dictionary/model) skip straight to an interview about the first idea they had. Results vary a lot by model, and the pinned skill does not have a documented no-grill mode.

**The report opened as unstyled raw HTML with no diagrams. What happened?**

The report loads Tailwind and Mermaid from CDNs, so it needs network access when you open it. If something blocks those scripts, the page breaks with no error. In the reported case, a security hook required SRI hashes. The agent added them, but the CDN served different bytes to the browser than to the `curl` that computed the hash, so the browser blocked the script. Offline and locked-down environments have the same problem. The agent cannot see it, because it never renders the page. As a workaround, ask for inline CSS and hand-built SVG diagrams instead of the CDN setup, retaining the dark palette.

**It gave me twelve candidates. Do I work through them in the same session or start a new one?**

Use one candidate per session. If you work through several in one conversation, the [context window](https://www.aihero.dev/ai-coding-dictionary/context-window) fills with the report, the grilling, the domain-model edits and the code changes all at once. The report is only a temp file, so carry the candidate forward, not the file. Pick one, grill it, and let `/next` take the decision into `/grill-with-docs`. Turn the rest into [tickets](https://www.aihero.dev/ai-coding-dictionary/ticket) that you can pick up separately later. Put the chosen improvement into a spec instead of going straight to implementation.

**How should I prompt it?**

Prompt it with the next thing you are building. If a big build is coming up, point it at the spec and ask "how can we make this change easy?" A run with no prompt looks for hot spots on its own. That is fine for routine upkeep, but a direction makes the report actionable.

**Does it work on a large legacy codebase?**

Partly. It works well on big existing codebases that lack consistent structure, and it is the recommended upkeep tool after any one-time structural setup. But users with out-of-control projects report it "helped a little but still doesn't seem to cut it." One developer with an eight-year-old legacy codebase reported that the model went in circles, though the same skill produces a clean graph on a tidy repo. There is no dedicated `/refactor` skill for that case at the pin. If the codebase has no shared vocabulary, run [grill-with-docs](./grill-with-docs.md) first to create one. That usually makes this skill's output much better.

**How is this different from `/codebase-design`?**

`/codebase-design` is a reference, not a session driver. It supplies the vocabulary (module, interface, depth, seam, adapter, leverage, locality), and this skill uses it. If you give a fresh agent `/codebase-design` as the task, it fails in a known way. It has no process of its own to follow, so the agent invents one, explores the code again, and runs for a very long time before it asks you anything. Run this skill, and let it use that one.

**Will it ever tell me the codebase is fine?**

Rarely, so know that before you start. The skill exists to output findings, so it tends to produce candidates instead of concluding that nothing is wrong. Use the strength badges to correct for this. If every candidate in a report is `Speculative`, the skill found nothing.

**Does it work in Copilot CLI or another harness?**

Yes. The exploration step says to spawn a sub-agent without naming a tool or agent type, so any [harness](https://www.aihero.dev/ai-coding-dictionary/harness) can use its own sub-agent dispatch.

**How do I actually implement deep modules in TypeScript?**

The skill does not ship a good answer. People often ask for a `TYPESCRIPT.md` with concrete file and module layouts for the principles, and it does not exist. The skill tells you where a deepening belongs and what goes behind the seam. You must turn that into a package or directory structure yourself.

## It's working if

- The candidates name your domain's concepts, not invented class names: "the Order intake module," not "the FooBarHandler."
- The candidates are in files you edited recently, not in parts of the repo nobody touches.
- No application code changed during the run. The report is in your temp directory; glossary and ADR edits capture decisions rather than implementing the refactor.
- It stops after the report and asks which candidate you want. It does not continue on its own.
- Each card explains the payoff as locality or leverage, and says which tests get simpler, not just "this is cleaner."
- When you reject a candidate for a lasting reason, it offers to record an ADR, so the next run does not suggest it again.

## Where it fits

`improve-codebase-architecture` is **periodic maintenance**. You start it every few days, outside the main build loop, to queue up work, not to do it. Its neighbours:

- [codebase-design](./codebase-design.md) owns the depth-and-seam vocabulary that every candidate uses.
- [grilling](./grilling.md) walks the decision tree after you choose a candidate.
- [domain-modeling](./domain-modeling.md) keeps `GLOSSARY.md` and the ADRs current as you make the decision.

Its output is an idea, which goes back into the main build flow at [grill-with-docs](./grill-with-docs.md). Its counterpart at the end of the main flow is `/retro`. This skill improves the code the agent works in, and `retro` improves the environment around it (checks, standards, steering files) after a build. Here, [next](./next.md) owns the closing transition after grilling, as well as routing when you are unsure which skill fits.
