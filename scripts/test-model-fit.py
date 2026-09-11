#!/usr/bin/env python3
"""Offline contract tests for the co-installed model-fit manifest guard."""

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "skills/model-fit/validate_manifest.py"
SPEC = importlib.util.spec_from_file_location("model_fit", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)
NOW = datetime(2026, 9, 10, 20, 0, tzinfo=timezone.utc)
OBSERVED = "2026-09-10T19:00:00Z"


def manifest():
    return {
        "schema_version": 1,
        "inventory": {
            "observed_at": OBSERVED,
            "source": "Test fixture: authenticated picker and capability observation",
            "builtin_agents": sorted(guard.BUILTINS),
            "models": {
                "fixture-model": {
                    "selectable": True,
                    "efforts": ["low", "high"],
                    "context_tiers": ["default", "long_context"],
                },
                "unavailable-model": {
                    "selectable": False, "efforts": [], "context_tiers": [],
                },
            },
        },
        "sources": {
            source: {
                "url": f"https://example.com/{source}",
                "accessed_at": OBSERVED,
                "status": "ok",
                "notes": "Synthetic test data, not research or a recommended model.",
            }
            for source in guard.SOURCE_IDS
        },
        "evidence": {
            "terminal": {
                "model": "fixture-model", "source": "aa",
                "finding": "Synthetic measured component at high effort in a named harness.",
            },
        },
        "coverage_gaps": {},
        "profiles": {
            "shared": {
                "model": "fixture-model", "effort": "high", "context": "default",
                "evidence": ["terminal"], "rationale": "Synthetic contract-test choice.",
                "confidence": "medium",
            },
        },
        "copilot": {role: "shared" for role in guard.BUILTINS},
        "git_loopy": {role: "shared" for role in guard.TASK_TYPES},
        "equivalence_groups": [sorted(group) for group in guard.SHARED_ROLES],
    }


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.data = manifest()

    def reject(self, message):
        with self.assertRaisesRegex(guard.InvalidManifest, message):
            guard.validate(self.data, NOW)

    def test_complete_manifest_and_no_mutation(self):
        before = copy.deepcopy(self.data)
        self.assertEqual(
            guard.validate(self.data, NOW),
            {"status": "valid", "profiles": 1, "copilot_builtins": 7,
             "git_loopy_task_types": 7},
        )
        self.assertEqual(before, self.data)

    def test_unavailable_selection(self):
        self.data["profiles"]["shared"]["model"] = "unavailable-model"
        self.reject("unavailable or unverified")

    def test_invented_model(self):
        self.data["profiles"]["shared"]["model"] = "guessed-alias"
        self.reject("unavailable or unverified")

    def test_auto_is_not_a_fixed_candidate(self):
        self.data["inventory"]["models"]["auto"] = {
            "selectable": True, "efforts": [], "context_tiers": [],
        }
        self.data["profiles"]["shared"]["model"] = "auto"
        self.reject("unavailable or unverified")

    def test_unsupported_effort(self):
        self.data["profiles"]["shared"]["effort"] = "max"
        self.reject("unsupported effort")

    def test_effort_must_be_explicit(self):
        del self.data["profiles"]["shared"]["effort"]
        self.reject("effort is required")

    def test_no_effort_control_uses_null(self):
        self.data["inventory"]["models"]["fixture-model"]["efforts"] = []
        self.data["profiles"]["shared"]["effort"] = None
        guard.validate(self.data, NOW)
        self.data["profiles"]["shared"]["effort"] = "none"
        self.reject("unsupported effort")

    def test_no_inherited_context(self):
        self.data["profiles"]["shared"]["context"] = "inherit"
        self.reject("unsupported context")

    def test_context_is_model_specific(self):
        self.data["inventory"]["models"]["fixture-model"]["context_tiers"] = ["default"]
        self.data["profiles"]["shared"]["context"] = "long_context"
        self.reject("unsupported context")

    def test_missing_inventory_builtin(self):
        self.data["inventory"]["builtin_agents"].remove("security-review")
        self.reject("missing a required built-in")

    def test_new_builtin_must_be_bound(self):
        self.data["inventory"]["builtin_agents"].append("future-built-in")
        self.reject("every in-scope role")
        self.data["copilot"]["future-built-in"] = "shared"
        self.assertEqual(guard.validate(self.data, NOW)["copilot_builtins"], 8)

    def test_custom_agent_is_out_of_scope(self):
        self.data["copilot"]["my-custom-agent"] = "shared"
        self.reject("every in-scope role")

    def test_each_git_loopy_task_is_required(self):
        for role in guard.TASK_TYPES:
            with self.subTest(role=role):
                self.data = manifest()
                del self.data["git_loopy"][role]
                self.reject("every in-scope role")

    def test_equivalent_roles_share_one_profile(self):
        self.data["profiles"]["other"] = copy.deepcopy(self.data["profiles"]["shared"])
        self.data["git_loopy"]["review"] = "other"
        self.reject("one shared profile")

    def test_shared_groups_are_mandatory(self):
        self.data["equivalence_groups"] = []
        self.reject("shared role group is missing")

    def test_unknown_equivalent_role(self):
        self.data["equivalence_groups"].append(["copilot:task", "git_loopy:typo"])
        self.reject("unknown role")

    def test_test_authoring_can_differ_from_command_execution(self):
        self.data["profiles"]["commands"] = copy.deepcopy(self.data["profiles"]["shared"])
        self.data["profiles"]["commands"]["effort"] = "low"
        self.data["copilot"]["task"] = "commands"
        guard.validate(self.data, NOW)

    def test_all_selectable_candidates_need_coverage(self):
        self.data["inventory"]["models"]["unmeasured"] = {
            "selectable": True, "efforts": ["low"], "context_tiers": ["default"],
        }
        self.reject("neither evidence nor a gap")
        self.data["coverage_gaps"]["unmeasured"] = "No exact-model evaluation recovered."
        guard.validate(self.data, NOW)

    def test_evidence_must_stay_within_license(self):
        self.data["evidence"]["terminal"]["model"] = "unavailable-model"
        self.reject("outside the selectable roster")

    def test_evidence_must_match_selected_model(self):
        self.data["inventory"]["models"]["other"] = {
            "selectable": True, "efforts": ["high"], "context_tiers": ["default"],
        }
        self.data["coverage_gaps"]["fixture-model"] = "No result."
        self.data["evidence"]["terminal"]["model"] = "other"
        self.reject("evidence for its exact model")

    def test_all_source_attempts_required(self):
        del self.data["sources"]["huggingface"]
        self.reject("all five")

    def test_blocked_source_is_recorded_but_not_evidence(self):
        self.data["sources"]["arena"]["status"] = "blocked"
        guard.validate(self.data, NOW)
        self.data["sources"]["aa"]["status"] = "blocked"
        self.reject("unknown or blocked")

    def test_source_status_must_be_text(self):
        self.data["sources"]["aa"]["status"] = {}
        self.reject("status must be nonempty text")

    def test_stale_inventory(self):
        self.data["inventory"]["observed_at"] = "2026-09-09T19:00:00Z"
        self.reject("stale")

    def test_source_access_must_be_current(self):
        self.data["sources"]["aa"]["accessed_at"] = "2026-09-08T19:00:00Z"
        self.reject("stale")

    def test_future_inventory(self):
        self.data["inventory"]["observed_at"] = "2026-09-11T19:00:00Z"
        self.reject("future")

    def test_timestamp_timezone_is_required(self):
        self.data["inventory"]["observed_at"] = "2026-09-10T19:00:00"
        self.reject("timezone")

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaisesRegex(guard.InvalidManifest, "duplicate JSON key"):
            json.loads('{"model": "a", "model": "b"}', object_pairs_hook=guard.unique_object)

    def test_nonfinite_json_rejected(self):
        with self.assertRaisesRegex(guard.InvalidManifest, "non-finite"):
            json.loads('{"score": NaN}', parse_constant=guard.invalid_constant)

    def test_cli_is_read_only_and_errors_are_actionable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decision.json"
            path.write_text(json.dumps(self.data), encoding="utf-8")
            before = path.read_bytes()
            command = [sys.executable, str(SCRIPT), str(path), "--as-of", NOW.isoformat()]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["status"], "valid")
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(list(Path(directory).iterdir()), [path])
            path.write_text("{", encoding="utf-8")
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("model-fit:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
