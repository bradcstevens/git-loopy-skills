Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=show-me
```

```bash
npx skills update show-me
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/show-me)

## What it does

`show-me` explains the current topic visually. It skips the preamble, keeps the prose short and picks the smallest view that makes the point: pseudocode for logic, a call tree for runtime flow, a component tree for UI structure, a shallow file tree for file responsibility, or a Mermaid diagram for interaction and data flow.

When the change is the point and the shape already exists, it uses a `diff`-style view. When most of a block is new, it shows the whole block. For a visual that is too dense for Mermaid, it writes one focused HTML file (a diagram, infographic or short slide deck) in the product's own look and opens it for you.

## When to reach for it

`show-me` is a standalone tool. It is **not on the idea → ship flow**: nothing hands off to it and it hands off to nothing. Use it any time in any session when words are not landing and a picture would be quicker.

Reach for it when you are lost in a control flow, a refactor's blast radius, a component hierarchy or a data flow, or when you need to compare options on screen.

## Common questions

**Will it use every kind of view?** No. It uses one or a few and avoids overwhelming you. Each visual sits next to the short text it supports.

**Does it change any files?** Only the HTML artifact, and only when the topic needs one. It is written as `show-me-{description}.html` and opened with `open`.

**How is it different from [wait-what](./wait-what.md)?** `wait-what` re-pitches a message in plain words. `show-me` draws the topic.

## It's working if

- The answer is mostly a diagram, tree or diff, with only a few lines of prose.
- Each visual contains only the calls, files, props, states and boundaries that matter to your question.
- Any HTML artifact opens on its own, uses real labels and data, and reads on desktop and mobile.
