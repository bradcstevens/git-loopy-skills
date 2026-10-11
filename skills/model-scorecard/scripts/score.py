#!/usr/bin/env python3
"""Score every selectable model@effort 1-100 per role and write the scorecard.

Reads a run directory holding ``leaderboard.json`` (capture_leaderboard.py),
``models-copilot.json`` and ``models-git-loopy.json`` (list_models.py) and
``working-sets.json`` (measure_context.py), plus the skill's ``profiles.json``.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
_EFFORT_ALIASES = {"non-reasoning": "none"}
_VARIANT_NOISE = {"with", "fallback", "default", "adaptive"}
_PREFIX_VENDORS = {"claude": "Anthropic", "gpt": "OpenAI", "gemini": "Google", "grok": "xAI"}
BENCHMARKS = (
    "terminalBench40", "terminalbenchHard", "scicode", "lcr", "hle", "gpqa", "critpt",
    "gdpvalNormalized", "ifbench", "omniscienceNonHallucination", "tau2", "mmmuPro",
)
MIN_SAMPLES = 5
FIELD_IDS = {"success", "first_answer", "end_to_end", "token_appetite", "consistency", "throughput"}
DEFAULT_COMPACTION_RATIO = 0.8
BAND_FLOOR_SLOPE = 8.0
BAND_CEILING_SLOPE = 20.0


def roc_weights(count: int) -> list[float]:
    """Rank-order-centroid weights: rank 1 heaviest, summing to 1."""
    return [sum(1 / k for k in range(rank, count + 1)) / count for rank in range(1, count + 1)]


def parse_variant(short_name: str) -> tuple[str, str | None] | None:
    """Split a leaderboard name into (base, effort); ``None`` for unselectable variants."""
    match = re.fullmatch(r"(.+?)(?:\s*\((.+)\))?", short_name.strip())
    if not match:
        return None
    base, variant = match.group(1).strip(), match.group(2)
    if not variant:
        return base, None
    words = [_EFFORT_ALIASES.get(word, word) for word in re.split(r"[\s,]+", variant.lower()) if word]
    efforts = [word for word in words if word in EFFORTS]
    others = [word for word in words if word not in EFFORTS and word not in _VARIANT_NOISE]
    if others or len(efforts) != 1:
        return None
    return base, efforts[0]


def copilot_id(base: str) -> str:
    return base.lower().replace(" ", "-")


def _spread(row: dict) -> float | None:
    logs = []
    for low, high in (
        ("percentile05TimeToFirstTokenSeconds", "percentile95TimeToFirstTokenSeconds"),
        ("percentile05OutputTokensPerSecond", "percentile95OutputTokensPerSecond"),
    ):
        if row.get(low) and row.get(high):
            logs.append(abs(math.log(row[high] / row[low])))
    return statistics.mean(logs) if logs else None


def build_candidates(rows: list[dict], listing: dict) -> list[dict]:
    """Leaderboard variants the harness can select, one per (model id, effort)."""
    models = {model["id"]: model for model in listing["models"] if model.get("policy") != "disabled"}
    chosen: dict[tuple[str, str | None], dict] = {}
    for row in rows:
        if row.get("deprecated") or row.get("intelligenceIndex") is None:
            continue
        parsed = parse_variant(row.get("shortName") or "")
        if not parsed:
            continue
        base, effort = parsed
        model = models.get(copilot_id(base))
        if model is None:
            continue
        if model["efforts"] and effort not in model["efforts"]:
            continue
        if not model["efforts"] and effort is not None:
            continue
        cost, out_price = row.get("intelligenceIndexCostPerTask"), row.get("price1mOutputTokens")
        candidate = {
            "id": model["id"],
            "effort": effort,
            "vendor": row.get("modelCreatorName") or _PREFIX_VENDORS.get(model["id"].split("-")[0], "?"),
            "aa": row.get("shortName"),
            "ii": row["intelligenceIndex"],
            "ii_estimated": bool(row.get("intelligenceIndexIsEstimated")),
            "first_answer": row.get("medianTimeToFirstAnswerTokenSeconds")
            or row.get("medianTimeToFirstTokenSeconds"),
            "end_to_end": row.get("medianEndToEndResponseTimeSeconds"),
            "token_appetite": cost / out_price * 1e6 if cost and out_price else None,
            "consistency": _spread(row),
            "throughput": row.get("medianOutputTokensPerSecond") or None,
            "benchmarks": {name: row.get(name) for name in BENCHMARKS if row.get(name) is not None},
            "default_cap": model["default_cap"],
            "long_cap": model["long_cap"],
        }
        key = (candidate["id"], effort)
        filled = sum(value is not None for value in candidate.values())
        if key not in chosen or filled > sum(v is not None for v in chosen[key].values()):
            chosen[key] = candidate
    return list(chosen.values())


class Scale:
    """Maps a metric onto 0..1 across a candidate pool; a missing value is neutral."""

    def __init__(self, values, *, log: bool, lower_better: bool):
        present = [self._t(v, log) for v in values if v is not None]
        self.log, self.lower_better = log, lower_better
        self.low, self.high = (min(present), max(present)) if present else (0.0, 0.0)

    @staticmethod
    def _t(value: float, log: bool) -> float:
        return math.log(max(value, 1e-3)) if log else value

    def __call__(self, value) -> float:
        if value is None or self.high == self.low:
            return 0.5
        unit = (self._t(value, self.log) - self.low) / (self.high - self.low)
        unit = min(1.0, max(0.0, unit))
        return 1.0 - unit if self.lower_better else unit


def build_scales(pool: list[dict]) -> dict[str, Scale]:
    scales = {
        "first_answer": Scale([c["first_answer"] for c in pool], log=True, lower_better=True),
        "end_to_end": Scale([c["end_to_end"] for c in pool], log=True, lower_better=True),
        "token_appetite": Scale([c["token_appetite"] for c in pool], log=True, lower_better=True),
        "consistency": Scale([c["consistency"] for c in pool], log=False, lower_better=True),
        "throughput": Scale([c["throughput"] for c in pool], log=True, lower_better=False),
        "ii": Scale([c["ii"] for c in pool], log=False, lower_better=False),
    }
    for name in BENCHMARKS:
        scales[name] = Scale([c["benchmarks"].get(name) for c in pool], log=False, lower_better=False)
    return scales


def band_fit(ii: float, band: list[float]) -> float:
    floor, ceiling = band
    if ii < floor:
        return max(0.0, 1 - (floor - ii) / BAND_FLOOR_SLOPE)
    if ii > ceiling:
        return max(0.5, 1 - (ii - ceiling) / BAND_CEILING_SLOPE)
    return 1.0


def success(candidate: dict, role: dict, scales: dict[str, Scale]) -> float:
    present = [scales[name](candidate["benchmarks"][name]) for name in role["benchmarks"] if name in candidate["benchmarks"]]
    strength = statistics.mean(present) if present else scales["ii"](candidate["ii"])
    return band_fit(candidate["ii"], role["band"]) * (0.5 + 0.5 * strength)


def score(candidate: dict, role: dict, scales: dict[str, Scale], fields: list[str]) -> tuple[int, dict]:
    parts = {
        field: success(candidate, role, scales) if field == "success" else scales[field](candidate[field])
        for field in fields
    }
    total = sum(weight * parts[field] for field, weight in zip(fields, roc_weights(len(fields))))
    return max(1, min(100, round(100 * total))), parts


def in_band(candidate: dict, role: dict) -> bool:
    floor, ceiling = role["band"]
    return floor <= candidate["ii"] <= ceiling


def rank(role: dict, pool: list[dict], scales, fields, blocked_vendor: str | None) -> list[dict]:
    ranked = []
    for candidate in pool:
        if candidate["effort"] in role.get("exclude_efforts", []):
            continue
        if blocked_vendor and candidate["vendor"] == blocked_vendor:
            continue
        value, parts = score(candidate, role, scales, fields)
        ranked.append({**candidate, "score": value, "parts": parts, "in_band": in_band(candidate, role)})
    ranked.sort(key=lambda c: (not c["in_band"], -c["score"], c["end_to_end"] or math.inf, c["id"]))
    return ranked


def context_choice(role: dict, pick: dict, working_set: dict | None, ratio: float | None) -> dict:
    if working_set and working_set["n"] >= MIN_SAMPLES:
        need, source = working_set["p95"], f"p95 of {working_set['n']} runs"
    else:
        need, source = role["working_set_k"] * 1000, "profile estimate"
    tier, cap = "default", pick["default_cap"]
    if role["context"] == "fit" and cap and need > (ratio or DEFAULT_COMPACTION_RATIO) * cap and pick["long_cap"]:
        tier, cap = "long_context", pick["long_cap"]
    return {"tier": tier, "cap": cap, "need": need, "source": source}


def vendor_of(model_id: str | None, pools: list[list[dict]]) -> str | None:
    if not model_id:
        return None
    for pool in pools:
        for candidate in pool:
            if candidate["id"] == model_id:
                return candidate["vendor"]
    return _PREFIX_VENDORS.get(model_id.split("-")[0])


def recommend(profiles: dict, pools: dict[str, list[dict]], working_sets: dict, main_model: str | None) -> dict:
    fields = [field["id"] for field in profiles["fields"]]
    unknown = set(fields) - FIELD_IDS
    if unknown or len(set(fields)) != len(fields):
        raise SystemExit(f"profiles.json fields must be distinct ids from {sorted(FIELD_IDS)}; got {fields}")
    needs_main = [r for r, role in profiles["roles"].items() if role.get("distinct_vendor_from") == "main"]
    main_vendor = vendor_of(main_model, list(pools.values()))
    if needs_main and not main_vendor:
        raise SystemExit(
            f"{', '.join(needs_main)} must avoid the main model's vendor, but the vendor of main model "
            f"{main_model!r} is unknown; pass a concrete model id with --main-model"
        )
    scales = {harness: build_scales(pool) for harness, pool in pools.items()}
    ratio = (working_sets.get("compaction") or {}).get("ratio")
    picks: dict[str, dict] = {}
    pending = dict(profiles["roles"])
    while pending:
        progressed = False
        for role_id, role in list(pending.items()):
            dependency = role.get("distinct_vendor_from")
            if dependency and dependency != "main" and dependency not in picks:
                continue
            blocked = (
                main_vendor if dependency == "main"
                else picks[dependency]["pick"]["vendor"] if dependency else None
            )
            ranked = rank(role, pools[role["harness"]], scales[role["harness"]], fields, blocked)
            if not ranked:
                raise SystemExit(f"{role_id}: no selectable candidate")
            pick = ranked[0]
            picks[role_id] = {
                "pick": pick,
                "runner_up": ranked[1] if len(ranked) > 1 else None,
                "top": ranked[:3],
                "blocked_vendor": blocked,
                "context": context_choice(role, pick, working_sets.get("roles", {}).get(role_id), ratio),
            }
            del pending[role_id]
            progressed = True
        if not progressed:
            raise SystemExit(f"unresolvable distinct_vendor_from cycle: {sorted(pending)}")
    return picks


def _skip_string(text: str, start: int) -> int:
    """Index just past the JSON string literal that opens at ``start``."""
    index = start + 1
    while index < len(text) and text[index] != '"':
        index += 2 if text[index] == "\\" else 1
    return index + 1


def _jsonc_to_json(text: str) -> str:
    """Drop comments and trailing commas outside strings, as Copilot's settings.json allows."""
    kept, index = [], 0
    while index < len(text):
        if text[index] == '"':
            end = _skip_string(text, index)
            kept.append(text[index:end])
            index = end
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline
        elif text.startswith("/*", index):
            close = text.find("*/", index + 2)
            index = len(text) if close < 0 else close + 2
        else:
            kept.append(text[index])
            index += 1
    cleaned, result, index = "".join(kept), [], 0
    while index < len(cleaned):
        if cleaned[index] == '"':
            end = _skip_string(cleaned, index)
            result.append(cleaned[index:end])
            index = end
            continue
        if not (cleaned[index] == "," and cleaned[index + 1 :].lstrip()[:1] in ("}", "]")):
            result.append(cleaned[index])
        index += 1
    return "".join(result)


