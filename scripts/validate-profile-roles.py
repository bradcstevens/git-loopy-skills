#!/usr/bin/env python3
"""Keep scorecard git-loopy roles aligned with the catalog's profile stems.

git-loopy's candidate proof owns profile content and the closed taxonomy. This
local gate only connects those profiles to the scorecard's model-fitness roles.
"""

import argparse
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    root = parser.parse_args().repo
    scorecard = root / "skills/model-scorecard/profiles.json"
    try:
        roles = json.loads(scorecard.read_text())["roles"]
        if not isinstance(roles, dict):
            raise ValueError("'roles' must be an object")
        actual = {name for name in roles if name.startswith("git-loopy:")}
        expected = {f"git-loopy:{path.stem}" for path in (root / "profiles").glob("*.md")}
    except (OSError, ValueError, KeyError) as exc:
        print(f"error: cannot compare scorecard/profile roles: {exc}", file=sys.stderr)
        return 1

    if actual != expected:
        missing = ", ".join(sorted(expected - actual)) or "none"
        extra = ", ".join(sorted(actual - expected)) or "none"
        print(
            f"error: scorecard/profile role mismatch; missing: {missing}; extra: {extra}",
            file=sys.stderr,
        )
        return 1
    print(f"ok: {len(expected)} scorecard git-loopy role(s) match profiles/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
