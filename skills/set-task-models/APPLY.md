# Apply one decision map

This phase changes local configuration and source files. `research-only` never
enters it. Plan all target changes before writing any of them.

## Preflight and source ownership

Read current files immediately before preparing the patch. Record hashes, file
modes, symlink targets, repository HEAD and existing diffs. Back up only intended
files into the private run directory with their permissions preserved. Keep
credentials and unrelated settings out of research reports and diffs shown to
external services.

Discover source ownership from the current clone rather than assuming one TOML
edit updates the product. These are starting pointers, not a frozen schema:

| Surface | Inspect |
| --- | --- |
| Recommended routing | `git-loopy/python/git_loopy/config.py`: `RECOMMENDED_ROUTING`, taxonomy, roster and effort/context gates |
| Bundled defaults | `git-loopy/config.toml`; compare its routes with the canonical table |
| Unlabeled-run defaults | `git-loopy/python/git_loopy/cli.py`: `_DEFAULT_MODEL`, `_DEFAULT_REASONING_EFFORT`, escalation policy |
| Persistence/precedence | `configcmd.py`, configuration readers, `measured_routing.py`, routing scope |
| Runtime consumption | Trace resolved model, effort, and context into session creation/resume, not just logs or pickup events |
| Contracts and tests | Active ADRs, `AGENTS.md`, conformance fixtures, routing/default assertions |

Read the active successors of ADRs 0027, 0028, 0035, 0037, and 0048. In the
September 2026 design, routed defaults reserve higher effort for escalation and
write-capable review has task-cheating safeguards. Re-check these constraints
before selecting a common review profile; a good read-only benchmark does not
override a write-capable runner's safety restriction.

Public leaderboard research is not local calibration. Leave
`routing.measured.toml`, measured-run statuses, and calibration provenance intact;
do not label recommendations "measured" without running the defined local
experiment. Read precedence from the implementation: global, project, environment,
CLI and measured layers can make a file edit ineffective.

**Preflight passes:** every intended field has a real reader and consumer, all
selected triples are supported, common profiles satisfy both systems, and no
architectural or concurrent-edit conflict remains.

## Context capability gate

Establish the actual context path per task, including the SDK/CLI session request.
Do not infer support from a dataclass field or an event reporting a tier.

At authoring time, git-loopy routed model/effort pairs, kept an internal run-level
`context_tier`, and had no operator-facing or per-task context setting. Treat
that as a discovery lead, not a permanent fact.

If every requested task uses `default` and the actual session path demonstrably
uses that tier, record its effective implicit default without inventing TOML keys.
If any requested context cannot be expressed, or inherited CLI settings prevent
proving equality, stop before changing any target. Explain the missing reader or
runtime path and ask for approval of the smallest complete runtime change.

With that approval, implement and test parsing, validation, precedence, per-task
resolution if required, session creation/resume, diagnostics, and relevant
fixtures/documentation. Honor the user's shared-triple requirement rather than
silently substituting a run-wide tier. A deliberately non-routing shell or
PowerShell port stays out of scope unless explicitly included.

## Apply the projections

Resolve each role through its profile; project from that one source, never
recompute model choices while editing.

### Copilot built-ins

Use the installed CLI's documented settings interface or a surgical JSONC-aware
edit of its actual user settings file. Preserve comments, symlinks, file modes,
custom agents, enabled status, and unrelated keys. Verify the current schema;
modern releases use `settings.json`, not the internal-state `config.json`.

For every inventoried built-in, set:

| Setting | Value |
| --- | --- |
| `subagents.agents.<name>.model` | Profile's exact selectable model ID |
| `subagents.agents.<name>.effortLevel` | Profile effort; for null, remove a stale effort override and verify the model has no effort control |
| `subagents.agents.<name>.contextTier` | Profile's concrete context tier |
| `subagents.agents.<name>.modelPolicy` | `"required"` |

Required model enforcement means the subagent cannot substitute another model;
it is not a permission escalation or a guarantee that effort/context cannot be
overridden by another supported mechanism. Leave the main model, permissions,
custom agents, concurrency/depth, and account settings unchanged. A fixed
rubber-duck model stops adapting automatically when the parent changes: disclose
that trade-off and recalibrate after a parent-family switch.

### git-loopy global and source defaults

Update all seven global routing entries using the supported model/effort/context
representation. Preserve unrelated configuration, enabled skills, project
overrides, and formatting. Apply exactly the same role map to the canonical
recommended defaults and their bundled mirror in the clone.

Inspect the global and source unlabeled-run fallbacks: align their model/effort
with the selected implementation profile where the active contract defines
implementation as that fallback. Otherwise preserve and report the distinct
fallback policy. Preserve escalation intent rather than copying a routed default
over the escalation rung.

Update directly affected current assertions and documentation. Historical ADR
decisions stay historical; explain a changed design through the repository's
decision process rather than rewriting history. Extend a stale roster only from
current Copilot capability evidence, keeping its conformance mirrors consistent.

If the installed git-loopy resolves to a different checkout or built artifact,
report that distinction. Update/install it only with explicit authorization; a
source edit alone does not prove that the installed binary uses the new defaults.

## Persistence gate

Recheck hashes immediately before each write and stop on conflicting concurrent
changes. Prefer the target's atomic writer; otherwise stage and validate a
same-directory replacement before atomic rename, preserving permissions and
symlink semantics. Never replace whole settings files from a partial projection.

After applying:

1. Parse every changed config through its real reader, then read back all
   built-in triples plus required enforcement and all seven git-loopy routes.
2. Test each task-type resolution under an isolated home/environment with no
   project overrides. Verify the actual session request receives its triple;
   separately report overrides affecting normal invocation.
3. Run the smallest existing checks covering changed sources, defaults, and
   mirrors, and required repository feedback loops. Use mocks/fixtures for
   routing checks and frozen dependency resolution (for example `uv run --frozen`)
   to avoid incidental lockfile changes. Billable benchmark runs require separate
   authorization.
4. Compare effective triples across every equivalence group and verify unrelated
   settings are unchanged. Re-run the projection comparison: it must be a no-op.

If a later write or check fails, report the failure and restore only this run's
changes when the current content still matches what this run wrote. A newer
concurrent edit blocks automatic restoration. Describe any partial state
explicitly; never claim success because one target was updated.

Save the final diff, effective-value readback, source citations, and result in the
run directory. Report completion only after all authorized targets pass. Do not
commit, push, publish private settings, restart services, or interrupt running
git-loopy jobs as part of calibration.
