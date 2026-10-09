---
name: jev-ultrafast
description: "Run fast goal-driven browser automation with Jev Ultrafast for navigating, searching, and interacting with visible web pages. Use when a user requests fast browser automation or explicitly asks to use Jev."
---

# Jev Ultrafast

Use Jev's indexed browser actions for short, goal-driven tasks. Each run opens a tab in the selected Chromium browser through Browser Harness and makes bounded decisions against the live page.

Jev sends visible page text and the task goal to TypeSafe; text entry also sends field context to the configured text-model provider. Run it only on public, non-sensitive pages. Do not use it on pages showing credentials, personal data, private work content, or other sensitive information.

## Prepare

1. Resolve `JEV_ULTRAFAST_HOME` to an absolute checkout path. Honor an existing setting; otherwise look for an existing `jev-ultrafast` checkout under `~/code/github/` before using `~/.local/share/jev-ultrafast`. Accept forks containing the upstream `jev_ultrafast.Agent` API. Reuse that checkout and its virtual environment.
2. Run commands from the checkout through `zsh -c` so `~/.zshenv` is loaded. Confirm `uv run --no-sync python -c 'from jev_ultrafast import Agent'` succeeds. For a missing checkout, runtime, Edge installation, or explicitly configured browser connection, read [Setup](references/setup.md) and resolve the reported gap.
3. Require `TYPESAFE_API_KEY` for decisions; when only `TYPESAFEAI_API_KEY` is configured, map it to `TYPESAFE_API_KEY` in the Jev subprocess without printing or persisting it. Tasks involving text entry also require `TEXT_MODEL_API_KEY` and a matching provider endpoint/model. Load a user-configured `.env` only through `uv run --env-file .env`.
4. `BROWSER_USE_API_KEY` authenticates Browser Use Cloud, not Jev's TypeSafe or text-model calls. Keep it scoped to Browser Use; never alias it into either Jev credential. Missing provider credentials block live automation.

## Run

1. Turn the request into one concrete goal with an observable stopping condition. Keep the run focused; do not ask Jev to explore unrelated pages.
2. Preserve user intent and authorization boundaries. Do not submit, purchase, send, delete, or persistently change account data unless the user explicitly requested that action. Otherwise stop before the consequential action and report what is ready.
3. Invoke the bundled `scripts/run_jev.py` from the Jev checkout's environment. By default it starts headless Edge with a fresh, disposable profile and local CDP endpoint, then stops the browser and Browser Harness daemon and removes the profile. An explicitly configured localhost `BU_CDP_URL` is honored instead. The isolated default profile has no sign-in state; use only public pages.
4. Run the helper through the installed project, for example:

   ```bash
   zsh -c 'if [[ -f "$1/.env" ]]; then exec uv run --project "$1" --no-sync --env-file "$1/.env" python "$2" "$3" "$4" "${@:5}"; fi; exec uv run --project "$1" --no-sync python "$2" "$3" "$4" "${@:5}"' jev "$JEV_ULTRAFAST_HOME" "$SKILL_DIR/scripts/run_jev.py" "$URL" "$GOAL" $HEADLESS_FLAG
   ```

   Headless is the default. Pass `--no-headless` as `HEADLESS_FLAG` (or `--headless` explicitly) when the user asks to watch the browser or a headless page misbehaves; it only applies to the Edge the helper launches, not to an explicit `BU_CDP_URL`.

   Set `SKILL_DIR` to the directory containing this skill's `SKILL.md`. The helper accepts the target URL and one concrete goal as its positional arguments and maps `TYPESAFEAI_API_KEY` to `TYPESAFE_API_KEY` in its child process without printing or persisting the value.
5. Verify every requested condition from the helper's fresh observation of visible page text and URL. A `done` status alone is not proof of success. Treat `blocked`, an exception, or missing visible evidence as an incomplete run.
6. Report the observed outcome or exact blocker. Keep credentials and raw traces out of output.

## Limits

Jev operates on visible DOM controls in its owned Edge tab. It does not cover frames, canvas, uploads, pop-up tabs, or arbitrary keyboard widgets. Use another approach only when the requested interaction falls outside these limits.

Upstream project and API: <https://github.com/browser-use/jev-ultrafast>