def current_settings(settings_path: Path, git_loopy: Path | None) -> tuple[str | None, dict, dict]:
    """The main model, each role's configured (model, effort, tier), and the files read."""
    now: dict[str, str] = {}
    sources: dict[str, str] = {}
    main_model = None
    try:
        settings = json.loads(_jsonc_to_json(settings_path.read_text()))
    except (OSError, json.JSONDecodeError) as error:
        print(f"note: Copilot settings unreadable at {settings_path}: {error}", file=sys.stderr)
        settings = None
    if isinstance(settings, dict):
        main_model = settings.get("model")
        sources["copilot"] = str(settings_path)
        for agent, value in (settings.get("subagents") or {}).get("agents", {}).items():
            now[f"copilot:{agent}"] = f"{value.get('model')} {value.get('effortLevel') or ''} {value.get('contextTier') or ''}".strip()
    candidates = [git_loopy / "git-loopy" / "config.toml"] if git_loopy else []
    candidates.append(Path("~/.config/git-loopy/config.toml").expanduser())
    for path in candidates:
        if path.is_file():
            config = tomllib.loads(path.read_text())
            tier = config.get("context_tier", "")
            sources["git-loopy"] = str(path)
            for task_type, route in (config.get("routing") or {}).items():
                if isinstance(route, dict) and "model" in route:
                    now[f"git-loopy:{task_type}"] = f"{route['model']} {route.get('effort', '')} {tier}".strip()
            break
    return main_model, now, sources


