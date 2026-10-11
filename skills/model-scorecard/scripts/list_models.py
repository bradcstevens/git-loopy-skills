#!/usr/bin/env python3
"""List the models one Copilot harness offers this account.

``copilot-cli`` asks the installed ``copilot`` (what built-in subagents run on);
``sdk`` asks the CLI the Copilot SDK pins (what git-loopy Runs on). Run it in an
environment that has the ``copilot`` SDK, such as a git-loopy checkout's.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def _prompt_cap(block) -> int | None:
    value = getattr(block, "max_prompt_tokens", None) if block is not None else None
    return value if isinstance(value, int) and not isinstance(value, bool) and value > 0 else None


def describe(model) -> dict:
    """The capability facts the scorecard reads from one listing entry."""
    prices = getattr(getattr(model, "billing", None), "token_prices", None)
    limits = getattr(getattr(model, "capabilities", None), "limits", None)
    default_cap = _prompt_cap(prices) or _prompt_cap(limits)
    long_cap = _prompt_cap(getattr(prices, "long_context", None)) if prices is not None else None
    return {
        "id": model.id,
        "name": getattr(model, "name", None),
        "efforts": list(getattr(model, "supported_reasoning_efforts", None) or []),
        "default_cap": default_cap,
        "long_cap": long_cap,
        "policy": getattr(getattr(model, "policy", None), "state", None),
    }


async def _list() -> list:
    from copilot import CopilotClient

    async with CopilotClient() as client:
        return await client.list_models()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", required=True, choices=["copilot-cli", "sdk"])
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    if args.harness == "copilot-cli":
        cli = shutil.which("copilot")
        if not cli:
            raise SystemExit("copilot is not on PATH")
        os.environ["COPILOT_CLI_PATH"] = cli
        banner = subprocess.run([cli, "--version"], capture_output=True, text=True).stdout
        found = re.search(r"\d+\.\d+\.\d+(?:-\d+)?", banner)
        version = found.group(0) if found else banner.strip()
    else:
        os.environ.pop("COPILOT_CLI_PATH", None)
        from copilot._cli_version import CLI_VERSION

        version = CLI_VERSION

    seen, models = set(), []
    for model in asyncio.run(_list()):
        if model.id in seen or model.id == "auto":
            continue
        seen.add(model.id)
        models.append(describe(model))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(
            {
                "harness": args.harness,
                "cli_version": version,
                "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "models": sorted(models, key=lambda row: row["id"]),
            },
            indent=1,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"harness": args.harness, "cli_version": version, "models": len(models)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
