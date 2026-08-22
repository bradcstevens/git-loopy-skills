# Skill connections

How the skills in [`skills/`](../skills) fit together: which ones call which, which ones nest inside
another's session, and which sequences they run in.

The set is **composable, not a fixed pipeline**. [`next`](./next.md) picks the earliest unresolved
gate rather than the next item on a checklist, so any skill can be an entry point. What follows are
the paths that actually get walked.

## Four kinds of connection

Every edge in this document is one of four kinds. Read the arrows with these in mind.

| Kind | Meaning | Example |
| --- | --- | --- |
| **Routes to** | One session ends, another begins — usually a fresh context | `/to-tickets` → `/implement` |
| **Runs inside** | Nested in the caller's session; owns no transition and records nothing of its own | `/implement` → `/tdd` |
| **Publishes to** | Leaves a durable evidence comment that a later session reads back | `/code-review` → the ticket |
| **Reads config from** | Depends on files another skill wrote | `/next` → `/setup-git-loopy-skills` |

One skill is a hub. [`next`](./next.md) is the **router** — it reads live state (tracker, branch,
diff, worktrees) and names one action. It does no work itself.

Eleven skills leave a durable evidence comment on the ticket they acted on and name the skill that
succeeds them: `code-review`, `grill-with-docs`, `implement`, `prototype`, `push`,
`research`, `resolving-merge-conflicts`, `to-spec`, `to-tickets`, `triage`, `wayfinder`.

## The connection map

```mermaid
flowchart LR
    setup["/setup-git-loopy-skills"]

    subgraph ROUTE["Routing"]
        next["/next"]
        handoff["/handoff"]
    end

    subgraph ONRAMP["On-ramps"]
        grillme["/grill-me"]
        loopme["/loop-me"]
        wayfinder["/wayfinder"]
        triage["/triage"]
        ica["/improve-codebase-architecture"]
        diag["/diagnosing-bugs"]
    end

    subgraph MAIN["Main line: idea to ship"]
        direction LR
        gwd["/grill-with-docs"] --> tospec["/to-spec"] --> totickets["/to-tickets"]
        totickets --> implement["/implement"] --> review["/code-review"] --> push["/push"]
        push --> rmc["/resolving-merge-conflicts"]
    end

    subgraph NESTED["Nested support"]
        grilling["/grilling"]
        domain["/domain-modeling"]
        design["/codebase-design"]
        tdd["/tdd"]
        research["/research"]
        prototype["/prototype"]
        questionnaire["/to-questionnaire"]
    end

    setup -.->|config| next
    setup -.->|config| triage
    setup -.->|config| review

    next --> gwd
    next --> triage
    next --> wayfinder
    next --> diag
    next --> ica
    next --> implement
    next --> handoff
    handoff --> next

    grillme --> grilling
    loopme --> grilling
    gwd --> grilling
    triage --> grilling
    wayfinder --> grilling
    ica --> grilling
    grilling --> domain
    grilling --> next

    wayfinder --> research
    wayfinder --> prototype
    wayfinder --> tospec
    triage --> implement
    ica --> design
    diag --> ica

    implement --> tdd
    implement --> design
    implement --> domain
    tdd --> design
    review --> implement
    rmc --> review

    next --> questionnaire
```

Solid arrows route or nest; dotted arrows publish or read config.

---

## 1. The main line: idea to ship

The spine of the set. Grill → spec → tickets stays in **one unbroken context**; each `/implement`
ticket starts in a **fresh one**.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant NX as /next
    participant GD as /grill-with-docs
    participant TS as /to-spec
    participant TT as /to-tickets
    participant IM as /implement
    participant CR as /code-review
    participant PU as /push

    U->>NX: a rough idea
    NX-->>U: route, runtime, paste-safe prompt

    Note over GD,TT: one unbroken context
    U->>GD: sharpen it, a round of questions at a time
    GD->>GD: post the grilled decision as a ticket comment
    GD->>TS: destination agreed
    TS->>TS: post the spec as a ticket comment
    TS->>TT: break the spec into tracer bullets
    TT->>TT: post the ticket graph as a ticket comment
    
    Note over IM,PU: fresh context per ticket
    TT->>IM: one unblocked ticket
    IM->>IM: post the implementation as a ticket comment
    IM->>CR: review this candidate head
    alt findings
        CR->>IM: address them, republish a head
    else clean
        CR->>PU: publish the reviewed head

    end

    PU-->>U: the merged head
