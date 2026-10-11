#!/usr/bin/env python3
"""The upstream-sync control loop: sensor, controller and deterministic actions.

The loop keeps git-loopy-skills synced with mattpocock/skills releases, then
moves git-loopy's skill pin behind each completed sync. Design, local runbook
and steering: docs/upstream-sync-loop.md. Scope gate: .github/upstream-sync.json.

    upstream-sync.py sense                        read-only measurement   > sensor.json
    upstream-sync.py control SENSOR               pure decision           > decision.json
    upstream-sync.py apply DECISION [--dry-run]   merge, abandon, close-out, record-release, pause
    upstream-sync.py shepherd [--out FILE]        sense, control, apply until a non-deterministic decision
    upstream-sync.py decide implement --ticket N [--repo R]
    upstream-sync.py decide iterate --repo R --pr N --comment-id C --comment-body B
    upstream-sync.py start DECISION --root DIR    checkout + attempt marker (+ --install-skills in CI)
    upstream-sync.py prompt DECISION              actuator prompt         > prompt.md
    upstream-sync.py finish DECISION --body FILE  PR body and label, replies, failure handling

Only `apply`, `start` and `finish` write to GitHub. `control` is a pure function
of the sensor output, unit-tested offline by scripts/test-upstream-sync.py.
Runs on Python 3.9 (stock macOS) and later.
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = REPO_ROOT / ".github" / "upstream-sync.json"

AGENT_ACTIONS = ("implement", "fix", "iterate", "plan", "downstream-plan")
DETERMINISTIC_ACTIONS = ("merge", "abandon", "close-out", "record-release")
# A non-renameable assertion (docs/agents/triage-labels.md), so it is not configurable.
PRIORITY_LABEL = "priority"

MARKER_RE = re.compile(r"<!--\s*upstream-sync:([a-z-]+)((?:\s+[a-z_]+=[^\s>]+)*)\s*-->")
CLAIM_RE = re.compile(r"(?:^|/)(?:ticket|issue)[-/]?(\d+)(?=\D|$)")
WHAT_TO_BUILD_RE = re.compile(r"^## What to build", re.MULTILINE)
ACCEPTANCE_RE = re.compile(r"^## Acceptance criteria", re.MULTILINE)
PENDING_CHECK_STATES = {"PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "REQUESTED", "WAITING"}


class LoopError(Exception):
    """A failure the loop reports instead of acting on."""


# --------------------------------------------------------------------------- markers


def marker(kind: str, **fields: object) -> str:
    body = "".join(f" {key}={value}" for key, value in fields.items() if value not in (None, ""))
    return f"<!-- upstream-sync:{kind}{body} -->"


def parse_markers(text: str | None) -> list:
    found = []
    for match in MARKER_RE.finditer(text or ""):
        fields = dict(pair.split("=", 1) for pair in match.group(2).split())
        found.append((match.group(1), fields))
    return found


def first_marker(text: str | None, kind: str) -> dict | None:
    for found_kind, fields in parse_markers(text):
        if found_kind == kind:
            return fields
    return None


def ticket_from_branch(branch: str, prefix: str) -> int | None:
    if not branch.startswith(prefix):
        return None
    match = re.fullmatch(r"(\d+)", branch[len(prefix):])
    return int(match.group(1)) if match else None


def claimed_numbers(branch: str, prefix: str) -> list:
    """Ticket numbers a branch name claims. The loop's own namespace claims nothing."""
    if branch.startswith(prefix):
        return []
    return [int(match.group(1)) for match in CLAIM_RE.finditer(branch)]


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def minutes_between(earlier: str, later: str) -> float:
    return (parse_time(later) - parse_time(earlier)).total_seconds() / 60


def number_from_url(url: str) -> int:
    return int(url.strip().rstrip("/").rsplit("/", 1)[-1])


def queue_key(issue: dict) -> tuple:
    """Priority first, then oldest: the order docs/agents/triage-labels.md gives the queue."""
    return (PRIORITY_LABEL not in issue["labels"], issue["created_at"], issue["number"])


# --------------------------------------------------------------------------- trust
#
# The repositories are public, so anyone can comment. A marker counts only when the
# loop's own account (the token's owner) wrote it, and an issue-body marker only when
# a trusted association authored the issue.


def trusted_comment(comment: dict, trusted: str) -> bool:
    return (comment.get("user") or {}).get("login") == trusted


def trusted_issue(issue: dict, cfg: dict) -> bool:
    return issue.get("author_association") in cfg["trusted_associations"]


def is_loop_pr(head_ref: str, author: str | None, cross_repository: bool, labels: list, cfg: dict, trusted: str) -> bool:
    """The loop's own pull request: opened by its account, from a branch in this repository."""
    if cross_repository or author != trusted:
        return False
    return head_ref.startswith(cfg["branch_prefix"]) or cfg["labels"]["pull_request"] in labels


_REVIEW_RECORD: list = []


def review_record():
    """scripts/review-clean-record.py, the single source of the record's shape."""
    if not _REVIEW_RECORD:
        path = REPO_ROOT / "scripts" / "review-clean-record.py"
        spec = importlib.util.spec_from_file_location("review_clean_record", path)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        _REVIEW_RECORD.append(module)
    return _REVIEW_RECORD[0]


def trusted_review_clean(comments: list, head: str, trusted: str) -> bool:
    """Whether the loop's own account recorded `review-clean` for this exact head.

    `chain.sh gate` matches a record from any commenter, so on a public tracker the
    loop also requires one its own account wrote before it merges.
    """
    record = review_record()
    return any(
        trusted_comment(comment, trusted) and record.matching_record(comment.get("body") or "", head)
        for comment in comments
    )


_LOGIN: list = []


def current_login() -> str:
    if not _LOGIN:
        _LOGIN.append(gh_api("user")["login"])
    return _LOGIN[0]


# --------------------------------------------------------------------------- gh


