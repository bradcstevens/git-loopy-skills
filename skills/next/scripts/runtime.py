#!/usr/bin/env python3
"""Name the runtime a /next route runs on, read from the routed skill's SKILL.md header.

    runtime.py ROUTE [--skills-dir DIR] [--catalog PATH]

ROUTE is a skill name, with or without its leading slash. Every skill's header
names the GitHub Copilot ``model``, reasoning ``effort`` and ``context`` window
to choose in ``/model`` before running it. The header is read from
``<skills-dir>/<name>/SKILL.md``; ``--skills-dir`` defaults to the directory
that holds this skill, where its sibling skills are installed.

Copilot CLI's ``--context`` flag and a subagent's ``context_tier`` take a tier,
``default`` or ``long_context``, not a window. The window is ``long_context``
when it is larger than the model's default window in the catalog
``/model-scorecard`` writes (``--catalog``, default
``<skills-dir>/model-scorecard/references/skill-headers.json``). Without the
catalog, or a model it does not list, the tier falls back to ``default``, the
tier every model offers.

Prints one JSON object. ``runtime`` is the recommendation's Runtime line: the
header's values, or ``current session`` when the route names none: a built-in
such as ``/compact`` (``reason: no-skill``) or a skill without a header
(``reason: no-header``). Exits 0 for both, 1 for a header that is partial or
malformed (``reason: invalid-header``), and 2 for a route that is not a skill
name.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Dict, Optional, Tuple

ROUTE = re.compile(r"^/?([a-z0-9][a-z0-9-]*)$")
KEYS = ("model", "effort", "context")
VALID = {
    "model": re.compile(r"^[a-z0-9][a-z0-9.-]*$"),
    "effort": re.compile(r"^(none|minimal|low|medium|high|xhigh|max)$"),
    "context": re.compile(r"^[0-9]+[KM]$"),
}
CURRENT_SESSION = "current session"


def frontmatter(path: str) -> Dict[str, str]:
    """The header's top-level ``key: value`` lines; anything after the closing ``---`` is body."""
    values: Dict[str, str] = {}
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    if not lines or lines[0].strip() != "---":
        return values
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*?)\s*$", line)
        if match:
            value = match.group(2)
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[match.group(1)] = value
    return values


def window(context: str) -> int:
    """A header window such as ``272K`` or ``1M`` in tokens."""
    return int(context[:-1]) * (1_000_000 if context.endswith("M") else 1_000)


def tier_for(model: str, context: str, catalog_path: str) -> Tuple[str, str]:
    try:
        with open(catalog_path, encoding="utf-8") as handle:
            caps = json.load(handle).get("models", {}).get(model) or {}
    except (OSError, ValueError, AttributeError):
        caps = {}
    default_cap = caps.get("default_cap") if isinstance(caps, dict) else None
    if not isinstance(default_cap, int) or default_cap <= 0:
        return "default", "fallback"
    if caps.get("long_cap") and window(context) > default_cap:
        return "long_context", "catalog"
    return "default", "catalog"


def result(route: str, reason: Optional[str] = None, **runtime: Optional[str]) -> Dict[str, Optional[str]]:
    resolved: Dict[str, Optional[str]] = {"route": route}
    for key in (*KEYS, "tier", "tier_source"):
        resolved[key] = runtime.get(key)
    if reason:
        resolved["runtime"] = CURRENT_SESSION
        resolved["reason"] = reason
    else:
        resolved["runtime"] = (
            f"model {runtime['model']}, effort {runtime['effort']}, "
            f"context {runtime['context']} ({runtime['tier']})"
        )
    return resolved


def resolve(name: str, skills_dir: str, catalog_path: str) -> Tuple[int, Dict[str, Optional[str]]]:
    route = f"/{name}"
    skill_md = os.path.join(skills_dir, name, "SKILL.md")
    if not os.path.isfile(skill_md):
        return 0, result(route, "no-skill")
    header = frontmatter(skill_md)
    present = [key for key in KEYS if key in header]
    if not present:
        return 0, result(route, "no-header")
    problems = [f"missing {key}" for key in KEYS if key not in header]
    problems += [
        f"{key} {header[key]!r} is not valid" for key in present if not VALID[key].match(header[key])
    ]
    if problems:
        failed = result(route, "invalid-header")
        failed["error"] = f"{skill_md}: " + "; ".join(problems)
        return 1, failed
    tier, source = tier_for(header["model"], header["context"], catalog_path)
    return 0, result(route, tier=tier, tier_source=source, **{key: header[key] for key in KEYS})


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("route", help="the routed skill, such as /implement")
    parser.add_argument("--skills-dir", help="directory holding the installed skills")
    parser.add_argument("--catalog", help="model catalog; defaults to model-scorecard's skill-headers.json")
    args = parser.parse_args(argv)

    match = ROUTE.match(args.route)
    if not match:
        parser.error(f"route {args.route!r} is not a skill name such as /implement")
    skills_dir = args.skills_dir or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    catalog = args.catalog or os.path.join(skills_dir, "model-scorecard", "references", "skill-headers.json")

    status, resolved = resolve(match.group(1), skills_dir, catalog)
    print(json.dumps(resolved, separators=(",", ":")))
    if status:
        print(f"error: {resolved['error']}", file=sys.stderr)
    return status


if __name__ == "__main__":
    sys.exit(main())