```

A genuinely small change may skip the middle and go straight from grilling to
[`implement`](./implement.md).

## 2. Routing and session continuity

[`next`](./next.md) decides *what*; [`handoff`](./handoff.md) *launches* it.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant SK as any workflow skill
    participant NX as /next
    participant HO as /handoff
    participant BG as fresh session

    SK-->>NX: session concludes
    NX->>NX: read tracker, branch, diff, worktrees in flight
    NX-->>U: one action, HITL or AFK-safe, plus model, effort, context

    alt Continue here
        U->>SK: paste the prompt into this conversation
    else Fresh session, you drive
        U->>BG: run the copyable copilot command block
    else /implement route
        NX->>HO: run /handoff with the prompt and flags just returned
        HO->>BG: nohup copilot --yolo --no-ask-user with the same flags
        BG-->>U: resume by session name
    else Fresh session, agent drives
        U->>HO: /handoff
        HO->>NX: run /next first if it is not the last output
        HO->>BG: nohup copilot --yolo --no-ask-user with the same flags
        BG-->>U: resume by session name
    end
```

`/next` also routes to `/compact` at an intentional phase break, and to `/handoff` when the thread
must branch or survive.

## 3. The grilling family

[`grilling`](./grilling.md) is the interview engine. Four skills wrap it for different subjects; all
of them work a **design tree** in rounds until the frontier is empty.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant GM as /grill-me
    participant GD as /grill-with-docs
    participant LM as /loop-me
    participant ICA as /improve-codebase-architecture
    participant GR as /grilling
    participant DM as /domain-modeling
    participant NX as /next

    alt an idea outside a codebase
        U->>GM: sharpen it
        GM->>GR: run a grilling session
    else an idea inside a codebase
        U->>GD: sharpen it and keep docs current
        GD->>GR: run a grilling session
        GD->>DM: ADRs and glossary, inline
    else a workflow to design
        U->>LM: specify the loop
        LM->>GR: stateful grilling over workflows
    else an architecture candidate
        ICA->>GR: grill the picked candidate
    end

    loop until the frontier is empty
        GR-->>U: one round of frontier questions, each with a recommendation
        U-->>GR: decisions
        GR->>GR: recompute the design tree
    end

    GR->>NX: conclude and route onward
    GD->>GD: post the grilled decision as a ticket comment
```

`/batch-grill-me` is a standalone variant of the same discipline — it asks the whole frontier at
once instead of one question at a time, and calls nothing else. `/grill-with-docs` is the only
member that leaves a ticket comment; a grilling nested inside `/triage` or `/wayfinder` records
nothing of its own.

## 4. Wayfinder: planning beyond one context

For work too large for a single planning session. [`wayfinder`](./wayfinder.md) charts decision
tickets on the tracker and resolves them one at a time, delegating each to the right skill.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant WF as /wayfinder
    participant GR as /grilling
    participant DM as /domain-modeling
    participant RS as /research
    participant PR as /prototype
    participant TS as /to-spec

    U->>WF: a chunk bigger than one agent session
    WF->>GR: name the destination
    WF->>DM: pin the vocabulary that fixes scope
    WF->>WF: chart decision tickets on the tracker

    par AFK, in parallel subagents
        WF->>RS: a research ticket
        RS-->>WF: findings on a throwaway research branch
        RS->>RS: post the resolution as a ticket comment
    and HITL, when discussion is not enough
        WF->>PR: a prototype ticket
        PR-->>WF: a concrete artifact to react to
        PR->>PR: post the resolution as a ticket comment
    end

    loop until the frontier is empty
        WF->>GR: resolve the next decision ticket
        GR-->>WF: decision recorded on the ticket
    end

    WF->>TS: the way is clear, publish the spec
    WF->>WF: post map-complete as a ticket comment
```

