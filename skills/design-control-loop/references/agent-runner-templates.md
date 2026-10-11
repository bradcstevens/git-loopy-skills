# Actuator Runner — GitHub Copilot CLI

The actuator is the GitHub Copilot CLI (`copilot`) run headless with `-p`. The same command runs locally and in CI; only authentication differs. `references/workflow-template.yml` carries the CI steps; this file holds what the template cannot say inline.

## Run it locally first

Run the actuator by hand against a controller-selected target before it goes into a workflow. Source `git-loopy.env` (repo root of git-loopy-skills) to inherit the pinned `GIT_LOOPY_MODEL`, `GIT_LOOPY_EFFORT`, and `GIT_LOOPY_CONTEXT`; local runs use your signed-in `copilot` session, so no secret is needed.

```bash
source git-loopy.env
copilot -p "$(cat /tmp/agent-prompt.md)" \
  --model "$GIT_LOOPY_MODEL" \
  --reasoning-effort "$GIT_LOOPY_EFFORT" \
  --context "$GIT_LOOPY_CONTEXT" \
  --allow-all --no-ask-user --no-color \
  --output-format json --share /tmp/agent-session.md \
  > /tmp/agent-output.jsonl
grep '^{' /tmp/agent-output.jsonl \
  | jq -rs '[.[] | select(.type == "assistant.message" and (.data.content // "") != "")] | last | .data.content // empty' \
  > /tmp/pr-body.md
```

`/tmp/agent-prompt.md` is your assembled actuator prompt. Afterwards `/tmp/pr-body.md` holds the PR body CI would open, and `/tmp/agent-session.md` the readable transcript.

Flags outrank every other layer (`.github/copilot/settings.json`, `~/.copilot/settings.json`), so pin model, effort, and context here when the loop needs a stable actuator.

## Authenticate in CI

Settle one option with the user in Phase B:

- **`GITHUB_TOKEN` (recommended; the template ships it).** The `copilot-requests: write` permission lets the workflow's built-in token authenticate the CLI, so no secret is stored. Declaring `permissions:` sets every unlisted scope to `none`, so that line must stay. Billing follows the repo owner:
  - Organization-owned repo: usage bills to the organization, which needs the policy **Allow use of Copilot CLI billed to the organization** (on by default where Copilot CLI is enabled). User-level Copilot budgets do not apply, so recommend `--max-ai-credits`.
  - Personal repo: usage bills to the owner's Copilot seat.
- **Personal access token.** For an organization whose policy is off, or to bill one user's seat: a fine-grained PAT with the **Copilot Requests** permission, stored as the repo secret `COPILOT_GITHUB_TOKEN` and added to each actuator step's `env:` as `COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_GITHUB_TOKEN }}`. The CLI prefers it over `GITHUB_TOKEN`, which stays for `gh`.

The CLI redacts the `GITHUB_TOKEN` and `COPILOT_GITHUB_TOKEN` values from its output by default; name any other secret the agent must not see in `--secret-env-vars=NAME,...`.

## Flags

The template keeps one job-level `COPILOT_FLAGS` string for both actuator steps (the scheduled run and `/iterate`), split into an array with `read -ra`, so flag values must not contain spaces:

- `--model <model>`: pin the model settled in Phase B, so every scheduled run uses the same one. Add `--context <tier>` when Phase B chose a non-default context tier.
- `--allow-all`: a headless run denies any action that is not pre-approved, so an unattended coding run needs every tool, path, and URL permission. It suits only trusted, isolated runners such as GitHub-hosted ones.
- `--output-format json` and `--share /tmp/agent-session.md`: the PR body (or `/iterate` reply) is the agent's final message, and `-s`/`--silent` would print every assistant message, mid-run narration included. So the `Extract PR body` step reads the JSONL and keeps the last `assistant.message` event with non-empty `.data.content`; the shared transcript is the readable copy in the `agent-output` artifact.
- Optional `--max-ai-credits <n>` (minimum 30): a soft per-run spend cap; the run ends once it is reached.

## Troubleshooting

- Copilot step fails to authenticate: confirm `copilot-requests: write` in `permissions:`, then the organization policy above — or switch to the PAT.
- Pinned model rejected: the billing account's plan or policy does not enable it; pick another from `/model`.
- Empty or unexpected PR body: read `/tmp/agent-session.md` in the `agent-output` artifact.
