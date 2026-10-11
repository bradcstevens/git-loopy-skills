# Copilot CLI Runner

The loop runs the GitHub Copilot CLI (`copilot`) headless with `-p`. `references/workflow-template.yml` carries the working steps; this file holds what the template cannot say inline: authentication and billing, the flag choices, and troubleshooting.

## Authenticate

Settle one option with the user in setup step 2:

- **`GITHUB_TOKEN` (recommended; the template ships it).** The `copilot-requests: write` permission lets the workflow's built-in token authenticate the CLI, so no secret is stored. Declaring `permissions:` sets every unlisted scope to `none`, so that line must stay. Billing follows the repo owner:
  - Organization-owned repo: usage bills to the organization, which needs the policy **Allow use of Copilot CLI billed to the organization** (on by default where Copilot CLI is enabled). User-level Copilot budgets do not apply, so recommend `--max-ai-credits`.
  - Personal repo: usage bills to the owner's Copilot seat.
- **Personal access token.** For an organization whose policy is off, or to bill one user's seat: a fine-grained PAT with the **Copilot Requests** permission, stored as the repo secret `COPILOT_GITHUB_TOKEN` and added to the run step's `env:` as `COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_GITHUB_TOKEN }}`. The CLI prefers it over `GITHUB_TOKEN`, which stays for `gh`.

The CLI redacts the `GITHUB_TOKEN` and `COPILOT_GITHUB_TOKEN` values from its output by default; name any other secret the agent must not see in `--secret-env-vars=NAME,...`.

## Flags

The run step keeps one `COPILOT_FLAGS` array for both the scheduled and `/iterate` paths:

- `--model "<model>"`: pin a model ID from `/model` in an interactive `copilot` session, so every scheduled run uses the same model.
- `--allow-all`: a headless run denies any action that is not pre-approved, so an unattended coding run needs every tool, path, and URL permission. It suits only trusted, isolated runners such as GitHub-hosted ones.
- `--output-format json` and `--share /tmp/agent-session.md`: the PR body (or `/iterate` reply) is the agent's final message, and `-s`/`--silent` would print every assistant message, mid-run narration included. So the `Extract PR body` step reads the JSONL and keeps the last `assistant.message` event with non-empty `.data.content`; the shared transcript is the readable copy in the `agent-output` artifact.
- Optional `--max-ai-credits <n>` (minimum 30): a soft per-run spend cap; the run ends once it is reached.

## Troubleshooting

- Copilot step fails to authenticate: confirm `copilot-requests: write` in `permissions:`, then the organization policy above — or switch to the PAT.
- Pinned model rejected: the billing account's plan or policy does not enable it; pick another from `/model`.
- Empty or unexpected PR body: read `/tmp/agent-session.md` in the `agent-output` artifact.
