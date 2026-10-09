# Captured runtime payloads

Payloads here are recorded from live runs, never written by hand. A test that builds its own
payload from the same variables it passes to the code under test is self-consistent by construction
and cannot observe a mismatch between what the runtime sends and what the code expects — which is
how the `agentName` defect in #67 survived a passing suite.

## `subagent-stop-hook-invocation.json`

One verbatim `hook.start` event for a `subagentStop` hook, copied out of a session transcript at
`~/.copilot/session-state/<session-id>/events.jsonl`. `.data.input` is the payload the runtime pipes
to `chain.sh complete` on stdin. This particular invocation is recorded in that same transcript
returning `{"reason":"unmatched-payload"}` against a live ledger, which is the defect #67 describes:
the run was launched by a custom `implement-agent`, and the runtime set `agentName` to the agent
*type*, not to the descriptive name the caller bound.

To capture another one:

```bash
python3 - <<'PY'
import glob, json, os

for path in glob.glob(os.path.expanduser("~/.copilot/session-state/*/events.jsonl")):
    with open(path, encoding="utf-8") as transcript:
        for line in transcript:
            if "subagentStop" not in line:
                continue
            event = json.loads(line)
            data = event.get("data") or {}
            if event.get("type") == "hook.start" and data.get("hookType") == "subagentStop":
                print(json.dumps(event, indent=2, ensure_ascii=False))
PY
```

Rewrite as little as possible when a test uses one. `cwd` has to become a path that exists on the
machine running the suite; every field an assertion depends on should stay exactly as captured.
