#!/usr/bin/env python3
"""Offline checks for /next's pinned skill map and local routing contracts."""

import hashlib
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NextGuidanceTests(unittest.TestCase):
    def test_wayfinder_destinations_precede_the_generic_spec_gate(self):
        text = (ROOT / "skills/next/SKILL.md").read_text(encoding="utf-8")
        table = text.split("| Current state | Next route |", 1)[1].split(
            "Apply these flow rules:", 1
        )[0]
        rows = [
            tuple(cell.strip() for cell in row.strip("|").split("|"))
            for row in table.splitlines() if row.startswith("|")
        ]
        cases = (
            ("open decision ticket or remaining fog", ("`/wayfinder`",)),
            ("decision destination", ("No next route", "follow-up work")),
            ("specification destination", ("from the spec", "wayfinder", "gates below")),
            ("in-place change or proof of concept", (
                "`/to-spec`", "`/implement`", "only", "genuinely small",
            )),
        )
        generic_gate = next(
            index for index, (state, _) in enumerate(rows)
            if "no durable spec exists" in state
        )
        for destination, outcomes in cases:
            with self.subTest(destination=destination):
                matches = [
                    (index, route) for index, (state, route) in enumerate(rows)
                    if destination in state
                ]
                self.assertEqual(len(matches), 1)
                index, route = matches[0]
                self.assertLess(index, generic_gate)
                for outcome in outcomes:
                    self.assertIn(outcome, route)
                if destination == "decision destination":
                    self.assertNotIn("`/to-spec`", route)
                    self.assertNotIn("`/implement`", route)
        flow = " ".join(text.split("Apply these flow rules:", 1)[1].split())
        self.assertIn("no open decision ticket and no fog", flow)
        self.assertIn("closing summary comment", flow)
        self.assertIn("recorded decisions themselves call for follow-up work", flow)
        self.assertIn("do not synthesize it again", flow)
        self.assertNotIn(
            "destination is clear and no decision ticket remains, route to `/to-spec`",
            flow,
        )

    def test_docs_explain_finished_maps_without_inventing_a_build(self):
        docs = (ROOT / "docs/next.md").read_text(encoding="utf-8")
        self.assertIn("### Wayfinder destinations", docs)
        section = docs.split("### Wayfinder destinations", 1)[1].split("\n### ", 1)[0]
        for rule in (
            "no open decision ticket and no fog",
            "closing summary comment",
            "Open frontier or remaining fog | Continue `/wayfinder`",
            "Finished, specification destination | Continue from the spec",
            "wayfinder already called `/to-spec`",
            "Finished, decision destination | No next route",
            "recorded decisions themselves call for follow-up work",
            "Finished, in-place change or proof of concept still to build | `/to-spec`",
            "`/implement` only when the effort proved genuinely small",
            "kept git-loopy overlay",
            "`ask-matt`",
            "49dd158d1076134a641b33efb035946536778336",
        ):
            with self.subTest(rule=rule):
                self.assertIn(rule, " ".join(section.split()))
        self.assertNotIn("\u2014", section)
        self.assertNotIn("an agreed destination with no durable spec gates", docs)

    def test_selection_covers_the_pinned_catalog_without_retired_skills(self):
        route = (ROOT / "skills/next/SKILL.md").read_text(encoding="utf-8")
        selection = (ROOT / "skills/next/references/SKILL-SELECTION.md").read_text(
            encoding="utf-8"
        )
        route_table = route.split("| Current state | Next route |", 1)[1].split(
            "Apply these flow rules:", 1
        )[0]
        entries = set(re.findall(r"`/([a-z][a-z-]*)`", route_table + selection))
        # ask-matt at the pin, with handoff and setup renamed for git-loopy.
        upstream_skills = {
            "grill-with-docs", "grill-me", "grilling", "to-handoff", "prototype",
            "to-spec", "to-tickets", "implement", "implement-spec", "tdd",
            "code-review", "pr", "retro", "triage", "diagnosing-bugs", "wayfinder",
            "improve-codebase-architecture", "domain-modeling", "codebase-design",
            "research", "to-questionnaire", "wizard", "wait-what", "teach",
            "writing-for-agents", "setup-git-loopy-skills",
        }
        self.assertFalse(upstream_skills - entries, upstream_skills - entries)
        self.assertIn("chief-of-staff", entries)
        for name in entries - {"clear", "compact"}:
            with self.subTest(skill=name):
                self.assertTrue((ROOT / "skills" / name / "SKILL.md").is_file())
        self.assertIn("GLOSSARY.md", selection)
        self.assertNotIn("CONTEXT.md", selection)
        self.assertNotRegex(selection, r"\|[^|\n]*\| `/pr` \|")
        self.assertIn("`/push`", selection)

    def test_flow_keeps_user_invoked_routes_outside_the_chain(self):
        text = (ROOT / "skills/next/SKILL.md").read_text(encoding="utf-8")
        table = text.split("| Current state | Next route |", 1)[1].split(
            "Apply these flow rules:", 1
        )[0]
        for skill in ("implement-spec", "retro", "to-handoff", "chief-of-staff"):
            with self.subTest(skill=skill):
                self.assertRegex(table, rf"\|[^\n]+\| `/{skill}` \(HITL\) \|")
        retro_row = next(row for row in table.splitlines() if "`/retro`" in row)
        self.assertIn("build", retro_row)
        self.assertIn("`/diagnosing-bugs`", retro_row)
        self.assertLess(table.index("`/retro`"), table.index("`/improve-codebase-architecture`"))
        for rule in (
            "Use `/to-handoff` only for its portability cases",
            "Bridge a prototype detour with `/to-handoff`",
            "Run `/retro` in the session it examines before clearing",
            "declined retrospective for the same work",
            "Reach `/pr` through `/push`, not as a direct route",
            "For `/to-handoff`, use `Continue here`",
            "`/handoff` to launch the prompt in the background",
        ):
            with self.subTest(rule=rule):
                self.assertIn(rule, text)
        gate = text.split("## 5.", 1)[1].split("## 6.", 1)[0]
        self.assertIn(
            "also allowlisted: `/implement`,\n`/code-review`, `/research`, or `/push`",
            gate,
        )

    def test_docs_explain_the_local_names_and_user_invocation_boundary(self):
        docs = (ROOT / "docs/next.md").read_text(encoding="utf-8")
        for skill in ("implement-spec", "retro", "to-handoff", "chief-of-staff", "pr"):
            with self.subTest(skill=skill):
                self.assertIn(f"[{skill}](./{skill}.md)", docs)
        for rule in (
            "after a build or a `/diagnosing-bugs` fix",
            "not a direct route",
            "portable file",
            "GLOSSARY.md",
            "does not enlarge the chain allowlist",
        ):
            with self.subTest(rule=rule):
                self.assertIn(rule, docs)

    def test_phase_boundaries_preserve_the_pin_except_for_local_names(self):
        text = (ROOT / "skills/next/references/PHASE-BOUNDARIES.md").read_text(
            encoding="utf-8"
        )
        self.assertEqual(text.count("`/to-handoff`"), 4)
        self.assertEqual(text.count("(Copilot CLI → Codex)"), 1)
        text = text.replace("`/to-handoff`", "`/handoff`").replace(
            "(Copilot CLI → Codex)", "(Claude → Codex)"
        )
        # skills/engineering/ask-matt/PHASE-BOUNDARIES.md from
        # bradcstevens/mattpocock-skills@49dd158d1076134a641b33efb035946536778336.
        self.assertEqual(
            hashlib.sha256(text.encode()).hexdigest(),
            "a8aa20158609ef39e2b308b6ba0660c91066838d07a867202e63a7744a88a3ed",
        )


if __name__ == "__main__":
    unittest.main()
