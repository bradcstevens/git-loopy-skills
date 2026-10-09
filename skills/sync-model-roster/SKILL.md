---
name: sync-model-roster
description: Reconcile git-loopy's pinned model roster and one config.toml scope with authenticated harness evidence.
disable-model-invocation: true
---

# Sync model roster

Repair roster drift first, then configure against the repaired roster. An
ordinary invocation authorizes the requested edits, but not an SDK upgrade, a
different Config scope, or removal of compatibility rows.

## 1. Resolve the two targets

Find the git-loopy source checkout containing:

- `git-loopy/conformance/model-roster.json`
- `git-loopy/python/git_loopy/config.py`
- `git-loopy/python/tests/test_conformance.py`
- `docs/adr/0019-roster-derived-from-the-pinned-harness.md`

Resolve exactly one Config scope:

- project: `<repo>/git-loopy/config.toml`
- global: `$XDG_CONFIG_HOME/git-loopy/config.toml`, falling back to
  `~/.config/git-loopy/config.toml`

Use project scope for one repository and global scope for machine defaults. If
the request could mean either, ask before writing. Inspect both worktrees and
preserve unrelated edits.

**Done:** one source checkout and one Config file are named, and every existing
change in files this run may touch is accounted for.

## 2. Capture the pinned harness

The SDK-pinned Copilot CLI's authenticated `models.list()` result is the roster
authority. A PATH-installed CLI, public model list, provider documentation, or
the user's Config is not equivalent evidence.

Use the source checkout's existing environment without syncing dependencies.
The following probe records the CLI stamp and the capability fields git-loopy
reads:

```bash
uv run --project git-loopy/python --no-sync python - <<'PY'
import asyncio
import json

from copilot._cli_version import CLI_VERSION
from git_loopy.model_listing import fetch_live_models
from git_loopy.static_route import HarnessModel


async def main():
    rows = sorted(
        (HarnessModel.from_model_info(item) for item in await fetch_live_models()),
        key=lambda row: row.model,
    )
    print(json.dumps({
        "cli_version": CLI_VERSION,
        "models": [
            {
                "id": row.model,
                "eligible": row.eligible,
                "effort_configurable": row.effort_configurable,
                "efforts": sorted(row.efforts),
                "context_tiers": sorted(row.context_tiers),
            }
            for row in rows
        ],
    }, indent=2))


asyncio.run(main())
PY
```

If the environment is absent, inspect `uv.lock` before any locked or frozen
operation and follow the machine's configured package-feed policy. If the
pinned environment or authenticated listing cannot be obtained, report the
blocker; do not infer missing capabilities.

Compare the capture with the fixture and ADR-0019. Separate:

- **observed rows**: returned by the pinned harness; replace their effort sets
  with the capture
- **compatibility rows**: deliberately retained for saved Config despite being
  absent from this account; preserve them unless the user explicitly changes
  that policy
- **context tiers**: write only tiers evidenced by this capture
- **SDK drift**: a different `CLI_VERSION` means the pin and roster stamp must
  move together; do not upgrade the SDK unless the request authorizes it

**Done:** every fixture row is classified as observed, preserved compatibility,
added, changed, or removed, with the CLI version and capture source recorded.

## 3. Update the roster in lockstep

Patch the narrowest complete set:

1. Update `model-roster.json`:
   - keep `schema_version` unless the JSON shape changes
   - keep `contract_version` unless the Wrapper contract changes
   - set `cli_version` to the pinned harness version
   - update `roster` and evidenced `context_tiers`
2. Apply the same effort map to `MODEL_REASONING_EFFORTS` in `config.py`.
3. Apply the same CLI stamp to `MODEL_ROSTER_CLI_VERSION`.
4. Apply the same tier map to `MODEL_CONTEXT_TIERS`.
5. Add or amend the ADR-0019 upgrade record when the committed fallback's
   provenance changes. Name retained compatibility rows and distinguish backend
   catalogue drift from an SDK/CLI pin change.
6. Update directly coupled defaults or tests only when the requested routing
   decision changes them; a roster refresh alone does not retune routes.

Preserve the fixture's established model ordering and the effort vocabulary in
`REASONING_EFFORT_ORDER`. Do not add an effort merely because the harness would
forward it; the capture must advertise it.

Run the focused proof:

```bash
uv run --project git-loopy/python --all-extras python -m pytest -q \
  git-loopy/python/tests/test_conformance.py
uv run --project git-loopy/python --all-extras ruff check \
  git-loopy/python/git_loopy/config.py \
  git-loopy/python/tests/test_conformance.py
```

Use the repository's broader Python feedback loop when another changed surface
requires it.

**Done:** the fixture, Python maps, CLI stamp, provenance, and focused checks
agree exactly.

## 4. Configure one scope

Read the selected file and the effective merged values:

```bash
git-loopy config path --project
git-loopy config list
```

Use `--global` instead of `--project` for global scope. Patch only the requested
default or task routes. Prefer the typed merge commands:

```bash
git-loopy config set --project model MODEL
git-loopy config set --project reasoning_effort EFFORT
git-loopy config set --project context_tier TIER
git-loopy config routing set --project TYPE MODEL EFFORT
```

The routing taxonomy is `planning`, `review`, `implementation`, `test`, `docs`,
`chore`, and `bugfix`. Use the updated roster for model/effort validation.
Preserve unrelated keys and routes. If the installed command predates the
repaired source roster and rejects a newly added row, edit the chosen TOML file
surgically rather than changing another scope or downgrading the requested
model.

Read back the chosen file and effective values. Account for environment
overrides when the effective value differs from the persisted value.

**Done:** every changed model/effort/tier is supported by the repaired roster,
the intended scope contains the exact requested values, unrelated Config is
unchanged, and the effective readback is explained.

## Completion

Report the roster capture's CLI version, roster files changed, Config scope and
path, final default and routes, preserved compatibility rows, and validation
results. Name any blocked or intentionally unapplied change.
