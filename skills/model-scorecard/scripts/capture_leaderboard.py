#!/usr/bin/env python3
"""Capture the Artificial Analysis leaderboard dataset, verified by a Jev run.

Jev (the co-installed jev-ultrafast skill's helper) opens the live leaderboard and
reports the rows a visitor sees. The full dataset rides in the same page as a
Next.js payload; this script parses it and cross-checks it against Jev's rows, so
the captured numbers are the ones the live page shows.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_URL = "https://huggingface.co/spaces/ArtificialAnalysis/LLM-Performance-Leaderboard"
JEV_GOAL = (
    "Show the LLM leaderboard table. Stop when its first model rows are visible "
    "with name, creator, Intelligence Index, cost per task, output speed and latency."
)
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko)"
MIN_MATCHED_ROWS = 5
_CHUNK = re.compile(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', re.S)
_IFRAME = re.compile(r'<iframe[^>]*\bsrc="([^"]+)"', re.I)
_DOLLAR_NUMBER = re.compile(r"\$+(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)")


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def has_dataset(html: str) -> bool:
    return "self.__next_f.push" in html and "intelligenceIndex" in html


def resolve_dataset_page(url: str, get=fetch, depth: int = 4) -> tuple[str, str]:
    """Follow nested iframes from ``url`` to the page that embeds the dataset."""
    for _ in range(depth):
        html = get(url)
        if has_dataset(html):
            return url, html
        match = _IFRAME.search(html)
        if not match:
            break
        url = match.group(1)
    raise RuntimeError(f"no leaderboard dataset found at or below {url}")


def _clean(value):
    if isinstance(value, str):
        if value == "$undefined":
            return None
        match = _DOLLAR_NUMBER.fullmatch(value)
        if match:
            return float(match.group(1))
    return value


def parse_models(html: str) -> list[dict]:
    """Decode the page's flight payload and return its model rows."""
    payload = "".join(json.loads(f'"{chunk}"') for chunk in _CHUNK.findall(html))
    anchor = payload.find('"intelligenceIndex"')
    if anchor < 0:
        raise RuntimeError("payload carries no intelligenceIndex field")
    decoder = json.JSONDecoder()
    position = payload.rfind("[{", 0, anchor)
    while position >= 0:
        try:
            rows, _ = decoder.raw_decode(payload, position)
        except json.JSONDecodeError:
            rows = None
        if (
            isinstance(rows, list)
            and rows
            and isinstance(rows[0], dict)
            and "intelligenceIndex" in rows[0]
        ):
            return [{key: _clean(value) for key, value in row.items()} for row in rows]
        position = payload.rfind("[{", 0, position)
    raise RuntimeError("could not locate the model array in the payload")


def _half_up(value: float) -> int:
    return math.floor(value + 0.5)


def expected_tokens(row: dict) -> list[str]:
    """The cell texts the leaderboard table renders for ``row``."""
    tokens = []
    if row.get("intelligenceIndex") is not None:
        tokens.append(str(_half_up(row["intelligenceIndex"])))
    if row.get("intelligenceIndexCostPerTask") is not None:
        tokens.append(f"${row['intelligenceIndexCostPerTask']:.2f}")
    if row.get("medianOutputTokensPerSecond"):
        tokens.append(str(_half_up(row["medianOutputTokensPerSecond"])))
    if row.get("medianTimeToFirstTokenSeconds") is not None:
        tokens.append(f"{row['medianTimeToFirstTokenSeconds']:.2f}")
    if row.get("medianEndToEndResponseTimeSeconds") is not None:
        tokens.append(f"{row['medianEndToEndResponseTimeSeconds']:.2f}")
    return tokens


def cross_check(models: list[dict], visible_text: str) -> dict:
    """Compare dataset rows with the table rows Jev saw."""
    lines = [line.strip() for line in visible_text.splitlines()]
    by_name = {row["shortName"]: row for row in models if row.get("shortName")}
    names = [index for index, line in enumerate(lines) if line in by_name]
    matched, conflicts = [], []
    for position, index in enumerate(names):
        end = names[position + 1] if position + 1 < len(names) else min(len(lines), index + 10)
        window = set(lines[index + 1 : end])
        expected = expected_tokens(by_name[lines[index]])
        found = sum(token in window for token in expected)
        if expected and found >= min(3, len(expected)):
            matched.append(lines[index])
        elif expected:
            conflicts.append({"model": lines[index], "expected": expected, "seen": sorted(window)})
    return {"rows_seen": len(names), "matched": matched, "conflicts": conflicts}


def run_jev(jev_home: Path, jev_script: Path, url: str, headless: bool) -> dict:
    """Run jev-ultrafast's helper exactly as that skill documents it."""
    launcher = (
        'J="$1"; S="$2"; shift 2; '
        'if [[ -f "$J/.env" ]]; then exec uv run --project "$J" --no-sync --env-file "$J/.env" python "$S" "$@"; fi; '
        'exec uv run --project "$J" --no-sync python "$S" "$@"'
    )
    command = [
        "zsh", "-c", launcher, "jev", str(jev_home), str(jev_script),
        url, JEV_GOAL, "--headless" if headless else "--no-headless",
    ]
    result = subprocess.run(
        command, cwd=jev_home, capture_output=True, text=True, timeout=600, check=False
    )
    reports = [line for line in result.stdout.splitlines() if line.startswith("{")]
    if not reports:
        tail = (result.stderr or result.stdout).strip().splitlines()[-5:]
        raise RuntimeError(f"Jev produced no observation (exit {result.returncode}): {' | '.join(tail)}")
    return json.loads(reports[-1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jev-home", required=True, type=Path, help="jev-ultrafast checkout")
    parser.add_argument("--out", required=True, type=Path, help="leaderboard JSON to write")
    parser.add_argument("--url", default=DEFAULT_URL, help="leaderboard page or a page framing it")
    parser.add_argument(
        "--jev-script",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "jev-ultrafast" / "scripts" / "run_jev.py",
        help="jev-ultrafast's run_jev.py helper",
    )
    parser.add_argument("--headless", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    page_url, html = resolve_dataset_page(args.url)
    models = parse_models(html)
    jev = run_jev(args.jev_home.expanduser(), args.jev_script, page_url, args.headless)
    check = cross_check(models, jev.get("visible_text", ""))
    summary = {
        "page": page_url,
        "models": len(models),
        "current_models": sum(1 for row in models if not row.get("deprecated")),
        "jev_status": jev.get("status"),
        "rows_seen": check["rows_seen"],
        "rows_matched": len(check["matched"]),
        "conflicts": len(check["conflicts"]),
    }
    verified = (
        jev.get("status") == "done"
        and len(check["matched"]) >= MIN_MATCHED_ROWS
        and not check["conflicts"]
    )
    print(json.dumps(summary))
    if not verified:
        for conflict in check["conflicts"][:5]:
            print(json.dumps(conflict), file=sys.stderr)
        print("capture not verified: Jev must finish 'done' with matching rows", file=sys.stderr)
        return 1
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(
            {
                "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "page": page_url,
                "verification": {**summary, "matched_models": check["matched"]},
                "models": models,
            }
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