def _k(tokens: int | None) -> str:
    return f"{round(tokens / 1000)}K" if tokens else "?"


def _pair(candidate: dict | None) -> str:
    if not candidate:
        return "—"
    return f"`{candidate['id']}` {candidate['effort'] or 'n/a'} ({candidate['score']})"


def _row(role_id: str, result: dict, now: dict) -> str:
    pick, context = result["pick"], result["context"]
    flags = []
    if not pick["in_band"]:
        flags.append("outside band")
    if pick["ii_estimated"]:
        flags.append("II estimated")
    ii = f"{pick['ii']:.1f}" + (f" ({', '.join(flags)})" if flags else "")
    return (
        f"| {role_id.split(':', 1)[1]} | `{pick['id']}` | {pick['effort'] or 'n/a'} | "
        f"{_k(context['cap'])} {context['tier']} | {pick['score']} | {ii} | "
        f"{_pair(result['runner_up'])} | {now.get(role_id, '—')} |"
    )


def render(profiles: dict, picks: dict, meta: dict, now: dict) -> str:
    fields = profiles["fields"]
    weights = roc_weights(len(fields))
    weight_line = " · ".join(f"{field['label']} {100 * weight:.1f}" for field, weight in zip(fields, weights))
    header = "| {} | Model | Effort | Context | Score | II | Runner-up | Now |\n|---|---|---|---|---|---|---|---|"
    copilot_rows = [_row(r, picks[r], now) for r in profiles["roles"] if r.startswith("copilot:")]
    loopy_rows = [_row(r, picks[r], now) for r in profiles["roles"] if r.startswith("git-loopy:")]
    sdlc_rows = []
    for entry in profiles["sdlc"]:
        result = picks[entry["role"]]
        pick = result["pick"]
        sdlc_rows.append(
            f"| {entry['task']} | {entry['what']} | {entry['role']} | `{pick['id']}` | "
            f"{pick['effort'] or 'n/a'} | {_k(result['context']['cap'])} {result['context']['tier']} | {pick['score']} |"
        )
    evidence_rows = []
    for role_id, role in profiles["roles"].items():
        result = picks[role_id]
        context = result["context"]
        top = ", ".join(f"`{c['id']}` {c['effort'] or 'n/a'} {c['score']}" for c in result["top"])
        blocked = f"; excludes {result['blocked_vendor']}" if result["blocked_vendor"] else ""
        evidence_rows.append(
            f"| {role_id} | {role['band'][0]}–{role['band'][1]} | {', '.join(role['benchmarks'])} | "
            f"{_k(context['need'])} ({context['source']}) | {top}{blocked} | {role['why']} |"
        )
    gaps = meta["gaps"]
    lines = [
        "# Model scorecard",
        "",
        f"Generated {meta['generated']} by `/model-scorecard`; regenerate rather than edit.",
        f"Leaderboard: {meta['page']}, captured {meta['captured']}: {meta['current_models']} current models; "
        f"Jev verified {meta['rows_matched']} visible rows with 0 conflicts.",
        f"Harnesses: installed `copilot` {meta['copilot_version']} (subagents) and git-loopy's SDK CLI "
        f"{meta['sdk_version']} (task types). Compaction triggers at {meta['ratio']} of the window.",
        "",
        f"**Score** is 1–100 fit for the role, weighted by rank (rank-order centroid): {weight_line}.",
        "**Context** is the prompt cap the recommended tier gives that model. **II** is the Intelligence Index.",
        "",
        "## Copilot built-in subagents",
        "",
        "Apply with `/subagents`, or `subagents.agents.<agent>` in `~/.copilot/settings.json`: "
        "`model`, `effortLevel`, `contextTier`. "
        f"**Now** reads `{meta.get('now_sources', {}).get('copilot', 'nothing')}`; "
        f"rubber-duck avoids the vendor of the main session model, `{meta.get('main_model')}`.",
        "",
        header.format("Agent"),
        *copilot_rows,
        "",
        "## git-loopy task types",
        "",
        "Apply with `[routing.<type>]` `model` and `effort` in git-loopy's `config.toml`. "
        "`context_tier` is run-level (ADR-0017), so Context shows each model's default-tier cap. "
        f"**Now** reads `{meta.get('now_sources', {}).get('git-loopy', 'nothing')}`.",
        "",
        header.format("Task type"),
        *loopy_rows,
        "",
        "## SDLC task types",
        "",
        "Each common software-lifecycle task maps to the role whose work it is; its row repeats that role's pick.",
        "",
        "| Task | Covers | Role | Model | Effort | Context | Score |",
        "|---|---|---|---|---|---|---|",
        *sdlc_rows,
        "",
        "## Evidence per role",
        "",
        "| Role | II band | Benchmarks | Working set | Top three | Why |",
        "|---|---|---|---|---|---|",
        *evidence_rows,
        "",
        "## Method",
        "",
        "- **Candidates**: each current leaderboard variant whose name maps to a model id and effort the role's "
        "harness lists; git-loopy roles skip `max`, which git-loopy keeps as its retry rung.",
        "- **Task-fit success** = band fit × (0.5 + 0.5 × mean of the role's benchmarks, normalised across the pool). "
        f"Band fit is 1 inside the band, falls to 0 at {BAND_FLOOR_SLOPE:g} points below the floor, and to 0.5 at "
        f"{BAND_CEILING_SLOPE:g} points above the ceiling. The pick is the best-scoring in-band candidate.",
        "- **Speed fields** are normalised across the harness's pool on a log scale; a missing value scores 0.5.",
        "- **Context**: a subagent keeps the default tier unless its p95 working set passes the compaction "
        "trigger, then takes `long_context`. git-loopy roles use the default tier.",
        "- Leaderboard latency ranks models; real agent turns think less, so read the speed fields as order, "
        "not seconds.",
        "",
        "## Coverage gaps",
        "",
        f"- Retired on the leaderboard, so unscored: {', '.join(gaps['retired']) or 'none'}.",
        f"- Not on the leaderboard: {', '.join(gaps['absent']) or 'none'}.",
    ]
    return "\n".join(lines) + "\n"


