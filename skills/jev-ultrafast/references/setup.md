# Setup

Resolve only the missing prerequisites; preserve existing checkouts, environments, and credentials.

## Runtime

Jev requires Python 3.12+, `uv`, Microsoft Edge, and the dependencies declared in the checkout's `pyproject.toml`.

For a new checkout:

```bash
git clone https://github.com/browser-use/jev-ultrafast.git "$JEV_ULTRAFAST_HOME"
```

Use the machine's configured package feed. When the upstream lock names public registries but the machine requires a corporate feed, export the pins locally rather than rewriting the lock or using public downloads:

```bash
# Create the environment only if .venv is absent.
uv venv --python 3.12 "$JEV_ULTRAFAST_HOME/.venv"
REQ="$(mktemp)"
uv export --project "$JEV_ULTRAFAST_HOME" --frozen --no-default-groups \
  --no-emit-project --format requirements-txt -o "$REQ"
```

Inspect the export for direct URLs and feed overrides before installation. Keep the locked versions and hashes; report inaccessible pins instead of silently replacing them.

```bash
uv pip install --python "$JEV_ULTRAFAST_HOME/.venv/bin/python" --require-hashes -r "$REQ"
uv pip install --python "$JEV_ULTRAFAST_HOME/.venv/bin/python" \
  --no-deps --editable "$JEV_ULTRAFAST_HOME"
rm "$REQ"
```

Build dependencies also use the configured feed. Run from the checkout with `uv run --no-sync` thereafter so validation cannot resync public-source dependencies.

## Credentials

`TYPESAFE_API_KEY` comes from [TypeSafe's dashboard](https://console.typesafe.ai/keys). If the existing zsh environment exposes the same credential as `TYPESAFEAI_API_KEY`, map it in the command's zsh process with `export TYPESAFE_API_KEY="${TYPESAFE_API_KEY:-${TYPESAFEAI_API_KEY:-}}"`; do not print it or copy it into `.env`. Jev sends decisions to `https://api.typesafe.ai/v1/systemone`.

Text entry uses an OpenAI-compatible provider. Configure `TEXT_MODEL_API_KEY`, `TEXT_MODEL_BASE_URL`, and `TEXT_MODEL` together; the key must belong to that endpoint. Read the checkout's `.env.example` for its example configuration: it uses OpenRouter, while the library's unset defaults use DeepSeek. Set `TEXT_MODEL_REASONING` as appropriate for the selected model.

Use existing environment exports or a user-configured, ignored `.env`; pass the latter with `uv run --no-sync --env-file .env`. Ask the user to configure missing keys locally without posting their values in chat.

## Local browser

The bundled `scripts/run_jev.py` helper launches headless Edge by default (`--no-headless` shows the window) with a unique temporary profile and local debugging port when `BU_CDP_URL` is unset. It shuts down its Browser Harness daemon and Edge process and removes the profile after the run. The temporary profile is not signed in to user accounts.

To use a separately launched local Chromium browser instead, set `BU_CDP_URL` to its localhost DevTools endpoint before invoking the helper. Use a dedicated profile, never your normal browser profile. Do not expose the debugging port beyond localhost.

If an explicitly configured endpoint fails, run the Browser Harness diagnostics from the Jev checkout:

```bash
uv run --no-sync browser-harness --doctor
```

Microsoft's [Edge DevTools Protocol documentation](https://learn.microsoft.com/microsoft-edge/devtools/protocol/) covers the local debugging endpoint and dedicated browser profiles.
```bash
export BU_CDP_URL=http://127.0.0.1:9222
export TYPESAFE_API_KEY="${TYPESAFE_API_KEY:-${TYPESAFEAI_API_KEY:-}}"
```

Run the Jev script from the checkout with `uv run --no-sync` (and `--env-file .env` if text-entry settings are configured). Leave Edge running while Jev is using it. Use a dedicated profile for automation; it does not share sign-in state with the user's normal Edge profile.

Microsoft's [Edge DevTools Protocol documentation](https://learn.microsoft.com/microsoft-edge/devtools/protocol/) documents launching Edge with a debugging port and separate user-data directory.
