#!/usr/bin/env python3
"""Project each skill's model, effort and context into its skill and named agent.

The picks come from ``skill-headers.json``, which /model-scorecard writes beside its
scorecard. With ``--decision``, each skill instead takes the profile set-task-models
decided for its role, and its context is re-fitted to that model by the scorecard's
rule. Agents use model/reasoning-effort frontmatter, context metadata and an
explicitly sized CLI launch command: agent frontmatter cannot set runtime context.
Dry-run by default; ``--write`` edits differing files, and ``--check`` exits 1
while any differ. Exit 2 means the inputs cannot produce every projection.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

KEYS = ("model", "effort", "context")
EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
DEFAULT_REPO = Path("~/code/github/bradcstevens/git-loopy-skills")
HEADERS = Path("skills/model-scorecard/references/skill-headers.json")
DEFAULT_COMPACTION_RATIO = 0.8
_MODEL_ID = re.compile(r"[a-z0-9][a-z0-9.-]*")
_CONTEXT = re.compile(r"[0-9]+[KM]")
AGENT_START = "<!-- model-scorecard: start -->"
AGENT_END = "<!-- model-scorecard: end -->"


class HeaderError(Exception):
    """The inputs cannot produce a valid header."""


def fit_tier(need: int, default_cap: int | None, long_cap: int | None, ratio: float | None) -> tuple[str, int | None]:
    """The default tier, unless ``need`` passes its compaction trigger and the model has a long tier.

    The same rule as model-scorecard's ``score.fit_tier``.
    """
    if default_cap and long_cap and need > (ratio or DEFAULT_COMPACTION_RATIO) * default_cap:
        return "long_context", long_cap
    return "default", default_cap


def context_size(tokens: int) -> str:
    """A prompt cap as a header writes it: whole millions as ``1M``, otherwise thousands as ``272K``."""
    thousands = round(tokens / 1000)
    return f"{thousands // 1000}M" if thousands >= 1000 and thousands % 1000 == 0 else f"{thousands}K"


def decided(name: str, entry: dict, decision: dict, models: dict, ratio: float | None) -> dict[str, str]:
    """The profile ``decision`` binds to the skill's role, with context re-fitted to that profile's model."""
    harness, _, role = entry["role"].partition(":")
    table = decision.get("git_loopy" if harness == "git-loopy" else harness) or {}
    profile = (decision.get("profiles") or {}).get(table.get(role))
    if not profile:
        raise HeaderError(f"{name}: decision.json binds no profile to {entry['role']}")
    model = models.get(profile.get("model"))
    if model is None:
        raise HeaderError(f"{name}: {profile.get('model')} is not in skill-headers.json; rebuild the scorecard")
    _, cap = fit_tier(entry["need"], model.get("default_cap"), model.get("long_cap"), ratio)
    if not cap:
        raise HeaderError(f"{name}: skill-headers.json lists no prompt cap for {profile['model']}")
    return {"model": profile["model"], "effort": profile.get("effort") or "none", "context": context_size(cap)}


def targets(headers: dict, decision: dict | None) -> dict[str, dict[str, str]]:
    """Every mapped skill's wanted header values."""
    ratio = headers.get("compaction_ratio")
    wanted: dict[str, dict[str, str]] = {}
    for name, entry in headers["skills"].items():
        if decision:
            values = decided(name, entry, decision, headers.get("models") or {}, ratio)
        else:
            values = {key: entry[key] for key in KEYS}
        if not _MODEL_ID.fullmatch(str(values["model"])):
            raise HeaderError(f"{name}: model {values['model']!r} is not a Copilot model id")
        if values["effort"] not in EFFORTS:
            raise HeaderError(f"{name}: effort {values['effort']!r} is not one of {', '.join(EFFORTS)}")
        if not _CONTEXT.fullmatch(str(values["context"])):
            raise HeaderError(f"{name}: context {values['context']!r} is not a size like 200K or 1M")
        wanted[name] = values
    return wanted


def skill_files(repo: Path) -> dict[str, Path]:
    """Each skill's SKILL.md by skill name; a git-ignored skill is local-only, not this repo's."""
    found: dict[str, Path] = {}
    for skill_md in sorted((repo / "skills").rglob("SKILL.md")):
        if "node_modules" in skill_md.parts:
            continue
        relative = f"{skill_md.parent.relative_to(repo).as_posix()}/"
        ignored = subprocess.run(["git", "-C", str(repo), "check-ignore", "-q", relative], capture_output=True)
        if ignored.returncode not in (0, 1):
            raise HeaderError(f"cannot check ignored skills: {ignored.stderr.decode().strip()}")
        if ignored.returncode == 1:
            name = skill_md.parent.name
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
                raise HeaderError(f"{skill_md}: invalid skill name {name!r}")
            if name in found:
                raise HeaderError(f"duplicate skill name {name}: {found[name]} and {skill_md}")
            found[name] = skill_md
    return found


