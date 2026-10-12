#!/usr/bin/env python3
"""Measure each role's working set — its peak prompt per run — from local history.

Copilot built-ins come from ``<copilot-home>/session-state/*/events.jsonl``: a
subagent run's peak ``inputTokens`` across its model calls. Skills come from the
same logs: a run of a skill opens when a user message starting ``/<skill>``
follows the CLI's ``skill.invoked`` for it, and its working set is the main
session's peak ``inputTokens`` until the next such message. git-loopy task types
come from a checkout's ``.git-loopy/logs/*.jsonl``: each Iteration's
``peak_context_window``. The harness's own compaction trigger ratio is read from
its ``session.compaction_start`` events.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import statistics
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

BUILTINS = {"explore", "task", "general-purpose", "rubber-duck", "code-review", "research", "security-review"}
_COPILOT_MARKERS = (
    '"subagent.started"', '"session.usage_record"', '"session.compaction_start"', '"skill.invoked"', '"user.message"',
)
_SLASH_COMMAND = re.compile(r"/([a-z0-9][a-z0-9-]*)(?=\s|$)")
_LOOPY_MARKERS = ('"wrapper.pickup.bound"', '"wrapper.iteration.end"', '"wrapper.contribution.end"')


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def summarise(peaks: list[int]) -> dict:
    return {
        "n": len(peaks),
        "p50": percentile(peaks, 0.50),
        "p95": percentile(peaks, 0.95),
        "max": max(peaks),
    }


def _events(path: str, markers: tuple[str, ...]):
    with open(path, errors="replace") as handle:
        for line in handle:
            if any(marker in line for marker in markers):
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue


def scan_copilot(home: Path, sessions: int) -> tuple[dict[str, list[int]], dict[str, list[int]], list[float]]:
    """Peaks per built-in subagent run, peaks per user-invoked skill run, and compaction ratios."""
    files = sorted(glob.glob(str(home / "session-state" / "*" / "events.jsonl")), key=os.path.getmtime)
    peaks: dict[str, list[int]] = defaultdict(list)
    skill_peaks: dict[str, list[int]] = defaultdict(list)
    ratios: list[float] = []
    for path in files[-sessions:]:
        agent_names: dict[str, str] = {}
        per_run: dict[str, int] = defaultdict(int)
        invoked: set[str] = set()
        skill, skill_peak = None, 0
        for event in _events(path, _COPILOT_MARKERS):
            kind, data, agent = event.get("type"), event.get("data") or {}, event.get("agentId")
            if kind == "subagent.started":
                agent_names[agent] = data.get("agentName")
            elif kind == "skill.invoked" and not agent:
                invoked.add(data.get("name"))
            elif kind == "user.message" and not agent:
                # The CLI logs skill.invoked just before the message that named the skill, so only a
                # message opening with a just-confirmed /<skill> starts a run; built-in commands and
                # skills the model loads mid-task do not.
                match = _SLASH_COMMAND.match((data.get("content") or "").lstrip())
                if match and match.group(1) in invoked:
                    if skill and skill_peak:
                        skill_peaks[skill].append(skill_peak)
                    skill, skill_peak = match.group(1), 0
                invoked.clear()
            elif kind == "session.usage_record":
                tokens = (data.get("usage") or {}).get("inputTokens") or 0
                if not agent:
                    if skill:
                        skill_peak = max(skill_peak, tokens)
                elif agent_names.get(agent) in BUILTINS:
                    per_run[agent] = max(per_run[agent], tokens)
            elif kind == "session.compaction_start" and data.get("trigger") == "threshold":
                if data.get("tokenLimit"):
                    ratios.append(data["currentTokens"] / data["tokenLimit"])
        if skill and skill_peak:
            skill_peaks[skill].append(skill_peak)
        for agent, peak in per_run.items():
            if peak:
                peaks[f"copilot:{agent_names[agent]}"].append(peak)
    return peaks, skill_peaks, ratios


def issue_task_types(checkout: Path) -> dict[int, str]:
    """Current ``task-type:`` labels, so Iterations picked before labelling still count."""
    try:
        result = subprocess.run(
            ["gh", "issue", "list", "--state", "all", "--limit", "5000", "--json", "number,labels"],
            cwd=checkout, capture_output=True, text=True, timeout=120, check=True,
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(f"note: issue labels unavailable ({error}); using Pickup task types only", file=sys.stderr)
        return {}
    types = {}
    for issue in json.loads(result.stdout or "[]"):
        for label in issue.get("labels", []):
            if label.get("name", "").startswith("task-type:"):
                types[issue["number"]] = label["name"].split(":", 1)[1]
    return types


def scan_git_loopy(checkout: Path) -> dict[str, list[int]]:
    labels = issue_task_types(checkout)
    peaks: dict[str, list[int]] = defaultdict(list)
    for path in sorted(glob.glob(str(checkout / ".git-loopy" / "logs" / "*.jsonl"))):
        picked: dict[int, str] = {}
        for event in _events(path, _LOOPY_MARKERS):
            if event.get("type") == "wrapper.pickup.bound" and event.get("issue") is not None:
                keys = event.get("task_type_keys") or []
                if keys:
                    picked[event["issue"]] = keys[0]
                continue
            for record in event.get("issues") or []:
                tokens = (record.get("peak_context_window") or {}).get("current_tokens")
                task_type = picked.get(record.get("issue")) or labels.get(record.get("issue"))
                if tokens and task_type:
                    peaks[f"git-loopy:{task_type}"].append(tokens)
    return peaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--copilot-home", type=Path, default=Path(os.environ.get("COPILOT_HOME", "~/.copilot")).expanduser()
    )
    parser.add_argument("--sessions", type=int, default=400, help="newest sessions to scan")
    parser.add_argument("--git-loopy", type=Path, help="git-loopy checkout whose Run logs to scan")
    args = parser.parse_args()

    peaks, skill_peaks, ratios = scan_copilot(args.copilot_home, args.sessions)
    if args.git_loopy:
        peaks.update(scan_git_loopy(args.git_loopy.expanduser()))
    report = {
        "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "compaction": {"ratio": round(statistics.median(ratios), 3) if ratios else None, "n": len(ratios)},
        "roles": {role: summarise(values) for role, values in sorted(peaks.items())},
        "skills": {skill: summarise(values) for skill, values in sorted(skill_peaks.items())},
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps({
        "roles": {role: row["n"] for role, row in report["roles"].items()},
        "skills": {skill: row["n"] for skill, row in report["skills"].items()},
        "compaction": report["compaction"],
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
