# Actuator Runner — GitHub Copilot CLI

The actuator is the GitHub Copilot CLI (`copilot`) run headless with `-p`. The same command runs locally and in CI; only the credentials and the permission flags differ. `--allow-all` / `--yolo` is appropriate only on trusted, isolated runners.

Goal: the agent's final formatted response lands in `/tmp/pr-body.md` for the PR body. `--silent` prints only that response, so extraction is a redirect.

## Run it locally first

Run the actuator by hand against a controller-selected target before it goes into a workflow. Source `git-loopy.env` (repo root of git-loopy-skills) to inherit the pinned `GIT_LOOPY_MODEL`, `GIT_LOOPY_EFFORT`, and `GIT_LOOPY_CONTEXT`; local runs use your signed-in `copilot` session, so no secret is needed.

```bash
source git-loopy.env
PROMPT="$(cat /tmp/agent-prompt.md)"   # your assembled actuator prompt
copilot -p "$PROMPT" \
  --model "$GIT_LOOPY_MODEL" \
  --reasoning-effort "$GIT_LOOPY_EFFORT" \
  --context "$GIT_LOOPY_CONTEXT" \
  --allow-all --no-ask-user --no-color --silent \
  > /tmp/pr-body.md
```

Flags outrank every other layer (`.github/copilot/settings.json`, `~/.copilot/settings.json`), so pin model, effort, and context here when the loop needs a stable actuator.

## In CI

Secret: `COPILOT_GITHUB_TOKEN` — a fine-grained personal access token with the **Copilot Requests** permission, stored as a repo secret. `GITHUB_TOKEN` cannot authenticate Copilot; keep it for `gh` and PR creation.

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 24
- run: npm install -g @github/copilot
- name: Run Copilot CLI
  env:
    COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_GITHUB_TOKEN }}
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set -o pipefail
    copilot -p "$PROMPT" \
      --model "<model>" \
      --reasoning-effort high \
      --allow-all --no-ask-user --no-color --silent \
      > /tmp/pr-body.md
```

Pick `<model>` from the models the Copilot CLI lists (`copilot --help`, `/model`). Add `--max-autopilot-continues <n>` when the repo needs a spend guard. Use `--output-format json` plus `--share /tmp/session.md` when the run needs a debug transcript; then take the final message from the JSONL instead of redirecting stdout.

## Response extraction

With `--silent`, stdout is the final response and needs no parsing. Fall back to a placeholder body when the file is empty:

```yaml
- name: Extract PR body
  run: |
    [ -s /tmp/pr-body.md ] || echo "Agent produced no final message; see the workflow run." > /tmp/pr-body.md
```

## Notes

- Upload `/tmp/pr-body.md` (and any `--share` transcript) as an artifact for debugging.
- The PR creation step reads `/tmp/pr-body.md`.
- `COPILOT_GITHUB_TOKEN` outranks `GH_TOKEN`, so the CLI authenticates with the former while `gh` uses the latter. Keep secrets out of the prompt; `--secret-env-vars=<NAME>,...` strips and redacts any variable the agent must not see.
