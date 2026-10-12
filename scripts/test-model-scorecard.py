#!/usr/bin/env python3
"""Offline contract tests for the model-scorecard skill's scripts and profiles."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SKILL = REPO / "skills/model-scorecard"


def load(name):
    spec = importlib.util.spec_from_file_location(name, SKILL / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


capture = load("capture_leaderboard")
scorer = load("score")
measure = load("measure_context")
PROFILES = json.loads((SKILL / "profiles.json").read_text())


def row(short_name, ii, *, creator="Vendor A", ttfa=5.0, e2e=10.0, tps=100.0, cost=0.5, out_price=10.0, **extra):
    return {
        "shortName": short_name, "deprecated": False, "modelCreatorName": creator,
        "intelligenceIndex": ii, "intelligenceIndexIsEstimated": False,
        "medianTimeToFirstAnswerTokenSeconds": ttfa, "medianTimeToFirstTokenSeconds": ttfa,
        "medianEndToEndResponseTimeSeconds": e2e, "medianOutputTokensPerSecond": tps,
        "intelligenceIndexCostPerTask": cost, "price1mOutputTokens": out_price, **extra,
    }


def listing(*models):
    return {"models": [
        {"id": model_id, "efforts": efforts, "default_cap": 200000, "long_cap": 900000, "policy": policy}
        for model_id, efforts, policy in models
    ]}


ROLE = {"harness": "copilot-cli", "band": [46, 52], "benchmarks": ["scicode"], "context": "fit", "working_set_k": 100, "why": "w"}


def tracked_skills():
    """Skill directory names in this repo, minus git-ignored local-only skills."""
    names = set()
    for skill_md in (REPO / "skills").rglob("SKILL.md"):
        relative = f"{skill_md.parent.relative_to(REPO).as_posix()}/"
        ignored = subprocess.run(["git", "-C", str(REPO), "check-ignore", "-q", relative], capture_output=True)
        if "node_modules" not in skill_md.parts and ignored.returncode != 0:
            names.add(skill_md.parent.name)
    return names


def synthetic_picks():
    pool = scorer.build_candidates([row("Alpha 1 (high)", 53), row("Beta 2 (high)", 47, creator="Vendor B"),
                                    row("Gamma 3 (low)", 35, creator="Vendor C")],
                                   listing(("alpha-1", ["high"], "enabled"), ("beta-2", ["high"], "enabled"),
                                           ("gamma-3", ["low"], "enabled")))
    return scorer.recommend(PROFILES, {"copilot-cli": pool, "git-loopy": pool}, {"roles": {}}, "alpha-1")


class WeightsAndNames(unittest.TestCase):
    def test_rank_order_centroid_weights(self):
        weights = scorer.roc_weights(6)
        self.assertAlmostEqual(sum(weights), 1.0)
        self.assertEqual([round(100 * w, 1) for w in weights], [40.8, 24.2, 15.8, 10.3, 6.1, 2.8])

    def test_parse_variant(self):
        self.assertEqual(scorer.parse_variant("Claude Opus 5.5 (high with fallback)"), ("Claude Opus 5.5", "high"))
        self.assertEqual(scorer.parse_variant("GPT-6.1 Sol (xhigh)"), ("GPT-6.1 Sol", "xhigh"))
        self.assertEqual(scorer.parse_variant("GPT-5.4 (non-reasoning)"), ("GPT-5.4", "none"))
        self.assertEqual(scorer.parse_variant("Grok 4.7"), ("Grok 4.7", None))
        self.assertIsNone(scorer.parse_variant("GPT-6 Sol (Daybreak Blue, max)"))
        self.assertIsNone(scorer.parse_variant("GPT-5.5 Instant (June 2026)"))
        self.assertEqual(scorer.copilot_id("GPT-5.4 mini"), "gpt-5.4-mini")


class Capture(unittest.TestCase):
    MODELS = [row("Model A (high)", 57.6, cost=5.98, tps=99.0, ttfa=704.18, e2e=709.24),
              row("Model B (low)", 41.2, cost=None, tps=None, ttfa=None, e2e=None)]

    def page(self):
        payload = json.dumps({"rows": [{"slug": "a", **self.MODELS[0], "x": "$undefined"}]})
        half = len(payload) // 2
        chunks = [json.dumps(payload[:half])[1:-1], json.dumps(payload[half:])[1:-1]]
        return "".join(f'<script>self.__next_f.push([1,"{c}"])</script>' for c in chunks)

    def test_parse_models_decodes_flight_payload(self):
        models = capture.parse_models(self.page())
        self.assertEqual(models[0]["shortName"], "Model A (high)")
        self.assertIsNone(models[0]["x"])

    def test_dollar_numbers_become_floats(self):
        self.assertEqual(capture._clean("$5.98"), 5.98)
        self.assertEqual(capture._clean("$$0.32"), 0.32)
        self.assertEqual(capture._clean("$D2026-10-10"), "$D2026-10-10")

    def test_resolve_follows_nested_iframes(self):
        pages = {"space": '<iframe src="static">', "static": '<iframe src="embed">', "embed": self.page()}
        self.assertEqual(capture.resolve_dataset_page("space", get=pages.__getitem__)[0], "embed")

    def test_cross_check_matches_and_conflicts(self):
        seen = "Model A (high)\n1M\nVendor A\n58\n$5.98\n99\n704.18\n709.24\nModel C\n"
        result = capture.cross_check(self.MODELS, seen)
        self.assertEqual((result["matched"], result["conflicts"]), (["Model A (high)"], []))
        wrong = "Model A (high)\n1M\nVendor A\n12\n$1.00\n5\n1.00\n2.00\n"
        self.assertEqual(len(capture.cross_check(self.MODELS, wrong)["conflicts"]), 1)


class Scoring(unittest.TestCase):
    def pool(self, rows, models):
        return scorer.build_candidates(rows, listing(*models))

    def test_build_candidates_keeps_only_selectable_variants(self):
        rows = [row("Alpha 1 (high)", 50), row("Alpha 1 (max)", 52), row("Beta 2 (low)", 40),
                {**row("Gamma 3 (high)", 49), "deprecated": True}, row("Delta 4 (high)", 49)]
        pool = self.pool(rows, [("alpha-1", ["low", "high"], "enabled"), ("beta-2", ["low"], None),
                                ("gamma-3", ["high"], "enabled"), ("delta-4", ["high"], "disabled")])
        self.assertEqual(sorted((c["id"], c["effort"]) for c in pool), [("alpha-1", "high"), ("beta-2", "low")])

    def test_in_band_beats_below_floor_at_equal_speed(self):
        pool = self.pool([row("Alpha 1 (high)", 48), row("Beta 2 (high)", 40)],
                         [("alpha-1", ["high"], "enabled"), ("beta-2", ["high"], "enabled")])
        ranked = scorer.rank(ROLE, pool, scorer.build_scales(pool), [f["id"] for f in PROFILES["fields"]], None)
        self.assertEqual([c["id"] for c in ranked], ["alpha-1", "beta-2"])
        self.assertTrue(ranked[0]["in_band"] and not ranked[1]["in_band"])

    def test_faster_wins_inside_band(self):
        pool = self.pool([row("Alpha 1 (high)", 48, ttfa=60, e2e=70), row("Beta 2 (high)", 48, ttfa=5, e2e=10)],
                         [("alpha-1", ["high"], "enabled"), ("beta-2", ["high"], "enabled")])
        ranked = scorer.rank(ROLE, pool, scorer.build_scales(pool), [f["id"] for f in PROFILES["fields"]], None)
        self.assertEqual(ranked[0]["id"], "beta-2")
        self.assertTrue(all(1 <= c["score"] <= 100 for c in ranked))

    def test_rank_excludes_max_effort_and_blocked_vendor(self):
        pool = self.pool([row("Alpha 1 (max)", 50), row("Beta 2 (high)", 50, creator="Vendor B"), row("Gamma 3 (high)", 49)],
                         [("alpha-1", ["max"], "enabled"), ("beta-2", ["high"], "enabled"), ("gamma-3", ["high"], "enabled")])
        role = {**ROLE, "exclude_efforts": ["max"]}
        ranked = scorer.rank(role, pool, scorer.build_scales(pool), [f["id"] for f in PROFILES["fields"]], "Vendor B")
        self.assertEqual([c["id"] for c in ranked], ["gamma-3"])

    def test_context_fits_working_set_to_tier(self):
        pick = {"default_cap": 200000, "long_cap": 900000}
        big = {"n": 10, "p95": 180000}
        self.assertEqual(scorer.context_choice(ROLE, pick, big, 0.8)["tier"], "long_context")
        self.assertEqual(scorer.context_choice(ROLE, pick, {"n": 10, "p95": 150000}, 0.8)["tier"], "default")
        self.assertEqual(scorer.context_choice({**ROLE, "context": "default"}, pick, big, 0.8)["tier"], "default")
        estimate = scorer.context_choice(ROLE, pick, {"n": 2, "p95": 999999}, 0.8)
        self.assertEqual((estimate["need"], estimate["source"]), (100000, "profile estimate"))

    def test_context_size_writes_whole_millions_as_m(self):
        sizes = {1_000_000: "1M", 2_000_000: "2M", 922_000: "922K", 272_000: "272K", 1_048_576: "1049K"}
        self.assertEqual({tokens: scorer.context_size(tokens) for tokens in sizes}, sizes)


class SkillWorkingSets(unittest.TestCase):
    EVENTS = [
        {"type": "skill.invoked", "data": {"name": "next"}},
        {"type": "user.message", "data": {"content": "/next"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 50_000}}},
        {"type": "subagent.started", "agentId": "a1", "data": {"agentName": "explore"}},
        {"type": "session.usage_record", "agentId": "a1", "data": {"usage": {"inputTokens": 90_000}}},
        {"type": "user.message", "data": {"content": "go ahead"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 80_000}}},
        {"type": "user.message", "data": {"content": "/model gpt-6.1-sol"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 85_000}}},
        {"type": "skill.invoked", "data": {"name": "wayfinder"}},
        {"type": "user.message", "data": {"content": "/wayfinder continue the map"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 120_000}}},
        {"type": "skill.invoked", "data": {"name": "jev-ultrafast"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 150_000}}},
        {"type": "skill.invoked", "data": {"name": "model-scorecard"}},
        {"type": "user.message", "data": {"content": "per the results of /model-scorecard, which model?"}},
        {"type": "session.usage_record", "data": {"usage": {"inputTokens": 170_000}}},
    ]

    def test_a_run_starts_at_a_confirmed_slash_command_and_ends_at_the_next(self):
        with tempfile.TemporaryDirectory() as home:
            session = Path(home) / "session-state" / "s1"
            session.mkdir(parents=True)
            (session / "events.jsonl").write_text("".join(json.dumps(e) + "\n" for e in self.EVENTS))
            peaks, skill_peaks, _ = measure.scan_copilot(Path(home), 10)
        self.assertEqual(dict(skill_peaks), {"next": [85_000], "wayfinder": [170_000]})
        self.assertEqual(dict(peaks), {"copilot:explore": [90_000]})


class Skills(unittest.TestCase):
    LISTING = listing(("alpha-1", ["high"], "enabled"), ("beta-2", ["high"], "enabled"), ("gamma-3", ["low"], "enabled"))

    def test_a_skill_inherits_its_role_pick_and_fits_its_own_runs(self):
        picks = synthetic_picks()
        profiles = {**PROFILES, "skills": {"plan": "git-loopy:planning", "route": "copilot:explore", "big": "copilot:explore"}}
        working_sets = {"roles": {}, "compaction": {"ratio": 0.8}, "skills": {
            "big": {"n": 6, "p50": 1, "p95": 190_000, "max": 1},
            "route": {"n": 2, "p50": 1, "p95": 999_999, "max": 1},
        }}
        skills = scorer.recommend_skills(profiles, picks, working_sets, self.LISTING)
        for name, role_id in profiles["skills"].items():
            self.assertEqual((skills[name]["model"], skills[name]["effort"]),
                             (picks[role_id]["pick"]["id"], picks[role_id]["pick"]["effort"]))
        self.assertEqual((skills["plan"]["need"], skills["plan"]["context"]), (170_000, "900K"))
        self.assertEqual((skills["route"]["need"], skills["route"]["context"]), (82_000, "200K"))
        self.assertEqual((skills["big"]["context"], skills["big"]["need_source"]), ("900K", "p95 of 6 /big runs"))

    def test_an_unknown_role_is_refused(self):
        with self.assertRaises(SystemExit):
            scorer.recommend_skills({**PROFILES, "skills": {"x": "copilot:nope"}}, synthetic_picks(), {}, self.LISTING)

    def test_now_reads_each_skill_header(self):
        with tempfile.TemporaryDirectory() as root:
            for name, header in {"a": "model: m\neffort: low\ncontext: 1M\n", "b": ""}.items():
                (Path(root) / name).mkdir()
                (Path(root) / name / "SKILL.md").write_text(f"---\nname: {name}\ndescription: d\n{header}---\nmodel: body\n")
            self.assertEqual(scorer.current_headers(Path(root)), {"a": "m low 1M", "b": "—"})


class ProfilesAndRender(unittest.TestCase):
    def test_profiles_cover_every_role_once(self):
        roles = PROFILES["roles"]
        builtins = {f"copilot:{name}" for name in measure.BUILTINS}
        task_types = {f"git-loopy:{key}" for key in ("planning", "review", "implementation", "test", "docs", "chore", "bugfix")}
        self.assertEqual(set(roles), builtins | task_types)
        self.assertEqual(PROFILES["fields"][0]["id"], "success")
        for role_id, role in roles.items():
            self.assertLess(role["band"][0], role["band"][1], role_id)
            self.assertIn(role["harness"], {"copilot-cli", "git-loopy"}, role_id)
            self.assertTrue(set(role["benchmarks"]) <= set(scorer.BENCHMARKS), role_id)
            dependency = role.get("distinct_vendor_from")
            self.assertTrue(dependency in (None, "main") or dependency in roles, role_id)
        self.assertTrue(all(entry["role"] in roles for entry in PROFILES["sdlc"]))

    def test_profiles_map_every_skill_to_a_role(self):
        self.assertEqual(set(PROFILES["skills"]), tracked_skills())
        self.assertTrue(set(PROFILES["skills"].values()) <= set(PROFILES["roles"]))

    def test_render_lists_every_role_sdlc_task_and_skill(self):
        picks = synthetic_picks()
        listed = listing(("alpha-1", ["high"], "enabled"), ("beta-2", ["high"], "enabled"), ("gamma-3", ["low"], "enabled"))
        skills = scorer.recommend_skills(PROFILES, picks, {"roles": {}}, listed)
        meta = {"generated": "now", "page": "p", "captured": "c", "current_models": 3, "rows_matched": 5,
                "copilot_version": "1", "sdk_version": "2", "ratio": 0.8, "gaps": {"retired": [], "absent": []}}
        text = scorer.render(PROFILES, picks, meta, {}, skills, {})
        for role_id in PROFILES["roles"]:
            self.assertIn(f"| {role_id.split(':', 1)[1]} |", text)
        for entry in PROFILES["sdlc"]:
            self.assertIn(entry["task"], text)
        for name in PROFILES["skills"]:
            self.assertIn(f"| {name} | {PROFILES['skills'][name]} |", text)
        self.assertNotEqual(picks["copilot:rubber-duck"]["pick"]["vendor"], "Vendor A")
        document = scorer.headers_document(skills, listed, meta)
        self.assertEqual(set(document["skills"]), set(PROFILES["skills"]))
        self.assertEqual(document["models"]["alpha-1"], {"efforts": ["high"], "default_cap": 200000, "long_cap": 900000})

    def test_coverage_separates_retired_from_absent(self):
        rows = [row("Alpha 1 (high)", 50), {**row("Old 2 (high)", 40), "deprecated": True}]
        listed = listing(("alpha-1", ["high"], "enabled"), ("old-2", ["high"], "enabled"), ("new-3", [], "enabled"))
        pool = scorer.build_candidates(rows, listed)
        self.assertEqual(scorer.coverage([listed], [pool], rows), {"retired": ["old-2"], "absent": ["new-3"]})

    def test_any_field_order_scores(self):
        pool = scorer.build_candidates([row("Alpha 1 (high)", 48)], listing(("alpha-1", ["high"], "enabled")))
        reordered = ["first_answer", "success", "end_to_end", "token_appetite", "consistency", "throughput"]
        value, parts = scorer.score(pool[0], ROLE, scorer.build_scales(pool), reordered)
        self.assertTrue(1 <= value <= 100)
        self.assertEqual(set(parts), set(reordered))

    def test_recommend_refuses_unknown_fields_and_missing_main_model(self):
        pool = scorer.build_candidates([row("Alpha 1 (high)", 53)], listing(("alpha-1", ["high"], "enabled")))
        pools = {"copilot-cli": pool, "git-loopy": pool}
        bad_fields = {**PROFILES, "fields": [*PROFILES["fields"], {"id": "vibes", "label": "v", "source": "s"}]}
        with self.assertRaises(SystemExit):
            scorer.recommend(bad_fields, pools, {"roles": {}}, "alpha-1")
        with self.assertRaises(SystemExit):
            scorer.recommend(PROFILES, pools, {"roles": {}}, None)
        with self.assertRaises(SystemExit):
            scorer.recommend(PROFILES, pools, {"roles": {}}, "auto")

    def test_settings_read_as_jsonc(self):
        text = '{\n "model": "claude-x", // main\n /* block */ "path": "C:\\\\", "url": "http://a//b",\n "list": [1, 2,],\n}\n'
        self.assertEqual(
            json.loads(scorer._jsonc_to_json(text)),
            {"model": "claude-x", "path": "C:\\", "url": "http://a//b", "list": [1, 2]},
        )


if __name__ == "__main__":
    unittest.main(verbosity=1)
