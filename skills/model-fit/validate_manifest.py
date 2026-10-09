#!/usr/bin/env python3
"""Validate a model-fit decision manifest without modifying its targets."""

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BUILTINS = {
    "explore", "task", "general-purpose", "rubber-duck",
    "code-review", "research", "security-review",
}
TASK_TYPES = {"planning", "review", "implementation", "test", "docs", "chore", "bugfix"}
SOURCE_IDS = {"aa", "huggingface", "arena", "benchlm", "llm-stats"}
CONTEXTS = {"default", "long_context"}
SHARED_ROLES = (
    {"copilot:general-purpose", "git_loopy:implementation"},
    {"copilot:code-review", "git_loopy:review"},
)


class InvalidManifest(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidManifest(message)


def object_value(value, label):
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def text(value, label):
    require(isinstance(value, str) and bool(value.strip()), f"{label} must be nonempty text")
    return value


def strings(value, label, *, empty=False):
    require(isinstance(value, list), f"{label} must be an array")
    require(empty or bool(value), f"{label} must not be empty")
    for item in value:
        text(item, label)
    require(len(value) == len(set(value)), f"{label} contains duplicates")
    return set(value)


def timestamp(value, label):
    value = text(value, label)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise InvalidManifest(f"{label} must be an ISO timestamp") from error
    require(parsed.tzinfo is not None, f"{label} must include a timezone")
    return parsed


def fresh(value, label, now):
    observed = timestamp(value, label)
    require(observed <= now + timedelta(minutes=5), f"{label} is in the future")
    require(now - observed <= timedelta(hours=24), f"{label} is stale; refresh the observation")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def invalid_constant(value):
    raise InvalidManifest(f"non-finite JSON number: {value}")


def validate(manifest, now):
    root = object_value(manifest, "manifest")
    require(type(root.get("schema_version")) is int and root["schema_version"] == 1,
            "schema_version must be 1")
    inventory = object_value(root.get("inventory"), "inventory")
    text(inventory.get("source"), "inventory.source")
    fresh(inventory.get("observed_at"), "inventory.observed_at", now)
    builtins = strings(inventory.get("builtin_agents"), "inventory.builtin_agents")
    require(BUILTINS <= builtins, "inventory is missing a required built-in")
    models = object_value(inventory.get("models"), "inventory.models")
    eligible = set()
    for model, raw in models.items():
        text(model, "model ID")
        info = object_value(raw, f"models.{model}")
        require(type(info.get("selectable")) is bool, f"{model}.selectable must be boolean")
        strings(info.get("efforts"), f"{model}.efforts", empty=True)
        tiers = strings(info.get("context_tiers"), f"{model}.context_tiers", empty=True)
        require(tiers <= CONTEXTS, f"{model} has unknown context tiers")
        if info["selectable"] and model != "auto":
            require(bool(tiers), f"{model} is missing observed context capabilities")
            eligible.add(model)
    require(bool(eligible), "inventory has no selectable fixed models")

    sources = object_value(root.get("sources"), "sources")
    require(SOURCE_IDS <= sources.keys(), "attempt all five required source surfaces")
    usable_sources = set()
    for source, raw in sources.items():
        info = object_value(raw, f"sources.{source}")
        url = text(info.get("url"), f"{source}.url")
        require(url.startswith(("https://", "http://")), f"{source}.url must be a web URL")
        text(info.get("notes"), f"{source}.notes")
        fresh(info.get("accessed_at"), f"{source}.accessed_at", now)
        status = text(info.get("status"), f"{source}.status")
        require(status in {"ok", "partial", "blocked"}, f"{source}: invalid status")
        if status != "blocked":
            usable_sources.add(source)

    evidence = object_value(root.get("evidence"), "evidence")
    covered = set()
    for evidence_id, raw in evidence.items():
        text(evidence_id, "evidence ID")
        entry = object_value(raw, f"evidence.{evidence_id}")
        model = text(entry.get("model"), f"{evidence_id}.model")
        source = text(entry.get("source"), f"{evidence_id}.source")
        require(model in eligible, f"{evidence_id} evaluates a model outside the selectable roster")
        require(source in usable_sources, f"{evidence_id} cites an unknown or blocked source")
        text(entry.get("finding"), f"{evidence_id}.finding")
        covered.add(model)
    gaps = object_value(root.get("coverage_gaps"), "coverage_gaps")
    for model, reason in gaps.items():
        require(model in eligible, f"coverage gap references a nonselectable model: {model}")
        text(reason, f"coverage_gaps.{model}")
    require(eligible <= covered | gaps.keys(), "some selectable models have neither evidence nor a gap")

    profiles = object_value(root.get("profiles"), "profiles")
    require(bool(profiles), "profiles must not be empty")
    for profile_id, raw in profiles.items():
        text(profile_id, "profile ID")
        profile = object_value(raw, f"profiles.{profile_id}")
        model = text(profile.get("model"), f"{profile_id}.model")
        require(model in eligible, f"{profile_id} selects an unavailable or unverified model")
        require("effort" in profile, f"{profile_id}.effort is required (null for no control)")
        effort = profile["effort"]
        allowed = models[model]["efforts"]
        require((isinstance(effort, str) and effort in allowed) if allowed else effort is None,
                f"{profile_id} selects unsupported effort")
        context = text(profile.get("context"), f"{profile_id}.context")
        require(context in models[model]["context_tiers"], f"{profile_id} selects unsupported context")
        citations = strings(profile.get("evidence"), f"{profile_id}.evidence")
        for citation in citations:
            require(citation in evidence, f"{profile_id} cites unknown evidence: {citation}")
        require(any(evidence[citation]["model"] == model for citation in citations),
                f"{profile_id} lacks evidence for its exact model")
        text(profile.get("rationale"), f"{profile_id}.rationale")
        confidence = text(profile.get("confidence"), f"{profile_id}.confidence")
        require(confidence in {"high", "medium", "low"},
                f"{profile_id} has invalid confidence")

    roles = {}
    for namespace, expected in (("copilot", builtins), ("git_loopy", TASK_TYPES)):
        bindings = object_value(root.get(namespace), namespace)
        require(set(bindings) == expected, f"{namespace} must bind every in-scope role, and only those roles")
        for role, profile_id in bindings.items():
            text(profile_id, f"{namespace}.{role}")
            require(profile_id in profiles, f"{namespace}.{role} references an unknown profile")
            roles[f"{namespace}:{role}"] = profile_id
    require(set(roles.values()) == set(profiles), "profiles contains unused decisions")

    groups = root.get("equivalence_groups")
    require(isinstance(groups, list), "equivalence_groups must be an array")
    recorded = []
    for group in groups:
        members = strings(group, "equivalence group")
        require(len(members) >= 2, "equivalence groups need at least two roles")
        require(members <= roles.keys(), "equivalence group contains an unknown role")
        require(len({roles[role] for role in members}) == 1,
                "equivalent roles must reference one shared profile")
        recorded.append(members)
    for required in SHARED_ROLES:
        require(any(required <= group for group in recorded), "a required shared role group is missing")
    return {"status": "valid", "profiles": len(profiles),
            "copilot_builtins": len(builtins), "git_loopy_task_types": len(TASK_TYPES)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--as-of", help="authoritative current ISO timestamp; defaults to the system clock")
    args = parser.parse_args()
    try:
        now = timestamp(args.as_of, "--as-of") if args.as_of else datetime.now(timezone.utc)
        with args.manifest.open(encoding="utf-8") as stream:
            manifest = json.load(stream, object_pairs_hook=unique_object,
                                 parse_constant=invalid_constant)
        result = validate(manifest, now)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"model-fit: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