def _split(text: str) -> tuple[list[str], int]:
    """The file's lines, endings kept, and the index of the line closing its frontmatter."""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise HeaderError("no YAML frontmatter")
    for index in range(1, len(lines)):
        if lines[index].rstrip("\r\n") == "---":
            return lines, index
    raise HeaderError("unclosed YAML frontmatter")


def _key(line: str) -> str | None:
    if line[:1].isspace() or ":" not in line:
        return None
    return line.split(":", 1)[0].strip()


def read_header(text: str) -> dict[str, str]:
    """The header's present model, effort and context values."""
    lines, end = _split(text)
    return {
        key: line.split(":", 1)[1].strip().strip("'\"")
        for line in lines[1:end]
        if (key := _key(line)) in KEYS
    }


def set_header(text: str, values: dict[str, str]) -> str:
    """``text`` with its model, effort and context set to ``values``; every other line stays where it was.

    The keys are written, in that order, where the first of them already sits, else after ``description``.
    """
    return set_fields(text, values)


def set_fields(text: str, values: dict[str, str]) -> str:
    """Replace owned top-level fields, preserving all other frontmatter and the body."""
    lines, end = _split(text)
    newline = "\r\n" if lines[0].endswith("\r\n") else "\n"
    kept: list[str] = []
    position = None
    for line in lines[1:end]:
        if _key(line) in values:
            position = len(kept) if position is None else position
            continue
        kept.append(line)
    if position is None:
        position = _after_description(kept)
    block = [f"{key}: {value}{newline}" for key, value in values.items()]
    return "".join([lines[0], *kept[:position], *block, *kept[position:], *lines[end:]])


def agent_tier(name: str, values: dict[str, str], headers: dict) -> str:
    """Resolve the recorded prompt cap to a supported CLI tier, never guess from its size."""
    model = headers.get("models", {}).get(values["model"])
    if not model:
        raise HeaderError(f"{name}: {values['model']} has no model capabilities; rebuild the scorecard")
    efforts = model.get("efforts") or ["none"]
    if values["effort"] not in efforts:
        raise HeaderError(f"{name}: {values['model']} does not support effort {values['effort']}")
    for tier, key in (("default", "default_cap"), ("long_context", "long_cap")):
        cap = model.get(key)
        if cap and context_size(cap) == values["context"]:
            return tier
    raise HeaderError(f"{name}: context {values['context']} is not a prompt cap for {values['model']}")


def agent_text(name: str, skill: str, values: dict[str, str], tier: str, text: str | None,
               relative_skill: str) -> str:
    """Create a skill carrier or update its sizing without replacing hand-written instructions."""
    if text is None:
        skill_lines, end = _split(skill)
        flags = "".join(line for line in skill_lines[1:end]
                        if _key(line) in ("disable-model-invocation", "user-invocable"))
        text = f"---\nname: {name}\ndescription: Run the /{name} skill.\n{flags}---\n"
    text = set_fields(text, {"name": name})
    text = set_fields(text, {"model": values["model"], "reasoning-effort": values["effort"]})
    lines, end = _split(text)
    newline = "\r\n" if lines[0].endswith("\r\n") else "\n"
    metadata = (
        f'  scorecard-context: "{values["context"]}"{newline}'
        f'  scorecard-context-tier: "{tier}"{newline}'
    )
    positions = [index for index in range(1, end) if _key(lines[index]) == "metadata"]
    if positions:
        start = positions[0]
        if len(positions) != 1 or lines[start].strip() != "metadata:":
            raise HeaderError(f"{name}: agent metadata must be a single block mapping")
        finish = start + 1
        while finish < end and _key(lines[finish]) is None:
            finish += 1
        kept = [line for line in lines[start + 1:finish]
                if line.strip().split(":", 1)[0] not in ("scorecard-context", "scorecard-context-tier")]
        text = "".join([*lines[:start + 1], *kept, metadata, *lines[finish:]])
    else:
        text = "".join([*lines[:end], f"metadata:{newline}{metadata}", *lines[end:]])
    block = newline.join([
        AGENT_START,
        f'Call the Skill tool with "{name}" immediately and follow its instructions.',
        f"If the skill is not installed, read and follow [SKILL.md](../../{relative_skill}) instead.",
        "",
        "For the recorded context, launch from the repository root with:",
        "",
        "```bash",
        f"copilot --agent {name} --model {values['model']} --reasoning-effort {values['effort']} "
        f"--context {tier} -i 'Invoke the /{name} skill.'",
        "```",
        "",
        "Context metadata is advisory; selecting this agent alone does not set the context tier.",
        AGENT_END,
    ])
    lines, end = _split(text)
    body = "".join(lines[end + 1:])
    if (body.count(AGENT_START), body.count(AGENT_END)) not in ((0, 0), (1, 1)):
        raise HeaderError(f"{name}: agent has an incomplete or duplicate model-scorecard block")
    if AGENT_START in body:
        if body.index(AGENT_END) < body.index(AGENT_START):
            raise HeaderError(f"{name}: agent model-scorecard markers are reversed")
        start, finish = body.index(AGENT_START), body.index(AGENT_END) + len(AGENT_END)
        body = body[:start] + block + body[finish:]
    else:
        body = newline + block + newline + body
    return "".join(lines[:end + 1]) + body