Wayfinder routes to [`to-spec`](./to-spec.md), **not** straight to implementation — unless the
effort proved genuinely small.

## 5. Triage: work you did not create

The on-ramp for inbound issues and external PRs. [`triage`](./triage.md) is a state machine of
roles that ends with either an agent-ready brief or a request for missing information.

```mermaid
sequenceDiagram
    autonumber
    actor M as Maintainer
    participant TR as /triage
    participant GR as /grilling
    participant DM as /domain-modeling
    participant IM as /implement

    M->>TR: a raw issue or external PR
    TR->>TR: categorise, label, verify the reproduction
    opt the request needs fleshing out
        TR->>GR: grill it into shape, a round at a time
        TR->>DM: sharpen domain terms, update CONTEXT.md
    end

    alt agent-ready
        TR->>TR: post triage-agent-ready as a ticket comment
        TR-->>IM: implement the triaged issue
    else needs info
        TR->>TR: post triage-needs-info as a ticket comment
        TR-->>M: a brief naming exactly what is missing
    end
```

`/to-tickets` output is already agent-ready — reserve `/triage` for work that arrived raw.

## 6. Inside `/implement`

Four skills run **nested** here. They hand their evidence back to `/implement` and record nothing
of their own, so the whole ticket is one durable transition.

```mermaid
sequenceDiagram
    autonumber
    participant TT as /to-tickets
    participant IM as /implement
    participant TD as /tdd
    participant CD as /codebase-design
    participant DM as /domain-modeling
    participant PR as /prototype
    participant CR as /code-review

    TT-->>IM: one unblocked ticket, fresh context

    Note over IM,PR: nested, and recording nothing
    IM->>TD: red, green, refactor at pre-agreed seams
    TD->>CD: when the interface shape is itself in question
    IM->>CD: module, interface, depth, seam vocabulary
    IM->>DM: keep the domain model current
    IM->>PR: when a tracer bullet needs something concrete first

    IM->>IM: typecheck, targeted tests, full suite once
    IM->>IM: commit and push so the head is durable
    IM->>IM: post the implementation as a ticket comment
    IM->>CR: review this exact candidate head
```

Never review an uncommitted worktree — `/implement` pushes first so the head a reviewer reads is the
head that was built.

## 7. Review, publish, reconcile

Review is a **two-axis** check run in parallel sub-agents: Standards and Spec. Remediation returns
to review by construction.

```mermaid
sequenceDiagram
    autonumber
    participant IM as /implement
    participant CR as /code-review
    participant MS as /microsoft-docs and /microsoft-code-reference
    participant PU as /push
    participant RMC as /resolving-merge-conflicts

    IM->>CR: candidate head, fixed point at the default branch

    par Standards axis
        CR->>CR: does it follow this repo's documented standards
    and Spec axis
        CR->>CR: does it match what the issue or spec asked for
    end
    opt Microsoft APIs in the diff
        CR->>MS: verify signatures and behaviour
    end

    alt findings
        CR->>CR: post review-findings as a ticket comment
        CR->>IM: address them, republish a head
    else clean
        CR->>CR: post review-clean as a ticket comment
        CR->>PU: publish the reviewed head
    end

    PU->>PU: stage intended changes, commit, push, open the PR
    alt the remote moved
        PU->>RMC: reconcile with the remote head
        RMC->>RMC: post resolve-conflict as a ticket comment
        RMC->>CR: review the resolved head
    else clean
        PU->>PU: post publish-head as a ticket comment
    end
```

`/resolving-merge-conflicts` always routes back through `/code-review` — a resolved head is a new
candidate, not a reviewed one.

## 8. Codebase health

