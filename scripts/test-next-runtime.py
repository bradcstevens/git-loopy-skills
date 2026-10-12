#!/usr/bin/env python3
"""Offline tests for skills/next/scripts/runtime.py: a route's runtime, read from its skill header."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "skills", "next", "scripts", "runtime.py")

CATALOG = {
    "schema_version": 1,
    "models": {
        "gpt-6.1-sol": {"efforts": ["low", "medium", "high"], "default_cap": 272000, "long_cap": 922000},
        "claude-opus-5.5": {"efforts": ["low", "medium", "high"], "default_cap": 200000, "long_cap": 1000000},
        "gpt-5-mini": {"efforts": [], "default_cap": 128000, "long_cap": None},
    },
    "skills": {
        "implement": {"model": "gpt-5-mini", "effort": "low", "context": "128K"},
        "bare": {"model": "gpt-5-mini", "effort": "low", "context": "128K"},
        "partial": {"model": "gpt-5-mini", "effort": "low", "context": "128K"},
        "malformed": {"model": "gpt-5-mini", "effort": "low", "context": "128K"},
        "unreadable": {"model": "gpt-5-mini", "effort": "low", "context": "128K"},
    },
}


def skill(root: str, name: str, header: str, body: str = "Do the thing.\n") -> None:
    directory = os.path.join(root, name)
    os.makedirs(directory)
    with open(os.path.join(directory, "SKILL.md"), "w", encoding="utf-8") as handle:
        handle.write(f"---\nname: {name}\ndescription: A test skill.\n{header}---\n\n{body}")


def header(model: str, effort: str, context: str) -> str:
    return f"model: {model}\neffort: {effort}\ncontext: {context}\n"


class RuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.skills = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.skills, True)
        skill(self.skills, "implement", header("gpt-6.1-sol", "medium", "272K"))
        skill(self.skills, "code-review", header("claude-opus-5.5", "medium", "1M"))
        skill(self.skills, "research", 'model: "gpt-6.1-sol"\neffort: medium\ncontext: 922K\n')
        skill(self.skills, "summarize", header("gpt-5-mini", "low", "128K"))
        skill(self.skills, "unlisted", header("future-model-1", "high", "400K"))
        skill(self.skills, "unreadable", header("gpt-6.1-sol", "medium", "272K"))
        skill(self.skills, "invalid-no-fallback", header("gpt-6.1-sol", "extreme", "272K"))
        # A key in the body is prose, not a header.
        skill(self.skills, "bare", "", body="model: gpt-6.1-sol\neffort: medium\ncontext: 272K\n")
        skill(self.skills, "unconfigured", "")
        skill(self.skills, "partial", "model: gpt-6.1-sol\n")
        skill(self.skills, "malformed", header("gpt-6.1-sol", "extreme", "272K"))
        catalog_dir = os.path.join(self.skills, "model-scorecard", "references")
        os.makedirs(catalog_dir)
        self.catalog = os.path.join(catalog_dir, "skill-headers.json")
        with open(self.catalog, "w", encoding="utf-8") as handle:
            json.dump(CATALOG, handle)

    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True, check=False
        )

    def resolve(self, route: str, *args: str, status: int = 0) -> dict:
        result = self.run_script(route, "--skills-dir", self.skills, *args)
        self.assertEqual(result.returncode, status, result.stderr)
        return json.loads(result.stdout)

    def test_names_the_routed_skills_header_and_its_tier(self) -> None:
        self.assertEqual(
            self.resolve("/implement"),
            {
                "route": "/implement",
                "model": "gpt-6.1-sol",
                "effort": "medium",
                "context": "272K",
                "tier": "default",
                "tier_source": "catalog",
                "runtime_source": "skill-header",
                "runtime": "model gpt-6.1-sol, effort medium, context 272K (default)",
            },
        )

    def test_a_window_above_the_models_default_cap_is_long_context(self) -> None:
        review = self.resolve("/code-review")
        self.assertEqual((review["context"], review["tier"]), ("1M", "long_context"))
        self.assertEqual(review["runtime"], "model claude-opus-5.5, effort medium, context 1M (long_context)")
        research = self.resolve("/research")
        self.assertEqual((research["model"], research["tier"]), ("gpt-6.1-sol", "long_context"))

    def test_a_route_is_the_skill_name_with_or_without_its_slash(self) -> None:
        self.assertEqual(self.resolve("implement"), self.resolve("/implement"))

    def test_a_model_without_a_long_tier_stays_default(self) -> None:
        self.assertEqual(self.resolve("/summarize")["tier"], "default")

    def test_without_the_catalog_the_tier_falls_back_to_default(self) -> None:
        os.remove(self.catalog)
        review = self.resolve("/code-review")
        self.assertEqual((review["tier"], review["tier_source"]), ("default", "fallback"))
        unlisted = self.resolve("/unlisted", "--catalog", os.path.join(self.skills, "absent.json"))
        self.assertEqual((unlisted["tier"], unlisted["tier_source"]), ("default", "fallback"))

    def test_a_model_missing_from_the_catalog_falls_back_to_default(self) -> None:
        unlisted = self.resolve("/unlisted")
        self.assertEqual((unlisted["context"], unlisted["tier"], unlisted["tier_source"]), ("400K", "default", "fallback"))

    def test_an_explicit_catalog_overrides_the_co_installed_one(self) -> None:
        other = os.path.join(self.skills, "other-catalog.json")
        with open(other, "w", encoding="utf-8") as handle:
            json.dump({"models": {"gpt-6.1-sol": {"default_cap": 128000, "long_cap": 272000}}}, handle)
        self.assertEqual(self.resolve("/implement", "--catalog", other)["tier"], "long_context")

    def test_a_malformed_catalog_falls_back_to_default(self) -> None:
        malformed = os.path.join(self.skills, "malformed-catalog.json")
        for catalog in ('{"models": {"gpt-6.1-sol": {"default_cap": "272000"}}}', '{"models": []}', "[1]", "{"):
            with self.subTest(catalog=catalog):
                with open(malformed, "w", encoding="utf-8") as handle:
                    handle.write(catalog)
                implement = self.resolve("/implement", "--catalog", malformed)
                self.assertEqual((implement["tier"], implement["tier_source"]), ("default", "fallback"))

    def test_a_route_with_no_skill_runs_on_the_current_session(self) -> None:
        self.assertEqual(
            self.resolve("/compact"),
            {
                "route": "/compact",
                "model": None,
                "effort": None,
                "context": None,
                "tier": None,
                "tier_source": None,
                "runtime_source": None,
                "runtime": "current session",
                "reason": "no-skill",
            },
        )

    def test_missing_header_runtime_uses_the_model_scorecard_fallback(self) -> None:
        bare = self.resolve("/bare")
        self.assertEqual(
            (bare["model"], bare["effort"], bare["context"], bare["runtime_source"]),
            ("gpt-5-mini", "low", "128K", "model-scorecard"),
        )
        self.assertEqual(bare["runtime"], "model gpt-5-mini, effort low, context 128K (default)")

    def test_skill_without_header_or_fallback_runs_on_the_current_session(self) -> None:
        result = self.resolve("/unconfigured")
        self.assertEqual((result["runtime"], result["reason"]), ("current session", "no-header"))

    def test_partial_and_malformed_headers_use_the_model_scorecard_fallback(self) -> None:
        for route in ("/partial", "/malformed"):
            with self.subTest(route=route):
                result = self.resolve(route)
                self.assertEqual((result["runtime_source"], result["model"]), ("model-scorecard", "gpt-5-mini"))

    def test_missing_skill_file_uses_the_model_scorecard_fallback(self) -> None:
        os.remove(os.path.join(self.skills, "unreadable", "SKILL.md"))
        result = self.resolve("/unreadable")
        self.assertEqual((result["runtime_source"], result["model"]), ("model-scorecard", "gpt-5-mini"))

    def test_valid_skill_header_takes_precedence_over_scorecard_fallback(self) -> None:
        result = self.resolve("/implement")
        self.assertEqual((result["runtime_source"], result["model"]), ("skill-header", "gpt-6.1-sol"))

    def test_invalid_header_without_a_valid_fallback_fails(self) -> None:
        result = self.resolve("/invalid-no-fallback", status=1)
        self.assertEqual((result["runtime"], result["reason"]), ("current session", "invalid-header"))
        self.assertTrue(result["error"])

    def test_rejects_a_route_that_is_not_a_skill_name(self) -> None:
        for route in ("../implement", "/Implement", "implement/x", "/", ""):
            with self.subTest(route=route):
                result = self.run_script(route, "--skills-dir", self.skills)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertEqual(result.stdout, "")

    def test_every_skill_in_this_repository_resolves_from_the_skills_beside_next(self) -> None:
        skills_root = os.path.join(REPO, "skills")
        names = sorted(
            name for name in os.listdir(skills_root)
            if os.path.isfile(os.path.join(skills_root, name, "SKILL.md"))
        )
        self.assertIn("next", names)
        for name in names:
            with self.subTest(skill=name):
                result = self.run_script(f"/{name}")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                resolved = json.loads(result.stdout)
                self.assertEqual(resolved["route"], f"/{name}")
                if resolved["model"] is None:
                    self.assertEqual(resolved["reason"], "no-header")
                else:
                    self.assertIn(resolved["tier"], ("default", "long_context"))


if __name__ == "__main__":
    unittest.main()
