#!/usr/bin/env python3
"""Shared /iterate helper for recurring coding-agent workflows.

A Python port of design-control-loop's `references/agent-iteration.ts`, so the
loops in this repository need no extra runtime. Same modes, same marker:

`footer` appends visible /iterate instructions plus a hidden workflow marker to
an agent-created PR body. The marker is what lets many workflows listen for the
same /iterate command while only the workflow that opened the PR continues.

`prompt` builds the iteration prompt once the workflow has checked out the PR
branch: the raw PR context plus the workflow memory file, asking the agent to
update the PR and distill durable guidance back into that memory file.

    scripts/agent-iteration.py --command footer --workflow ID --memory PATH
    scripts/agent-iteration.py --command prompt --workflow ID --memory PATH \\
        --repo OWNER/REPO --pr-number N --comment-body BODY
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Comments from anyone else on a public repository are left out of the prompt: the
# agent acts on them with a write token.
DEFAULT_TRUSTED = ("OWNER", "MEMBER", "COLLABORATOR")


def marker(workflow: str, memory: str) -> str:
    return f"<!-- git-loopy-agent:workflow={workflow};memory={memory};version=1 -->"


def render_footer(workflow: str, memory: str) -> str:
    return "\n".join(
        [
            "---",
            "",
            "### Iterating on this agent run",
            "",
            "This PR was opened by a coding agent workflow. Maintainers can comment:",
            "",
            "- `/iterate <feedback>` to ask the same workflow to update this PR and learn durable guidance for future runs.",
            "",
            "The workflow stores durable feedback in its agent memory file and injects that memory into future runs.",
            "",
            marker(workflow, memory),
        ]
    )


def strip_iterate_command(body: str) -> str:
    stripped = re.sub(r"^/iterate\b\s*", "", body.strip(), flags=re.IGNORECASE).strip()
    return stripped or "Iterate on this PR using the available feedback."


def gh_api_json(path: str, paginate: bool = False):
    args = ["gh", "api", path]
    if paginate:
        args[2:2] = ["--paginate", "--slurp"]
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    data = json.loads(out) if out.strip() else None
    if paginate:
        return [item for page in data or [] for item in (page if isinstance(page, list) else [page])]
    return data


def format_issue_comments(comments: list) -> str:
    if not comments:
        return "(no issue comments)"
    return "\n\n---\n\n".join(
        f"Comment {comment.get('id')} by {(comment.get('user') or {}).get('login', 'unknown')} at "
        f"{comment.get('created_at', 'unknown time')}:\n\n{comment.get('body') or ''}"
        for comment in comments
    )


def format_review_comments(comments: list) -> str:
    if not comments:
        return "(no review comments)"
    return "\n\n---\n\n".join(
        f"Review comment {comment.get('id')} by {(comment.get('user') or {}).get('login', 'unknown')} on "
        f"{comment.get('path', 'unknown path')}:{comment.get('line') or comment.get('original_line') or 'unknown line'} "
        f"at {comment.get('created_at', 'unknown time')}:\n\n{comment.get('body') or ''}"
        for comment in comments
    )


def trusted_only(comments: list, trusted_associations) -> tuple:
    kept = [comment for comment in comments or [] if comment.get("author_association") in trusted_associations]
    return kept, len(comments or []) - len(kept)


def render_iteration_prompt(
    workflow: str,
    memory_path: str,
    repo: str,
    pr_number: int,
    comment_body: str,
    memory_text: str | None = None,
    fetch=gh_api_json,
    trusted_associations=DEFAULT_TRUSTED,
) -> str:
    if memory_text is None:
        path = Path(memory_path)
        memory_text = path.read_text(encoding="utf-8") if path.is_file() else ""
    pr = fetch(f"repos/{repo}/pulls/{pr_number}")
    issue_comments, omitted_issue = trusted_only(
        fetch(f"repos/{repo}/issues/{pr_number}/comments?per_page=100", paginate=True), trusted_associations
    )
    review_comments, omitted_review = trusted_only(
        fetch(f"repos/{repo}/pulls/{pr_number}/comments?per_page=100", paginate=True), trusted_associations
    )
    omitted = omitted_issue + omitted_review
    omitted_note = f"\n\n({omitted} comment(s) from other accounts omitted.)" if omitted else ""
    return f"""# Iteration Request

{strip_iterate_command(comment_body)}

# Workflow Identity

- Workflow: {workflow}
- Agent memory file: {memory_path}

# Instructions

You are iterating on an open PR that was created by this coding agent workflow.

1. Treat the Iteration Request as the user's current instruction.
2. Update this PR branch if the feedback asks for a code, workflow, prompt, or documentation change.
3. Distill durable feedback into {memory_path} when it should influence future scheduled/manual runs of this workflow.
4. Keep {memory_path} concise and human-readable. Do not append raw transcripts or one-off PR details.
5. If the feedback is only PR-specific, update the PR but do not add it to memory.
6. Commit and push any changes you make.
7. Finish with a concise GitHub-flavored markdown summary of what changed and whether memory was updated.

# Current Agent Memory

{memory_text.strip() or "(memory file is empty or missing)"}

# Pull Request

- Number: #{pr.get("number")}
- Title: {pr.get("title")}
- State: {pr.get("state")}
- Base: {(pr.get("base") or {}).get("ref", "(unknown)")}
- Head: {(pr.get("head") or {}).get("ref", "(unknown)")}

## PR Body

{pr.get("body") or "(empty)"}

# PR Issue Comments

{format_issue_comments(issue_comments)}

# PR Review Comments

{format_review_comments(review_comments)}{omitted_note}
"""


def main(argv: list | None = None) -> int:
    parser = argparse.ArgumentParser(description="Shared /iterate helper for recurring coding-agent workflows.")
    parser.add_argument("--command", choices=("footer", "prompt"), required=True)
    parser.add_argument("--workflow", required=True)
    parser.add_argument("--memory", required=True)
    parser.add_argument("--repo")
    parser.add_argument("--pr-number")
    parser.add_argument("--comment-body", default="")
    args = parser.parse_args(argv)
    if args.command == "footer":
        sys.stdout.write(render_footer(args.workflow, args.memory))
        return 0
    if not args.repo or not args.pr_number:
        parser.error("--repo and --pr-number are required for prompt")
    sys.stdout.write(render_iteration_prompt(args.workflow, args.memory, args.repo, int(args.pr_number), args.comment_body))
    return 0


if __name__ == "__main__":
    sys.exit(main())