def run_gh(args: list, *, check: bool = True, input_text: str | None = None) -> str:
    result = subprocess.run(["gh", *args], input=input_text, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise LoopError(f"gh {' '.join(args[:3])} failed ({result.returncode}): {result.stderr.strip()[:400]}")
    return result.stdout


def gh_json(*args: str):
    out = run_gh(list(args))
    return json.loads(out) if out.strip() else None


def gh_api(path: str):
    return gh_json("api", path)


def gh_paginated(path: str) -> list:
    pages = gh_json("api", "--paginate", "--slurp", path) or []
    items: list = []
    for page in pages:
        if isinstance(page, list):
            items.extend(page)
        else:
            items.append(page)
    return items


def comments_of(repo: str, number: int) -> list:
    return gh_paginated(f"repos/{repo}/issues/{number}/comments?per_page=100")


# --------------------------------------------------------------------------- config


def load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def repo_settings(repo: str, cfg: dict) -> dict:
    """The config section for a repository: the downstream runner's, or this repository's."""
    return cfg["downstream"] if repo == cfg["downstream"]["repository"] else cfg["skills"]


def local_skill_names(repo_root: Path) -> list:
    skills = repo_root / "skills"
    if not skills.is_dir():
        return []
    return sorted(entry.name for entry in skills.iterdir() if (entry / "SKILL.md").is_file())


# --------------------------------------------------------------------------- pure sensor helpers


def normalize_issue(issue: dict) -> dict:
    body = issue.get("body") or ""
    return {
        "number": issue["number"],
        "title": issue.get("title", ""),
        "state": issue.get("state", "open"),
        "state_reason": issue.get("state_reason"),
        "labels": sorted(label["name"] for label in issue.get("labels") or []),
        "assignees": sorted(user["login"] for user in issue.get("assignees") or []),
        "created_at": issue.get("created_at", ""),
        "blocked_by": (issue.get("issue_dependencies_summary") or {}).get("blocked_by", 0),
        "afk_ready": bool(WHAT_TO_BUILD_RE.search(body) and ACCEPTANCE_RE.search(body)),
    }


def count_markers(comments: list, kind: str, trusted: str, after: str | None = None) -> int:
    count = 0
    for comment in comments:
        if not trusted_comment(comment, trusted):
            continue
        if after and comment.get("created_at", "") <= after:
            continue
        count += sum(1 for found, _ in parse_markers(comment.get("body")) if found == kind)
    return count


def answered_iterates(comments: list, trusted: str) -> set:
    """Ids of the /iterate comments the loop's own replies name as answered."""
    answered = set()
    for comment in comments:
        if not trusted_comment(comment, trusted):
            continue
        for kind, fields in parse_markers(comment.get("body")):
            if kind == "iterate-reply" and fields.get("comment"):
                answered.add(str(fields["comment"]))
    return answered


def pending_iterate(comments: list, authors: list, trusted: str) -> dict | None:
    """The oldest authorised /iterate comment the loop has not answered."""
    answered = answered_iterates(comments, trusted)
    for comment in sorted(comments, key=lambda item: (item.get("created_at", ""), item.get("id", 0))):
        body = (comment.get("body") or "").strip()
        if not body.startswith("/iterate"):
            continue
        if comment.get("author_association") not in authors:
            continue
        if str(comment.get("id")) in answered:
            continue
        return {
            "id": comment.get("id"),
            "author": (comment.get("user") or {}).get("login"),
            "body": body,
            "created_at": comment.get("created_at"),
        }
    return None


def last_iterate_reply_at(comments: list, trusted: str) -> str | None:
    stamps = [
        comment.get("created_at", "")
        for comment in comments
        if trusted_comment(comment, trusted)
        and any(kind == "iterate-reply" for kind, _ in parse_markers(comment.get("body")))
    ]
    return max(stamps) if stamps else None


def skill_dirs_from_tree(tree: dict, root: str) -> dict:
    if tree.get("truncated"):
        raise LoopError("upstream tree listing is truncated")
    pattern = re.compile(rf"^{re.escape(root)}/([^/]+)/([^/]+)$")
    dirs = {}
    for entry in tree.get("tree", []):
        if entry.get("type") != "tree":
            continue
        match = pattern.match(entry.get("path", ""))
        if match:
            dirs[match.group(2)] = {"bucket": match.group(1), "tree": entry.get("sha")}
    return dirs


def classify_skills(base: dict, head: dict, cfg: dict, local: list) -> list:
    """Per-skill changes between two upstream revisions, with the scope gate applied."""
    upstream = cfg["upstream"]
    renames = upstream.get("renames", {})
    buckets = set(upstream.get("in_scope_buckets", []))
    also = set(upstream.get("also_in_scope", []))
    rows = []
    for name in sorted(set(base) | set(head)):
        before, after = base.get(name), head.get(name)
        if before and after and before["bucket"] == after["bucket"] and before["tree"] == after["tree"]:
            continue
        if before is None:
            change, bucket = "added", after["bucket"]
        elif after is None:
            change, bucket = "removed", before["bucket"]
        elif before["bucket"] != after["bucket"]:
            change = "deprecated" if after["bucket"] == "deprecated" else "moved"
            bucket = after["bucket"]
        else:
            change, bucket = "modified", after["bucket"]
        counterpart = renames.get(name, name)
        has_local = counterpart in local
        from_bucket = before["bucket"] if before else None
        rows.append(
            {
                "skill": name,
                "change": change,
                "bucket": bucket,
                "from_bucket": from_bucket,
                "local": counterpart if has_local else None,
                "in_scope": bool(
                    bucket in buckets or from_bucket in buckets or name in also or has_local
                ),
            }
        )
    return rows


# --------------------------------------------------------------------------- sensor (gh, read-only)


def wait_for_mergeable(repo: str, number: int, tries: int = 5) -> str:
    state = "UNKNOWN"
    for attempt in range(tries):
        state = (gh_json("pr", "view", str(number), "--repo", repo, "--json", "mergeable") or {}).get(
            "mergeable", "UNKNOWN"
        )
        if state != "UNKNOWN":
            return state
        time.sleep(3 * (attempt + 1))
    return state


def run_gate(repo: str, number: int, ticket: int, repo_root: Path) -> dict:
    script = repo_root / "skills" / "next" / "chain.sh"
    result = subprocess.run(
        [str(script), "gate", "--pull-request", str(number), "--ticket", str(ticket), "--repo", repo],
        capture_output=True,
        text=True,
    )
    lines = [line for line in result.stdout.strip().splitlines() if line.strip()]
    try:
        verdict = json.loads(lines[-1])
    except (IndexError, json.JSONDecodeError):
        verdict = {"decision": "error", "reason": "gate-output-unreadable", "stderr": result.stderr.strip()[-400:]}
    verdict["exit_status"] = result.returncode
    return verdict


def read_open_prs(repo: str) -> list:
    return gh_json(
        "pr", "list", "--repo", repo, "--state", "open", "--limit", "200", "--json",
        "number,title,headRefName,headRefOid,isDraft,labels,createdAt,url,closingIssuesReferences,author,isCrossRepository",
    ) or []


def pr_claims(prs: list, cfg: dict, interesting: set) -> dict:
    """Tickets an open pull request from a branch in this repository closes or is named for.

    A fork pull request claims nothing: anyone can open one, and a claim stops the loop.
    """
    prefix = cfg["branch_prefix"]
    claims: dict = {}
    for pr in prs:
        if pr.get("isCrossRepository") or pr["headRefName"].startswith(prefix):
            continue
        refs = [ref["number"] for ref in pr.get("closingIssuesReferences") or []]
        for number in refs + claimed_numbers(pr["headRefName"], prefix):
            if number in interesting:
                claims.setdefault(str(number), []).append(f"PR #{pr['number']} ({pr['headRefName']})")
    return claims


def read_claims(repo: str, prs: list, cfg: dict, now: str, interesting: set) -> dict:
    """Tickets someone else is working: open PRs that close them, or fresh branches named for them.

    Only branches naming an `interesting` ticket are dated, because a repository
    with many runner lanes would otherwise cost one API call per branch.
    """
    prefix = cfg["branch_prefix"]
    claims = pr_claims(prs, cfg, interesting)
    if not interesting:
        return claims
    max_age_minutes = cfg["limits"]["branch_claim_days"] * 24 * 60
    for branch in gh_paginated(f"repos/{repo}/branches?per_page=100"):
        numbers = [number for number in claimed_numbers(branch["name"], prefix) if number in interesting]
        if not numbers:
            continue
        committed = gh_api(f"repos/{repo}/commits/{branch['commit']['sha']}")["commit"]["committer"]["date"]
        if minutes_between(committed, now) > max_age_minutes:
            continue
        for number in numbers:
            claims.setdefault(str(number), []).append(f"branch {branch['name']}")
    return claims


def read_specs(repo: str, cfg: dict, trusted: str) -> dict:
    label = cfg["labels"]["sync"]
    issues = [
        issue
        for issue in gh_paginated(f"repos/{repo}/issues?labels={label}&state=all&per_page=100")
        if "pull_request" not in issue and trusted_issue(issue, cfg)
    ]
    open_specs, closed_specs, blockers = [], [], []
    for issue in issues:
        body = issue.get("body") or ""
        if issue["state"] == "open" and first_marker(body, "blocked") is not None:
            blockers.append({"number": issue["number"], "title": issue["title"]})
            continue
        spec = first_marker(body, "spec")
        if spec is None:
            continue
        record = {
            "number": issue["number"],
            "title": issue["title"],
            "state": issue["state"],
            "state_reason": issue.get("state_reason"),
            "closed_at": issue.get("closed_at"),
            "target": spec.get("target"),
            "release": spec.get("release"),
        }
        (open_specs if issue["state"] == "open" else closed_specs).append(record)
    last_completed = None
    completed = [spec for spec in closed_specs if spec.get("state_reason") == "completed"]
    for spec in sorted(completed, key=lambda item: item.get("closed_at") or "", reverse=True):
        synced = None
        for comment in comments_of(repo, spec["number"]):
            if trusted_comment(comment, trusted):
                synced = first_marker(comment.get("body"), "synced") or synced
        last_completed = dict(spec)
        if synced:
            last_completed.update(
                target=synced.get("target") or spec["target"],
                release=synced.get("release") or spec["release"],
                skills=synced.get("skills"),
            )
        else:
            last_completed["skills"] = None
        break
    return {"open": sorted(open_specs, key=lambda item: item["number"]), "last_completed": last_completed, "blockers": blockers}


def attach_attempts(repo: str, issues: list, should_count, trusted: str) -> None:
    for issue in issues:
        issue["attempts"] = (
            count_markers(comments_of(repo, issue["number"]), "attempt", trusted) if should_count(issue) else 0
        )


def read_tickets(repo: str, spec: int) -> list:
    return [normalize_issue(item) for item in gh_paginated(f"repos/{repo}/issues/{spec}/sub_issues?per_page=100")]


def eligibility(issue: dict, cfg: dict, claims: dict, limit: int | None = None) -> str:
    """Where an issue stands in the loop's queue. One rule for every queue the loop reads.

    `not_ready` follows docs/agents/triage-labels.md: the AFK-ready label, no human label,
    and a body with both `## What to build` and `## Acceptance criteria`.
    """
    labels = cfg["labels"]
    if issue.get("state") != "open":
        return "closed"
    if labels["ready"] not in issue["labels"] or labels["human"] in issue["labels"] or not issue.get("afk_ready"):
        return "not_ready"
    if issue.get("blocked_by", 0) > 0:
        return "blocked"
    if issue.get("assignees") or str(issue["number"]) in claims:
        return "claimed"
    if limit is not None and issue.get("attempts", 0) >= limit:
        return "exhausted"
    return "eligible"


def read_loop_prs(repo: str, prs: list, cfg: dict, repo_root: Path, trusted: str) -> list:
    prefix = cfg["branch_prefix"]
    loop_prs = []
    for pr in prs:
        names = [item["name"] for item in pr.get("labels") or []]
        author = (pr.get("author") or {}).get("login")
        if not is_loop_pr(pr["headRefName"], author, bool(pr.get("isCrossRepository")), names, cfg, trusted):
            continue
        ticket = ticket_from_branch(pr["headRefName"], prefix)
        ticket_issue = gh_api(f"repos/{repo}/issues/{ticket}") if ticket else {}
        ticket_comments = comments_of(repo, ticket) if ticket else []
        comments = comments_of(repo, pr["number"])
        reset_at = last_iterate_reply_at(comments, trusted)
        head = gh_api(f"repos/{repo}/commits/{pr['headRefOid']}") if pr.get("headRefOid") else None
        record = {
            "repository": repo,
            "number": pr["number"],
            "url": pr.get("url"),
            "title": pr.get("title"),
            "head_ref": pr["headRefName"],
            "head_sha": pr.get("headRefOid"),
            "head_committed_at": head["commit"]["committer"]["date"] if head else None,
            "is_draft": bool(pr.get("isDraft")),
            "created_at": pr.get("createdAt"),
            "ticket": ticket,
            "ticket_state": ticket_issue.get("state"),
            "ticket_state_reason": ticket_issue.get("state_reason"),
            "review_clean_by_loop": bool(ticket and pr.get("headRefOid"))
            and trusted_review_clean(ticket_comments, pr["headRefOid"], trusted),
            "pending_iterate": pending_iterate(comments, cfg["trusted_associations"], trusted),
            "fix_attempts": count_markers(comments, "fix-attempt", trusted, after=reset_at),
            "paused": count_markers(comments, "paused", trusted, after=reset_at) > 0,
            "mergeable": wait_for_mergeable(repo, pr["number"]),
            "gate": run_gate(repo, pr["number"], ticket, repo_root) if ticket else None,
        }
        loop_prs.append(record)
    return loop_prs


def read_downstream_issues(cfg: dict, trusted: str) -> list:
    repo = cfg["downstream"]["repository"]
    issues = [
        normalize_issue(issue)
        for issue in gh_paginated(f"repos/{repo}/issues?labels={cfg['labels']['sync']}&state=open&per_page=100")
        if "pull_request" not in issue and trusted_issue(issue, cfg)
    ]
    attach_attempts(repo, issues, lambda issue: True, trusted)
    return issues


def read_downstream(cfg: dict, last_completed: dict | None, skills_main: str | None, issues: list) -> dict:
    down = cfg["downstream"]
    repo = down["repository"]
    content = gh_api(f"repos/{repo}/contents/{down['pin_path']}?ref={down['default_branch']}")
    pin = json.loads(base64.b64decode(content["content"]).decode("utf-8"))["revision"]
    contains = None
    if last_completed and last_completed.get("skills"):
        status = gh_api(f"repos/{cfg['skills']['repository']}/compare/{last_completed['skills']}...{pin}")["status"]
        contains = status in ("ahead", "identical")
    return {
        "repository": repo,
        "pin": pin,
        "publish_revision": skills_main,
        "pin_contains_last_sync": contains,
        "issues": issues,
    }


def latest_release(repo: str) -> dict:
    release = gh_api(f"repos/{repo}/releases/latest")
    sha = gh_api(f"repos/{repo}/commits/{release['tag_name']}")["sha"]
    return {"tag": release["tag_name"], "sha": sha, "published_at": release.get("published_at")}


def release_gap(cfg: dict, base: str, release: dict, repo_root: Path) -> dict:
    upstream = cfg["upstream"]["repository"]
    status = gh_api(f"repos/{upstream}/compare/{base}...{release['sha']}?per_page=1")["status"]
    gap = {"base": base, "head": release["sha"], "release": release["tag"], "compare": status}
    if status in ("identical", "behind"):
        gap["status"] = "covered"
        return gap
    root = cfg["upstream"]["skills_root"]
    before = skill_dirs_from_tree(gh_api(f"repos/{upstream}/git/trees/{base}?recursive=1"), root)
    after = skill_dirs_from_tree(gh_api(f"repos/{upstream}/git/trees/{release['sha']}?recursive=1"), root)
    gap["status"] = "gap"
    gap["skills"] = classify_skills(before, after, cfg, local_skill_names(repo_root))
    return gap


def sense(cfg: dict, repo_root: Path) -> dict:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    skills_repo = cfg["skills"]["repository"]
    down_repo = cfg["downstream"]["repository"]
    sensor: dict = {"now": now, "errors": []}

    def section(name: str, read):
        try:
            return read()
        except Exception as error:  # noqa: BLE001 - every sensor failure is reported, never acted on
            sensor["errors"].append(f"{name}: {error}")
            return None

    sensor["skills_main"] = section(
        "skills_main", lambda: gh_api(f"repos/{skills_repo}/commits/{cfg['skills']['default_branch']}")["sha"]
    )
    trusted = section("trusted_login", current_login)
    sensor["trusted_login"] = trusted
    if trusted is None:
        return sensor
    specs = section("specs", lambda: read_specs(skills_repo, cfg, trusted)) or {
        "open": [],
        "last_completed": None,
        "blockers": [],
    }
    for spec in specs["open"]:
        spec["tickets"] = section(
            f"tickets of #{spec['number']}", lambda spec=spec: read_tickets(skills_repo, spec["number"])
        ) or []
    down_issues = section("downstream_issues", lambda: read_downstream_issues(cfg, trusted)) or []

    open_tickets = {ticket["number"] for spec in specs["open"] for ticket in spec["tickets"] if ticket["state"] == "open"}
    skills_prs = section("pull_requests", lambda: read_open_prs(skills_repo)) or []
    down_prs = section("downstream_pull_requests", lambda: read_open_prs(down_repo)) or []
    skills_claims = section("claims", lambda: read_claims(skills_repo, skills_prs, cfg, now, open_tickets)) or {}
    down_claims = section(
        "downstream_claims",
        lambda: read_claims(down_repo, down_prs, cfg, now, {issue["number"] for issue in down_issues}),
    ) or {}
    sensor["claims"] = {skills_repo: skills_claims, down_repo: down_claims}
    for spec in specs["open"]:
        section(
            f"attempts of #{spec['number']}",
            lambda spec=spec: attach_attempts(
                skills_repo,
                spec["tickets"],
                lambda ticket: eligibility(ticket, cfg, skills_claims) == "eligible",
                trusted,
            ),
        )

    sensor["loop_prs"] = (
        section("loop_prs", lambda: read_loop_prs(skills_repo, skills_prs, cfg, repo_root, trusted)) or []
    ) + (section("downstream_loop_prs", lambda: read_loop_prs(down_repo, down_prs, cfg, repo_root, trusted)) or [])
    sensor["specs"] = {"open": specs["open"], "last_completed": specs["last_completed"]}
    sensor["blocked_issues"] = specs["blockers"]
    release = section("latest_release", lambda: latest_release(cfg["upstream"]["repository"]))
    sensor["latest_release"] = release
    base = specs["open"][0]["target"] if specs["open"] else (specs["last_completed"] or {}).get("target")
    sensor["release_gap"] = (
        section("release_gap", lambda: release_gap(cfg, base, release, repo_root)) if base and release else None
    )
    sensor["downstream"] = section(
        "downstream", lambda: read_downstream(cfg, specs["last_completed"], sensor["skills_main"], down_issues)
    )
    return sensor


# --------------------------------------------------------------------------- controller (pure)


def decide(action: str, **fields: object) -> dict:
    decision = {"action": action}
    decision.update({key: value for key, value in fields.items() if value is not None})
    decision.setdefault("reason", "")
    return decision


def select_ticket(tickets: list, cfg: dict, claims: dict) -> tuple:
    census = {"open": 0, "not_ready": 0, "blocked": 0, "claimed": 0, "exhausted": 0}
    candidates = []
    for ticket in tickets:
        standing = eligibility(ticket, cfg, claims, limit=cfg["limits"]["max_ticket_attempts"])
        if standing == "closed":
            continue
        census["open"] += 1
        if standing == "eligible":
            candidates.append(ticket)
        else:
            census[standing] += 1
    candidates.sort(key=queue_key)
    return (candidates[0] if candidates else None), census


def shepherd_pr(pr: dict, cfg: dict, now: str) -> dict:
    common = {
        "repository": pr["repository"],
        "pull_request": pr["number"],
        "ticket": pr.get("ticket"),
        "branch": pr["head_ref"],
        "head_sha": pr.get("head_sha"),
    }
    if pr.get("ticket") is None:
        return decide("blocked", reason=f"loop PR #{pr['number']} names no ticket in {pr['head_ref']}", **common)
    gate = pr.get("gate") or {}
    if gate.get("decision") != "allow" and not gate.get("missing"):
        return decide("wait", reason=f"merge gate unavailable: {gate.get('reason', 'no verdict')}", **common)
    missing = set(gate.get("missing") or [])
    if not pr.get("review_clean_by_loop"):
        missing.add("review-clean-evidence-comment")
    if not missing:
        method = repo_settings(pr["repository"], cfg)["merge_method"]
        return decide("merge", merge_method=method, reason="merge evidence complete", **common)
    missing = sorted(missing)
    if pr.get("is_draft") or "pull-request-not-draft" in missing:
        return decide("wait", reason="draft PR: paused by a human", **common)
    conflicted = pr.get("mergeable") == "CONFLICTING"
    if pr.get("mergeable") == "UNKNOWN":
        return decide("wait", reason="GitHub has not computed mergeability yet", **common)
    if not conflicted and "checks-complete" in missing:
        return decide("wait", reason="checks running", **common)
    if not conflicted and "checks-present" in missing:
        pushed = pr.get("head_committed_at") or pr["created_at"]
        if minutes_between(pushed, now) < cfg["limits"]["checks_absent_grace_minutes"]:
            return decide("wait", reason="waiting for checks to start", **common)
        return decide(
            "blocked",
            reason=f"PR #{pr['number']} has reported no checks; was it opened with the workflow's GITHUB_TOKEN?",
            pause=True,
            **common,
        )
    attempts = pr.get("fix_attempts", 0)
    if attempts >= cfg["limits"]["max_fix_attempts"]:
        return decide(
            "blocked",
            reason=f"PR #{pr['number']}: {attempts} fix attempts without merge evidence; a human decides",
            pause=True,
            details={"missing": missing},
            **common,
        )
    return decide(
        "fix",
        reason="missing " + ", ".join(missing),
        details={"missing": missing, "mergeable": pr.get("mergeable"), "attempt": attempts + 1},
        **common,
    )


def downstream_decision(last: dict, downstream: dict, cfg: dict, claims: dict) -> dict:
    repo = downstream["repository"]
    issues = downstream.get("issues") or []
    details = {
        "last_sync": last,
        "pin": downstream.get("pin"),
        "publish_revision": downstream.get("publish_revision"),
        "sources": [issue["number"] for issue in issues if cfg["labels"]["ready"] not in issue["labels"]],
    }
    ready, in_flight = [], []
    for issue in issues:
        standing = eligibility(issue, cfg, claims, limit=cfg["limits"]["max_ticket_attempts"])
        if standing == "eligible":
            ready.append(issue)
        elif standing in ("claimed", "blocked"):
            in_flight.append(issue["number"])
    if ready:
        pick = sorted(ready, key=queue_key)[0]
        return decide(
            "implement",
            repository=repo,
            ticket=pick["number"],
            title=pick["title"],
            branch=f"{cfg['branch_prefix']}{pick['number']}",
            reason=f"git-loopy pins {str(details['pin'])[:7]}, which lacks the sync closed at {str(last.get('skills'))[:7]}",
            details=details,
        )
    if in_flight:
        return decide("wait", reason=f"git-loopy pin-move ticket(s) in flight: {in_flight}", details=details)
    planned = max((issue.get("attempts", 0) for issue in issues if issue["number"] in details["sources"]), default=0)
    if planned >= cfg["limits"]["max_downstream_plan_attempts"]:
        return decide("blocked", reason=f"git-loopy pin-move planning failed {planned} times", details=details)
    return decide(
        "downstream-plan",
        repository=repo,
        reason=f"git-loopy pins {str(details['pin'])[:7]}, which lacks the sync closed at {str(last.get('skills'))[:7]}",
        details=details,
    )


def control(sensor: dict, cfg: dict) -> dict:
    skills_repo = cfg["skills"]["repository"]
    down_repo = cfg["downstream"]["repository"]
    if sensor.get("errors"):
        return decide("blocked", reason="sensor could not read the system", details={"errors": sensor["errors"]})

    prs = sorted(sensor.get("loop_prs") or [], key=lambda item: (item.get("created_at") or "", item["number"]))
    for pr in prs:
        if pr.get("ticket") is not None and pr.get("ticket_state") == "closed":
            reason = pr.get("ticket_state_reason") or "closed"
            return decide(
                "abandon",
                repository=pr["repository"],
                pull_request=pr["number"],
                ticket=pr["ticket"],
                branch=pr["head_ref"],
                reason=f"ticket #{pr['ticket']} was closed ({reason}), so its pull request is no longer wanted",
            )
    for pr in prs:
        if pr.get("pending_iterate"):
            return decide(
                "iterate",
                repository=pr["repository"],
                pull_request=pr["number"],
                ticket=pr.get("ticket"),
                branch=pr["head_ref"],
                head_sha=pr.get("head_sha"),
                reason=f"/iterate from {pr['pending_iterate'].get('author')}",
                details={"comment": pr["pending_iterate"]},
            )
    if prs:
        return shepherd_pr(prs[0], cfg, sensor["now"])

    blockers = sensor.get("blocked_issues") or []
    if blockers:
        return decide(
            "blocked", reason=f"open blocker #{blockers[0]['number']}: {blockers[0]['title']}", details={"issues": blockers}
        )

    specs = sensor.get("specs") or {}
    open_specs = sorted(specs.get("open") or [], key=lambda item: item["number"])
    for spec in open_specs:
        tickets = spec.get("tickets") or []
        if tickets and all(ticket["state"] == "closed" for ticket in tickets):
            return decide(
                "close-out",
                repository=skills_repo,
                spec=spec["number"],
                reason=f"every ticket of spec #{spec['number']} is closed",
                details={"target": spec.get("target"), "release": spec.get("release"), "skills": sensor.get("skills_main")},
            )

    last = specs.get("last_completed")
    downstream = sensor.get("downstream") or {}
    if last and last.get("skills") and downstream.get("pin_contains_last_sync") is False:
        return downstream_decision(last, downstream, cfg, (sensor.get("claims") or {}).get(down_repo, {}))

    claims = (sensor.get("claims") or {}).get(skills_repo, {})
    censuses = {}
    for spec in open_specs:
        pick, census = select_ticket(spec.get("tickets") or [], cfg, claims)
        if pick:
            return decide(
                "implement",
                repository=skills_repo,
                ticket=pick["number"],
                title=pick["title"],
                spec=spec["number"],
                branch=f"{cfg['branch_prefix']}{pick['number']}",
                reason=f"next ready ticket of spec #{spec['number']}",
                details={"target": spec.get("target"), "release": spec.get("release"), "attempt": pick.get("attempts", 0) + 1},
            )
        censuses[spec["number"]] = census
    if open_specs:
        if any(census["claimed"] for census in censuses.values()):
            return decide("wait", reason="no selectable ticket; others are being worked", details={"census": censuses})
        return decide("blocked", reason="no selectable ticket; the rest need a human", details={"census": censuses})

    gap = sensor.get("release_gap")
    if gap is None:
        if not last:
            return decide("blocked", reason="no sync baseline: label a spec upstream-sync and give it a spec marker")
        return decide("none", reason="no release gap measured")
    if gap["status"] == "gap":
        in_scope = [row for row in gap.get("skills") or [] if row["in_scope"]]
        if in_scope:
            return decide(
                "plan",
                repository=skills_repo,
                reason=f"{gap['release']} carries {len(in_scope)} in-scope skill change(s)",
                details={"gap": gap, "last_completed": last, "downstream_repository": down_repo},
            )
        return decide(
            "record-release",
            repository=skills_repo,
            reason=f"{gap['release']} carries no in-scope skill change",
            details={"gap": gap, "previous_skills": (last or {}).get("skills")},
        )
    return decide("none", reason=f"in sync: {gap['release']} is covered by {gap['base'][:7]}")


# --------------------------------------------------------------------------- deterministic actions


LOOP_LABELS = {
    "sync": ("5319e7", "Tracked by the upstream-sync control loop"),
    "pull_request": ("0E8A16", "Opened by the upstream-sync control loop"),
}


def ensure_label(repo: str, cfg: dict, role: str, dry_run: bool) -> str:
    name = cfg["labels"][role]
    if not dry_run:
        color, description = LOOP_LABELS[role]
        run_gh(["label", "create", name, "--repo", repo, "--color", color, "--description", description, "--force"])
    return name


def comment(repo: str, number: int, body: str, dry_run: bool) -> None:
    if dry_run:
        print(f"[dry-run] comment on {repo}#{number}:\n{body}")
        return
    run_gh(["issue", "comment", str(number), "--repo", repo, "--body", body])


def apply(decision: dict, cfg: dict, dry_run: bool = False) -> str:
    action = decision["action"]
    repo = decision.get("repository")
    if action == "merge":
        args = ["pr", "merge", str(decision["pull_request"]), "--repo", repo, f"--{decision['merge_method']}", "--delete-branch"]
        if decision.get("head_sha"):
            args += ["--match-head-commit", decision["head_sha"]]
        if dry_run:
            return "[dry-run] gh " + " ".join(args)
        run_gh(args)
        return f"merged {repo}#{decision['pull_request']}"
    if action == "close-out":
        details = decision["details"]
        body = (
            f"Every ticket of this spec is closed, so the upstream-sync loop closes it. git-loopy-skills "
            f"`{str(details['skills'])[:12]}` carries mattpocock/skills `{str(details['target'])[:12]}` "
            f"({details.get('release')}). The loop moves git-loopy's skill pin next.\n\n"
            + marker("synced", target=details["target"], release=details.get("release"), skills=details["skills"])
        )
        comment(repo, decision["spec"], body, dry_run)
        if not dry_run:
            run_gh(["issue", "close", str(decision["spec"]), "--repo", repo, "--reason", "completed"])
        return f"closed spec {repo}#{decision['spec']}"
    if action == "record-release":
        gap = decision["details"]["gap"]
        rows = "\n".join(
            f"| `{row['skill']}` | {row['change']} | {row['from_bucket'] or ''} → {row['bucket']} |" for row in gap.get("skills") or []
        )
        body = (
            f"mattpocock/skills {gap['release']} (`{gap['head'][:12]}`) changes no skill in this repo's scope "
            f"(`.github/upstream-sync.json`), so there is nothing to sync.\n\n"
            f"| Upstream skill | Change | Bucket |\n| --- | --- | --- |\n{rows}\n\n"
            + marker("spec", target=gap["head"], release=gap["release"])
        )
        title = f"Spec: Record mattpocock/skills {gap['release']} (no in-scope changes)"
        if dry_run:
            return f"[dry-run] create and close '{title}'"
        label = ensure_label(repo, cfg, "sync", dry_run)
        number = number_from_url(run_gh(["issue", "create", "--repo", repo, "--title", title, "--body", body, "--label", label]))
        previous = decision["details"].get("previous_skills")
        comment(repo, number, marker("synced", target=gap["head"], release=gap["release"], skills=previous), dry_run)
        run_gh(["issue", "close", str(number), "--repo", repo, "--reason", "completed"])
        return f"recorded {gap['release']} as {repo}#{number}"
    if action == "abandon":
        body = (
            f"**Upstream-sync loop:** {decision['reason']}. Closing it; reopen the ticket and this pull "
            f"request if that was a mistake."
        )
        if dry_run:
            return f"[dry-run] close {repo}#{decision['pull_request']}: {body}"
        run_gh(["pr", "close", str(decision["pull_request"]), "--repo", repo, "--comment", body])
        return f"closed {repo}#{decision['pull_request']}"
    if action == "blocked" and decision.get("pause") and decision.get("pull_request"):
        body = (
            f"**Upstream-sync loop:** {decision['reason']}. The loop will not touch this PR again until a "
            f"maintainer comments `/iterate <feedback>`, fixes it, or closes it.\n\n"
            + marker("paused", pr=decision["pull_request"])
        )
        comment(repo, decision["pull_request"], body, dry_run)
        return f"paused {repo}#{decision['pull_request']}"
    return f"{action}: nothing to apply"


def shepherd(cfg: dict, repo_root: Path, dry_run: bool) -> tuple:
    steps = []
    decision = None
    for _ in range(cfg["limits"]["deterministic_steps_per_run"]):
        sensor = sense(cfg, repo_root)
        decision = control(sensor, cfg)
        if decision["action"] in DETERMINISTIC_ACTIONS:
            try:
                outcome = apply(decision, cfg, dry_run)
            except LoopError as error:
                steps.append({"decision": decision, "outcome": f"failed: {error}"})
                decision = decide("blocked", reason=f"{decision['action']} failed: {error}")
                break
            steps.append({"decision": decision, "outcome": outcome})
            if dry_run:
                break
            continue
        if decision["action"] == "blocked" and decision.get("pause") and not sensor_paused(sensor, decision):
            steps.append({"decision": decision, "outcome": apply(decision, cfg, dry_run)})
        else:
            steps.append({"decision": decision, "outcome": "handed on"})
        break
    return decision, steps


def sensor_paused(sensor: dict, decision: dict) -> bool:
    for pr in sensor.get("loop_prs") or []:
        if pr["number"] == decision.get("pull_request") and pr["repository"] == decision.get("repository"):
            return bool(pr.get("paused"))
    return False


def summary_markdown(steps: list) -> str:
    lines = ["### Upstream-sync loop", "", "| Step | Action | Target | Reason | Outcome |", "| --- | --- | --- | --- | --- |"]
    for index, step in enumerate(steps, 1):
        decision = step["decision"]
        target = decision.get("repository", "")
        if decision.get("pull_request"):
            target += f" PR #{decision['pull_request']}"
        elif decision.get("ticket"):
            target += f" #{decision['ticket']}"
        elif decision.get("spec"):
            target += f" spec #{decision['spec']}"
        reason = str(decision.get("reason", "")).replace("|", "\\|")
        lines.append(f"| {index} | `{decision['action']}` | {target} | {reason} | {step['outcome']} |")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------- manual decisions


def manual_implement(cfg: dict, repo: str, ticket: int) -> dict:
    issue = gh_api(f"repos/{repo}/issues/{ticket}")
    if issue.get("state") != "open" or "pull_request" in issue:
        raise LoopError(f"{repo}#{ticket} is not an open issue")
    return decide(
        "implement",
        repository=repo,
        ticket=ticket,
        title=issue["title"],
        branch=f"{cfg['branch_prefix']}{ticket}",
        reason="manual dispatch",
        details={"manual": True},
    )


def iterate_refusal(request: dict) -> str | None:
    """Why a comment-triggered /iterate must not run, or None when it should.

    The scheduled path reaches the same answers through the sensor; this keeps a
    comment run from iterating a PR the loop does not own, has closed, or has
    already answered.
    """
    if not request["ours"]:
        return "the pull request was not opened by the loop"
    if request["pr_state"] != "open":
        return "the pull request is closed"
    if request.get("ticket") and request.get("ticket_state") == "closed":
        return f"ticket #{request['ticket']} is closed; the next scheduled run closes its pull request"
    if request["answered"]:
        return f"/iterate {request['comment_id']} was already answered"
    return None


def manual_iterate(cfg: dict, repo: str, number: int, comment_id: str, comment_body: str) -> dict:
    pr = gh_api(f"repos/{repo}/pulls/{number}")
    trusted = current_login()
    head = pr.get("head") or {}
    ticket = ticket_from_branch(head.get("ref", ""), cfg["branch_prefix"])
    marked = f"<!-- git-loopy-agent:workflow={cfg['workflow_id']};" in (pr.get("body") or "")
    request = {
        "ours": marked
        and is_loop_pr(
            head.get("ref", ""),
            (pr.get("user") or {}).get("login"),
            (head.get("repo") or {}).get("full_name") != repo,
            [label["name"] for label in pr.get("labels") or []],
            cfg,
            trusted,
        ),
        "pr_state": pr.get("state"),
        "ticket": ticket,
        "ticket_state": gh_api(f"repos/{repo}/issues/{ticket}").get("state") if ticket else None,
        "comment_id": comment_id,
        "answered": str(comment_id) in answered_iterates(comments_of(repo, number), trusted),
    }
    refusal = iterate_refusal(request)
    if refusal:
        return decide("none", reason=f"{repo}#{number}: {refusal}")
    return decide(
        "iterate",
        repository=repo,
        pull_request=number,
        ticket=ticket,
        branch=head["ref"],
        head_sha=head.get("sha"),
        reason="/iterate comment",
        details={"comment": {"id": comment_id, "body": comment_body}},
    )


# --------------------------------------------------------------------------- actuation: start, prompt, finish


def git(cwd: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise LoopError(f"git {' '.join(args[:2])} failed: {result.stderr.strip()[:400]}")
    return result.stdout.strip()


def ensure_clone(repo: str, root: Path) -> Path:
    target = root / repo.split("/", 1)[1]
    if not (target / ".git").exists():
        run_gh(["repo", "clone", repo, str(target), "--", "--quiet"])
    git(target, "fetch", "--quiet", "--prune", "origin")
    return target


def install_catalog(repo_root: Path, copilot_home: Path) -> list:
    """Copy (never link) the catalog and the loop's own skills into the agent's skill root.

    A copy, so a ticket that edits a skill cannot change the skill running it.
    """
    destination = copilot_home / "skills"
    destination.mkdir(parents=True, exist_ok=True)
    installed = []
    sources = [repo_root / "skills", repo_root / ".github" / "skills"]
    for skill in sorted(path for source in sources if source.is_dir() for path in source.iterdir()):
        if not (skill / "SKILL.md").is_file():
            continue
        target = destination / skill.name
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        shutil.copytree(skill, target)
        installed.append(skill.name)
    record = repo_root / "scripts" / "review-clean-record.py"
    if record.is_file():
        (copilot_home / "scripts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(record, copilot_home / "scripts" / record.name)
    return installed


def run_marker_fields() -> dict:
    return {"run": os.environ.get("GITHUB_RUN_ID") or "local"}


def run_link() -> str:
    server, repo, run = (os.environ.get(name) for name in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID"))
    return f"{server}/{repo}/actions/runs/{run}" if server and repo and run else "a local run"


def pre_push_hook(protected: list) -> str:
    """A git pre-push hook refusing every push to a protected branch: the loop only ever opens PRs."""
    cases = " | ".join(f"refs/heads/{branch}" for branch in protected)
    return (
        "#!/bin/sh\n"
        "# Installed by scripts/upstream-sync.py start: the loop never pushes a default branch.\n"
        "while read -r local_ref local_sha remote_ref remote_sha; do\n"
        '  case "$remote_ref" in\n'
        f"    {cases})\n"
        '      echo "upstream-sync: refusing to push $remote_ref; push your own branch and open a pull request" >&2\n'
        "      exit 1 ;;\n"
        "  esac\n"
        "done\n"
        "exit 0\n"
    )


def guard_pushes(clone: Path, protected: list) -> None:
    hooks = Path(git(clone, "rev-parse", "--git-path", "hooks"))
    if not hooks.is_absolute():
        hooks = clone / hooks
    hooks.mkdir(parents=True, exist_ok=True)
    hook = hooks / "pre-push"
    hook.write_text(pre_push_hook(protected), encoding="utf-8")
    hook.chmod(0o755)


def start(decision: dict, cfg: dict, root: Path, install_skills: bool, copilot_home: Path, dry_run: bool) -> dict:
    action = decision["action"]
    if action not in AGENT_ACTIONS:
        raise LoopError(f"start: {action} is not an agent action")
    repo = decision["repository"]
    root.mkdir(parents=True, exist_ok=True)
    work = ensure_clone(repo, root)
    base = repo_settings(repo, cfg)["default_branch"]
    guard_pushes(work, [base])
    if action == "implement":
        branch = decision["branch"]
        remote = git(work, "ls-remote", "--heads", "origin", branch)
        if remote:
            open_prs = open_prs_for_branch(repo, branch)
            if open_prs:
                raise LoopError(f"{branch} already has open PR #{open_prs[0]['number']}; shepherd it instead")
            if not dry_run:
                git(work, "push", "--quiet", "origin", "--delete", branch)
        git(work, "checkout", "--quiet", "--no-track", "-B", branch, f"origin/{base}")
    elif action in ("fix", "iterate"):
        git(work, "checkout", "--quiet", "-B", decision["branch"], f"origin/{decision['branch']}")
    else:
        git(work, "checkout", "--quiet", "--detach", f"origin/{base}")
    result = {"work": str(work)}
    if repo == cfg["downstream"]["repository"]:
        skills = ensure_clone(cfg["skills"]["repository"], root)
        guard_pushes(skills, [cfg["skills"]["default_branch"]])
        revision = (decision.get("details") or {}).get("publish_revision") or f"origin/{cfg['skills']['default_branch']}"
        git(skills, "checkout", "--quiet", "--detach", revision)
        result["skills_checkout"] = str(skills)
    if install_skills:
        result["installed_skills"] = install_catalog(REPO_ROOT, copilot_home)
    fields = run_marker_fields()
    if action == "implement":
        attempt = (decision.get("details") or {}).get("attempt")
        body = f"The upstream-sync loop is implementing this ticket on `{decision['branch']}` ({run_link()})."
        comment(repo, decision["ticket"], body + "\n\n" + marker("attempt", ticket=decision["ticket"], n=attempt, **fields), dry_run)
    elif action == "fix":
        body = f"The upstream-sync loop is fixing this PR: {decision.get('reason')} ({run_link()})."
        comment(repo, decision["pull_request"], body + "\n\n" + marker("fix-attempt", pr=decision["pull_request"], **fields), dry_run)
    elif action == "downstream-plan":
        for source in (decision.get("details") or {}).get("sources") or []:
            body = f"The upstream-sync loop is planning git-loopy's skill-pin move from this issue ({run_link()})."
            comment(repo, source, body + "\n\n" + marker("attempt", ticket=source, **fields), dry_run)
    return result


def selected_work_markdown(decision: dict, cfg: dict, workspace: dict | None = None) -> str:
    action = decision["action"]
    details = decision.get("details") or {}
    lines = [f"- **Action:** `{action}`", f"- **Why:** {decision.get('reason', '')}"]
    if decision.get("repository"):
        lines.append(f"- **Repository:** `{decision['repository']}`")
    if decision.get("ticket"):
        lines.append(f"- **Ticket:** #{decision['ticket']} {decision.get('title', '')}".rstrip())
    if decision.get("spec"):
        lines.append(f"- **Spec:** #{decision['spec']}")
    if details.get("target"):
        lines.append(f"- **Upstream pin:** mattpocock/skills `{details['target']}` ({details.get('release')})")
    if decision.get("pull_request"):
        lines.append(f"- **Pull request:** #{decision['pull_request']} at `{decision.get('head_sha', '')}`")
    if decision.get("branch"):
        lines.append(f"- **Branch:** `{decision['branch']}` (checked out for you; push only to it)")
    if workspace:
        lines.append(f"- **Working tree:** `{workspace.get('work')}`")
        if workspace.get("skills_checkout"):
            lines.append(f"- **git-loopy-skills checkout (published revision, detached):** `{workspace['skills_checkout']}`")
    if action == "implement":
        base = repo_settings(decision["repository"], cfg)["default_branch"]
        lines.append(
            f"- **Open the PR** right after the first push, before the review: `gh pr create --repo "
            f"{decision['repository']} --base {base} --head {decision['branch']} --title \"[upstream-sync] "
            f"{decision.get('title', '')}\" --body \"Closes #{decision['ticket']}\"`"
        )
        if details.get("attempt"):
            lines.append(f"- **Attempt:** {details['attempt']} of {cfg['limits']['max_ticket_attempts']}")
    if action == "fix":
        lines.append(f"- **Missing merge evidence:** {', '.join(details.get('missing') or [])}")
        lines.append(f"- **Mergeable:** {details.get('mergeable')}")
        lines.append(f"- **Attempt:** {details.get('attempt')} of {cfg['limits']['max_fix_attempts']}")
    if action == "iterate":
        feedback = (details.get("comment") or {}).get("body", "")
        lines.append(f"- **Maintainer feedback:**\n\n> " + feedback.replace("\n", "\n> "))
    if action == "plan":
        gap = details["gap"]
        lines.append(f"- **Release:** mattpocock/skills {gap['release']} (`{gap['head']}`), base `{gap['base']}`")
        lines.append(f"- **Downstream repository:** `{details.get('downstream_repository')}`")
        lines.append("")
        lines.append("| Upstream skill | Change | Bucket | Counterpart here | In scope |")
        lines.append("| --- | --- | --- | --- | --- |")
        for row in gap.get("skills") or []:
            bucket = f"{row['from_bucket']} → {row['bucket']}" if row.get("from_bucket") and row["from_bucket"] != row["bucket"] else row["bucket"]
            lines.append(
                f"| `{row['skill']}` | {row['change']} | {bucket} | {('`' + row['local'] + '`') if row.get('local') else 'none'} | "
                f"{'yes' if row['in_scope'] else 'no'} |"
            )
    if action in ("downstream-plan",) or (action == "implement" and decision.get("repository") == cfg["downstream"]["repository"]):
        last = details.get("last_sync") or {}
        lines.append(f"- **Completed sync:** spec #{last.get('number')} → mattpocock/skills `{last.get('target')}` ({last.get('release')})")
        lines.append(f"- **git-loopy pins:** `{details.get('pin')}`")
        lines.append(f"- **Publish revision to prove and pin:** git-loopy-skills `{details.get('publish_revision')}`")
        if details.get("sources"):
            lines.append(f"- **Source issue(s):** {', '.join('#' + str(number) for number in details['sources'])}")
    return "\n".join(lines) + "\n"


def load_iteration_helper():
    path = REPO_ROOT / "scripts" / "agent-iteration.py"
    spec = importlib.util.spec_from_file_location("agent_iteration", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def build_prompt(decision: dict, cfg: dict, repo_root: Path, workspace: dict | None = None) -> str:
    template = (repo_root / cfg["prompt_path"]).read_text(encoding="utf-8").rstrip()
    memory_path = repo_root / cfg["memory_path"]
    memory = memory_path.read_text(encoding="utf-8").strip() if memory_path.is_file() else "(empty)"
    parts = [template, "## Selected work (controller output)", selected_work_markdown(decision, cfg, workspace).rstrip()]
    if decision["action"] == "iterate":
        helper = load_iteration_helper()
        parts.append("## Iteration context")
        parts.append(
            helper.render_iteration_prompt(
                workflow=cfg["workflow_id"],
                memory_path=cfg["memory_path"],
                repo=decision["repository"],
                pr_number=decision["pull_request"],
                comment_body=(decision.get("details") or {}).get("comment", {}).get("body", ""),
                memory_text=memory,
                trusted_associations=cfg["trusted_associations"],
            ).rstrip()
        )
    parts += ["## Agent memory", memory]
    return "\n\n".join(parts) + "\n"


def pr_footer(cfg: dict) -> str:
    return load_iteration_helper().render_footer(cfg["workflow_id"], cfg["memory_path"])


def open_prs_for_branch(repo: str, branch: str) -> list:
    """Open pull requests from this repository's `branch`; a fork's branch of the same name is not one."""
    prs = gh_json(
        "pr", "list", "--repo", repo, "--head", branch, "--state", "open", "--json",
        "number,url,headRefOid,author,isCrossRepository",
    ) or []
    return [pr for pr in prs if not pr.get("isCrossRepository")]


def find_open_pr(repo: str, branch: str) -> dict | None:
    """The loop's own open pull request for `branch`."""
    trusted = current_login()
    for pr in open_prs_for_branch(repo, branch):
        if (pr.get("author") or {}).get("login") == trusted:
            return pr
    return None


def wait_for_checks(repo: str, number: int, timeout: int) -> str:
    deadline = time.time() + timeout
    while True:
        view = gh_json("pr", "view", str(number), "--repo", repo, "--json", "statusCheckRollup") or {}
        rollup = view.get("statusCheckRollup") or []
        pending = [
            check
            for check in rollup
            if (check.get("status") or "").upper() in PENDING_CHECK_STATES
            or (check.get("state") or "").upper() in PENDING_CHECK_STATES
        ]
        if rollup and not pending:
            return "checks complete"
        if time.time() >= deadline:
            return "timed out waiting for checks"
        time.sleep(30)


def open_blocker(cfg: dict, title: str, body: str, dry_run: bool) -> str:
    repo = cfg["skills"]["repository"]
    full = body.rstrip() + f"\n\nRun: {run_link()}\n\nClose this issue to let the loop continue.\n\n" + marker("blocked")
    if dry_run:
        return f"[dry-run] open blocker '{title}'"
    label = ensure_label(repo, cfg, "sync", dry_run)
    url = run_gh(
        ["issue", "create", "--repo", repo, "--title", title, "--body", full, "--label", label, "--label", cfg["labels"]["triage"]]
    ).strip()
    return f"opened blocker {url}"


def finish(decision: dict, cfg: dict, body: str, wait_checks: int, dry_run: bool, repo_root: Path) -> str:
    action = decision["action"]
    repo = decision.get("repository")
    message = body.strip() or "The agent produced no final message; see the run's agent-output artifact."
    if action == "implement":
        pr = find_open_pr(repo, decision["branch"])
        base = repo_settings(repo, cfg)["default_branch"]
        if pr is None:
            ahead = git_remote_ahead(repo, base, decision["branch"])
            if not ahead:
                return fail_ticket(decision, cfg, message, dry_run)
            if dry_run:
                return f"[dry-run] would open a PR for {decision['branch']}"
            url = run_gh(
                ["pr", "create", "--repo", repo, "--base", base, "--head", decision["branch"],
                 "--title", f"[upstream-sync] {decision.get('title', '')}", "--body", f"Closes #{decision['ticket']}"]
            ).strip()
            pr = {"number": number_from_url(url), "url": url}
        closes = [decision["ticket"]] + list((decision.get("details") or {}).get("sources") or [])
        closing = ", ".join(f"closes #{number}" for number in closes)
        full = f"{message}\n\n{closing[0].upper()}{closing[1:]}\n\n{pr_footer(cfg)}\n"
        if dry_run:
            return f"[dry-run] would set the body of {repo}#{pr['number']}:\n{full}"
        label = ensure_label(repo, cfg, "pull_request", dry_run)
        run_gh(["pr", "edit", str(pr["number"]), "--repo", repo, "--body", full, "--add-label", label])
        outcome = f"PR {repo}#{pr['number']} labelled and described"
        if wait_checks:
            outcome += "; " + wait_for_checks(repo, pr["number"], wait_checks)
        return outcome
    if action in ("fix", "iterate"):
        header = "**Upstream-sync loop:** " + ("fix attempt" if action == "fix" else "iterated on the feedback above")
        reply = f"{header}\n\n{message}"
        if action == "iterate":
            comment_id = ((decision.get("details") or {}).get("comment") or {}).get("id")
            reply += "\n\n" + marker("iterate-reply", comment=comment_id)
        comment(repo, decision["pull_request"], reply, dry_run)
        outcome = f"replied on {repo}#{decision['pull_request']}"
        if wait_checks and not dry_run:
            outcome += "; " + wait_for_checks(repo, decision["pull_request"], wait_checks)
        return outcome
    if action == "plan":
        specs = read_specs(repo, cfg, current_login())
        target = decision["details"]["gap"]["head"]
        if any(spec.get("target") == target for spec in specs["open"]):
            return "planned: a spec now targets " + target[:12]
        return open_blocker(cfg, f"Upstream sync blocked: planning {decision['details']['gap']['release']} produced no spec", message, dry_run)
    if action == "downstream-plan":
        issues = read_downstream_issues(cfg, current_login())
        planned = [issue["number"] for issue in issues if eligibility(issue, cfg, {}) not in ("closed", "not_ready")]
        if planned:
            return f"planned: git-loopy ticket(s) {planned} ready"
        return "planning produced no ready git-loopy ticket; the next run retries or blocks"
    return f"{action}: nothing to finish"


def git_remote_ahead(repo: str, base: str, branch: str) -> bool:
    try:
        status = gh_api(f"repos/{repo}/compare/{base}...{branch}")
    except LoopError:
        return False
    return status.get("ahead_by", 0) > 0


def fail_ticket(decision: dict, cfg: dict, message: str, dry_run: bool) -> str:
    repo, ticket = decision["repository"], decision["ticket"]
    attempts = count_markers(comments_of(repo, ticket), "attempt", current_login())
    if attempts < cfg["limits"]["max_ticket_attempts"]:
        return f"no PR for #{ticket} (attempt {attempts}); the next run may retry"
    body = (
        f"The upstream-sync loop could not produce a pull request for this ticket in {attempts} attempts, "
        f"so it moves the ticket to `{cfg['labels']['human']}`. Last run: {run_link()}.\n\n"
        f"<details><summary>Agent's final message</summary>\n\n{message}\n\n</details>"
    )
    comment(repo, ticket, body, dry_run)
    if not dry_run:
        run_gh(["issue", "edit", str(ticket), "--repo", repo, "--remove-label", cfg["labels"]["ready"], "--add-label", cfg["labels"]["human"]])
    return f"#{ticket} moved to {cfg['labels']['human']} after {attempts} attempts"


# --------------------------------------------------------------------------- CLI


def read_json(path: str) -> dict:
    if path == "-":
        return json.load(sys.stdin)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def emit(data: object, out: str | None) -> None:
    text = json.dumps(data, indent=2, sort_keys=True) + "\n"
    if out:
        Path(out).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


def main(argv: list | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("sense").add_argument("--out")
    control_parser = sub.add_parser("control")
    control_parser.add_argument("sensor")
    control_parser.add_argument("--out")
    apply_parser = sub.add_parser("apply")
    apply_parser.add_argument("decision")
    apply_parser.add_argument("--dry-run", action="store_true")
    shepherd_parser = sub.add_parser("shepherd")
    shepherd_parser.add_argument("--out")
    shepherd_parser.add_argument("--summary")
    shepherd_parser.add_argument("--dry-run", action="store_true")
    decide_parser = sub.add_parser("decide")
    decide_sub = decide_parser.add_subparsers(dest="kind", required=True)
    implement_parser = decide_sub.add_parser("implement")
    implement_parser.add_argument("--ticket", type=int, required=True)
    implement_parser.add_argument("--repo")
    implement_parser.add_argument("--out")
    iterate_parser = decide_sub.add_parser("iterate")
    iterate_parser.add_argument("--repo", required=True)
    iterate_parser.add_argument("--pr", type=int, required=True)
    iterate_parser.add_argument("--comment-id", required=True)
    iterate_parser.add_argument("--comment-body", required=True)
    iterate_parser.add_argument("--out")
    start_parser = sub.add_parser("start")
    start_parser.add_argument("decision")
    start_parser.add_argument("--root", required=True)
    start_parser.add_argument("--install-skills", action="store_true")
    start_parser.add_argument("--copilot-home", default=os.environ.get("COPILOT_HOME") or str(Path.home() / ".copilot"))
    start_parser.add_argument("--out")
    start_parser.add_argument("--dry-run", action="store_true")
    prompt_parser = sub.add_parser("prompt")
    prompt_parser.add_argument("decision")
    prompt_parser.add_argument("--workspace")
    finish_parser = sub.add_parser("finish")
    finish_parser.add_argument("decision")
    finish_parser.add_argument("--body", required=True)
    finish_parser.add_argument("--wait-checks", type=int, default=0)
    finish_parser.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    cfg = load_config(Path(args.config))
    try:
        if args.command == "sense":
            emit(sense(cfg, REPO_ROOT), args.out)
        elif args.command == "control":
            emit(control(read_json(args.sensor), cfg), args.out)
        elif args.command == "apply":
            print(apply(read_json(args.decision), cfg, args.dry_run))
        elif args.command == "shepherd":
            decision, steps = shepherd(cfg, REPO_ROOT, args.dry_run)
            emit(decision, args.out)
            if args.summary:
                with open(args.summary, "a", encoding="utf-8") as handle:
                    handle.write(summary_markdown(steps))
            else:
                sys.stderr.write(summary_markdown(steps))
        elif args.command == "decide":
            if args.kind == "implement":
                emit(manual_implement(cfg, args.repo or cfg["skills"]["repository"], args.ticket), args.out)
            else:
                emit(manual_iterate(cfg, args.repo, args.pr, args.comment_id, args.comment_body), args.out)
        elif args.command == "start":
            emit(
                start(read_json(args.decision), cfg, Path(args.root), args.install_skills, Path(args.copilot_home), args.dry_run),
                args.out,
            )
        elif args.command == "prompt":
            workspace = read_json(args.workspace) if args.workspace else None
            sys.stdout.write(build_prompt(read_json(args.decision), cfg, REPO_ROOT, workspace))
        elif args.command == "finish":
            body = Path(args.body).read_text(encoding="utf-8") if Path(args.body).is_file() else ""
            print(finish(read_json(args.decision), cfg, body, args.wait_checks, args.dry_run, REPO_ROOT))
    except LoopError as error:
        print(f"upstream-sync: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