def coverage(listings: list[dict], pools: list[list[dict]], rows: list[dict]) -> dict:
    scored = {candidate["id"] for pool in pools for candidate in pool}
    listed = {model["id"] for listing in listings for model in listing["models"]}
    retired = set()
    for row in rows:
        parsed = parse_variant(row.get("shortName") or "")
        if parsed and row.get("deprecated"):
            retired.add(copilot_id(parsed[0]))
    unscored = listed - scored
    return {"retired": sorted(unscored & retired), "absent": sorted(unscored - retired)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--profiles", type=Path, default=Path(__file__).resolve().parents[1] / "profiles.json")
    parser.add_argument(
        "--settings",
        type=Path,
        default=Path(os.environ.get("COPILOT_HOME", "~/.copilot")).expanduser() / "settings.json",
    )
    parser.add_argument("--main-model", help="main session model id; defaults to `model` in the settings file")
    parser.add_argument("--git-loopy", type=Path, help="git-loopy checkout whose config.toml shows current routes")
    args = parser.parse_args()

    load = lambda name: json.loads((args.run_dir / name).read_text())
    profiles, leaderboard = json.loads(args.profiles.read_text()), load("leaderboard.json")
    listings = {"copilot-cli": load("models-copilot.json"), "git-loopy": load("models-git-loopy.json")}
    working_sets = load("working-sets.json")
    pools = {harness: build_candidates(leaderboard["models"], listing) for harness, listing in listings.items()}
    settings_main, now, now_sources = current_settings(args.settings, args.git_loopy)
    main_model = args.main_model or settings_main
    picks = recommend(profiles, pools, working_sets, main_model)

    for role_id, result in picks.items():
        pick, context = result["pick"], result["context"]
        listing = next(m for m in listings[profiles["roles"][role_id]["harness"]]["models"] if m["id"] == pick["id"])
        assert pick["effort"] is None or pick["effort"] in listing["efforts"], role_id
        assert context["tier"] == "default" or listing["long_cap"], role_id
        assert 1 <= pick["score"] <= 100, role_id

    verification = leaderboard["verification"]
    meta = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="minutes"),
        "page": leaderboard["page"],
        "captured": leaderboard["captured_at"],
        "current_models": verification["current_models"],
        "rows_matched": verification["rows_matched"],
        "copilot_version": listings["copilot-cli"]["cli_version"],
        "sdk_version": listings["git-loopy"]["cli_version"],
        "ratio": (working_sets.get("compaction") or {}).get("ratio") or DEFAULT_COMPACTION_RATIO,
        "gaps": coverage(list(listings.values()), list(pools.values()), leaderboard["models"]),
        "now_sources": {key: value.replace(str(Path.home()), "~") for key, value in now_sources.items()},
        "main_model": main_model,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(profiles, picks, meta, now), encoding="utf-8")
    summary = {
        role_id: f"{r['pick']['id']} {r['pick']['effort'] or 'n/a'} {_k(r['context']['cap'])} {r['context']['tier']} score {r['pick']['score']}"
        for role_id, r in picks.items()
    }
    print(json.dumps(summary, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
