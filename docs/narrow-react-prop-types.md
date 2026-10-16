Quickstart:

```bash
npx skills add bradcstevens/git-loopy-skills --skill=narrow-react-prop-types
```

```bash
npx skills update narrow-react-prop-types
```

[Source](https://github.com/bradcstevens/git-loopy-skills/tree/main/skills/narrow-react-prop-types)

## What it does

`narrow-react-prop-types` tightens a React component's prop types so they describe only what the live application does. Props often get widened for stories, mocks, tests or demos until the type allows states that never happen. This skill treats live code paths as the source of truth and makes tests and stories adapt to that contract, not the other way round.

It works through these steps:

1. Spot a suspect component: many optional props, `onSelect?.(...)` calls, `items ?? []` fallbacks, or demo-oriented props.
2. Find every live call site, separating app code from stories, tests, fixtures and mocks.
3. Classify each prop as required, optional or removed. Where a value can be empty but is always passed, prefer a required nullable prop over an optional one.
4. Tighten the public type and the internal child props, and derive types from live APIs where possible (`Parameters`, `ReturnType`, `Extract`, `React.Dispatch<React.SetStateAction<T>>`, explicit `useState<T>`).
5. Remove the fallback logic the widened types required.
6. Update every component that shares the type, fix stories and tests with realistic handlers, and run package-level typechecks for the changed package and its live consumers.

## When to reach for it

`narrow-react-prop-types` is a standalone tool. It is **not on the idea → ship flow**: nothing in that chain calls it. Use it when a component's props have drifted toward test and demo convenience, or run it as a recurring job. The skill ships an example GitHub Actions workflow, agent memory file and response template under `references/` for the CI case.

## Common questions

**Will it make a prop optional so a story compiles?** No. That is an anti-pattern the skill names. Add a helper or fixture in support code instead.

**When does a prop stay optional?** Only when a live call site omits it for a good reason.

**What is validated?** Typechecks for the changed package and every live app or package that consumes it, using the repository's own commands when available.

## It's working if

- Every remaining optional prop is omitted by at least one live call site.
- No rendered button or menu item can be inert because a handler is missing.
- Fallbacks such as `?? []` and `handler &&` are gone, and stories and tests pass the strict contract.
- Typechecks pass for the shared package and its consumers.