Two survey skills that feed the main line rather than sitting in it. Neither implements anything.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant DB as /diagnosing-bugs
    participant ICA as /improve-codebase-architecture
    participant CD as /codebase-design
    participant GR as /grilling
    participant DM as /domain-modeling
    participant NX as /next

    U->>DB: something is broken, throwing, or slow
    DB->>DB: reduce it to a tight reproducing command
    DB-->>U: cause and fix
    opt no test seam, tangled callers, hidden coupling
        DB->>ICA: hand off the structural cause
    end

    U->>ICA: survey for deepening opportunities
    ICA->>CD: depth, seam, adapter, the deletion test
    ICA-->>U: an HTML report of candidates
    U-->>ICA: pick one
    ICA->>GR: grill its decision tree
    ICA->>DM: keep the domain model current as decisions land
    ICA->>NX: the survey does not implement, so route onward
```

A candidate picked here becomes an *idea* for [`grill-with-docs`](./grill-with-docs.md).

## 9. Bootstrap

[`setup-git-loopy-skills`](./setup-git-loopy-skills.md) runs **once per repo**, before anything else. It
writes the config that four other skills read.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant SAS as /setup-git-loopy-skills
    participant DOC as docs/agents/
    participant NX as /next
    participant TR as /triage
    participant CR as /code-review
    participant DM as /domain-modeling

    U->>SAS: configure this repo once
    SAS->>DOC: issue-tracker.md
    SAS->>DOC: domain.md
    opt triage is installed
        SAS->>DOC: triage-labels.md
    end

    NX->>DOC: read the tracker config
    alt missing
        NX-->>U: /setup-git-loopy-skills is the only candidate
    else present
        TR->>DOC: label vocabulary
        CR->>DOC: tracker and standards
        DM->>DOC: domain doc layout
    end
```

## 10. Writing for agents, and the Microsoft cluster

Two small chains that sit off to the side of the engineering flow.

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant NX as /next
    participant WFA as /writing-for-agents

    NX-->>U: the task is to write or revise a skill
    U->>WFA: author or edit a skill, or modify AGENTS.md
    WFA-->>U: a document that reads predictably
```

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant AZ as /azure-mcaps-resource-deployment
    participant MF as /microsoft-foundry
    participant MD as /microsoft-docs
    participant MCR as /microsoft-code-reference

    U->>AZ: deploy into an internal MCAPS subscription
    AZ->>AZ: required tags, API-key auth defaults
    AZ->>MF: create or configure the Foundry resource
    MF->>MF: build, push, deploy, evaluate, optimize
    MD-->>MF: concepts, limits, quotas
    MCR-->>MF: real signatures and working samples
```

`/microsoft-docs` and `/microsoft-code-reference` are also pulled in by
[`code-review`](./code-review.md) whenever a diff touches Microsoft technologies.

---

## Standalone skills

These have no workflow edges. Reach for them directly; they neither route onward nor publish.

| Skill | What it stands alone for |
| --- | --- |
| `/batch-grill-me` | Grilling, whole frontier per round instead of one question at a time |
| `/codebase-audit` | Line-by-line pre-push sweep for junk, dead code, and security holes |
| `/create-readme` | Write a project README |
| `/mermaid-diagrams` | Author diagrams in Mermaid |
| `/playwright-cli` | Drive a browser for testing, screenshots, and extraction |
| [`/teach`](./teach.md) | A stateful, multi-session learning workspace |
| [`/to-questionnaire`](./to-questionnaire.md) | Turn a decision only another person can answer into a document to send |
| [`/wait-what`](./wait-what.md) | Re-pitch the last message when it did not land |
| `/wizard` | Generate a bash wizard for steps only a human can perform |

`/to-questionnaire` is the one exception: `/next` routes *to* it, and its answer comes back into
`/grill-with-docs` or `/to-spec`.

## Full edge reference