def _after_description(header: list[str]) -> int:
    """The index just past ``description`` and its continuation lines, else past ``name``, else the end."""
    for anchor in ("description", "name"):
        for index, line in enumerate(header):
            if _key(line) == anchor:
                index += 1
                while index < len(header) and header[index][:1].isspace():
                    index += 1
                return index
    return len(header)


def _read(path: Path) -> str:
    with path.open(encoding="utf-8", newline="") as stream:
        return stream.read()


def write_atomic(path: Path, text: str) -> None:
    """Replace ``path`` with ``text`` through a same-directory rename, keeping its permissions."""
    target = path.resolve()
    mode = target.stat().st_mode & 0o7777 if target.exists() else 0o644
    target.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def _describe(values: dict[str, str]) -> str:
    return " ".join(values[key] for key in KEYS if key in values) or "(no header)"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skills-repo", type=Path, default=DEFAULT_REPO, help="git-loopy-skills clone to edit")
    parser.add_argument("--headers", type=Path, help=f"skill picks; defaults to <skills-repo>/{HEADERS}")
    parser.add_argument("--decision", type=Path, help="set-task-models decision.json whose role profiles replace the picks")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="edit every skill or agent that differs")
    mode.add_argument("--check", action="store_true", help="exit 1 while any skill or agent differs")
    args = parser.parse_args(argv)

    repo = args.skills_repo.expanduser()
    try:
        headers = json.loads((args.headers or repo / HEADERS).expanduser().read_text(encoding="utf-8"))
        decision = json.loads(args.decision.expanduser().read_text(encoding="utf-8")) if args.decision else None
        wanted = targets(headers, decision)
    except (OSError, json.JSONDecodeError, KeyError, TypeError, HeaderError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    try:
        files = skill_files(repo)
    except (OSError, HeaderError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    if not files:
        print(f"error: no skills under {repo / 'skills'}", file=sys.stderr)
        return 2
    unmapped = sorted(set(files) - set(wanted))
    if unmapped:
        print(
            f"error: no role is mapped for {', '.join(unmapped)}; map each in model-scorecard's "
            "profiles.json `skills` and rebuild the scorecard",
            file=sys.stderr,
        )
        return 2
    for name in sorted(set(wanted) - set(files)):
        print(f"note: {name} has a pick but no SKILL.md here; skipped", file=sys.stderr)

    planned: list[tuple[Path, str]] = []
    agent_planned: list[tuple[Path, str]] = []
    for name, path in sorted(files.items()):
        try:
            text = _read(path)
            updated = set_header(text, wanted[name])
            agent_path = repo / ".github/agents" / f"{name}.agent.md"
            previous = _read(agent_path) if agent_path.exists() else None
            agent = agent_text(name, text, wanted[name], agent_tier(name, wanted[name], headers), previous,
                               path.relative_to(repo).as_posix())
        except (OSError, HeaderError, TypeError, ValueError) as error:
            print(f"error: {path}: {error}", file=sys.stderr)
            return 2
        if updated != text:
            planned.append((path, updated))
            print(f"{path.relative_to(repo)}: {_describe(read_header(text))} -> {_describe(wanted[name])}")
        if agent != previous:
            agent_planned.append((agent_path, agent))
            print(f"{agent_path.relative_to(repo)}: {'update' if previous is not None else 'create'}")
    if args.write:
        for path, updated in planned + agent_planned:
            try:
                write_atomic(path, updated)
            except OSError as error:
                print(f"error: {path}: {error}; earlier writes may have completed", file=sys.stderr)
                return 2
    print(f"{len(planned)} of {len(files)} skill headers {'updated' if args.write else 'differ'}")
    print(f"{len(agent_planned)} of {len(files)} skill agents {'updated' if args.write else 'differ'}")
    return 1 if args.check and (planned or agent_planned) else 0


if __name__ == "__main__":
    sys.exit(main())