| From | To | Kind | When |
| --- | --- | --- | --- |
| `next` | 22 routes | routes to | The earliest unresolved gate decides which |
| `next` | `handoff` | runs | The chosen route is `/implement` |
| `next` | `setup-git-loopy-skills` | reads config from | `docs/agents/issue-tracker.md` is missing |
| `handoff` | `next` | routes to | Runs `/next` first if it is not the last output |
| `handoff` | fresh session | routes to | Launches the sized runtime in the background |
| `grilling` | `next` | routes to | At the conclusion of every grilling session |
| `grill-me` | `grilling` | runs inside | Always — it is a one-line wrapper |
| `loop-me` | `grilling` | runs inside | Stateful grilling over workflow specs |
| `grill-with-docs` | `grilling`, `domain-modeling` | runs inside | Always |
| `grill-with-docs` | the ticket | publishes to | On the grilled decision |
| `improve-codebase-architecture` | `codebase-design` | runs inside | For the architecture vocabulary |
| `improve-codebase-architecture` | `grilling`, `domain-modeling` | runs inside | Once a candidate is picked |
| `improve-codebase-architecture` | `next` | routes to | The survey never implements |
| `diagnosing-bugs` | `improve-codebase-architecture` | routes to | The bug exposed a structural cause |
| `wayfinder` | `grilling`, `domain-modeling` | runs inside | Naming the destination, resolving tickets |
| `wayfinder` | `research` | runs inside | A fact-shaped ticket, resolved AFK in parallel |
| `wayfinder` | `prototype` | runs inside | A ticket needing something concrete |
| `wayfinder` | `to-spec` | routes to | The frontier is empty and the way is clear |
| `triage` | `grilling`, `domain-modeling` | runs inside | The request needs fleshing out |
| `triage` | `implement` | routes to | The issue reaches agent-ready |
| `to-spec` | `to-tickets` | routes to | The spec is published |
| `to-tickets` | `implement` | routes to | One unblocked ticket, fresh context each |
| `implement` | `tdd` | runs inside | At pre-agreed seams |
| `implement` | `codebase-design`, `domain-modeling` | runs inside | Shape or vocabulary questions mid-build |
| `implement` | `prototype` | runs inside | A tracer bullet needs a concrete answer |
| `implement` | `code-review` | routes to | The candidate head is committed and pushed |
| `tdd` | `codebase-design` | runs inside | The interface shape is itself in question |
| `code-review` | `implement` | routes to | Review found defects |
| `code-review` | `push` | routes to | Review came back clean |
| `code-review` | `microsoft-docs`, `microsoft-code-reference` | runs inside | The diff touches Microsoft technologies |
| `push` | `resolving-merge-conflicts` | routes to | The remote head moved |
| `resolving-merge-conflicts` | `code-review` | routes to | A resolved head is a new candidate |
| `setup-git-loopy-skills` | `triage`, `domain-modeling` | reads config from | Writes the labels and domain layout they use |
| `azure-mcaps-resource-deployment` | `microsoft-foundry` | routes to | Creating or configuring a Foundry resource |
| eleven producers | the ticket | publishes to | On completing a transition they own |

## Rules that govern the edges

- **Context boundaries.** `/grill-with-docs` → `/to-spec` → `/to-tickets` stays in one context.
  Every `/implement` ticket starts in a fresh one.
- **Nesting owns nothing.** A skill running inside another's session hands its evidence back and
  records no transition of its own.
- **Reviews come back.** `/code-review` findings return to `/implement`, which republishes a head
  and re-enters review. `/resolving-merge-conflicts` re-enters review too.
- **Surveys do not build.** `/improve-codebase-architecture` and `/diagnosing-bugs` produce ideas
  and causes; they route onward rather than implementing.
- **Detours are bridged.** A `/prototype` or `/research` detour out of a live thread is bridged with
  `/handoff` in both directions when the original thread must survive.
- **Direct reach is narrow.** Reach for `/domain-modeling`, `/codebase-design`, or `/tdd` directly
  only when the vocabulary, module shape, or a single behaviour is itself the unresolved gate.

## See also

- [`next`](./next.md) — the router that picks the edge to walk
- [`setup-git-loopy-skills`](./setup-git-loopy-skills.md) — the config every workflow edge depends on
