#!/usr/bin/env python3
"""Resolve chain target spellings to one issue-backed identity."""

import json
import os
import re
import subprocess
import sys
import urllib.parse


def resolution_failure():
    print(json.dumps({
        "canonical_target": None,
        "equivalent_targets": [],
        "error": "target-resolution-failed",
    }, separators=(",", ":"), sort_keys=True))
    raise SystemExit(0)


def repository_coordinates(repo_root):
    repo = os.environ.get("GH_REPO", "")
    host = os.environ.get("GH_HOST", "")
    if repo:
        parts = repo.strip("/").split("/")
        if len(parts) == 3:
            host, owner, name = parts
        elif len(parts) == 2:
            owner, name = parts
        else:
            resolution_failure()
        return host, owner, name.removesuffix(".git")

    remote = subprocess.run(
        ["git", "-C", repo_root, "config", "--get", "remote.origin.url"],
        capture_output=True,
        text=True,
    )
    if remote.returncode or not remote.stdout.strip():
        resolution_failure()

    remote_url = remote.stdout.strip()
    if "://" in remote_url:
        parsed = urllib.parse.urlparse(remote_url)
        host = parsed.hostname or ""
        path = parsed.path
    else:
        match = re.fullmatch(r"(?:[^@]+@)?([^:]+):(.+)", remote_url)
        if not match:
            resolution_failure()
        host, path = match.groups()

    parts = path.strip("/").split("/")
    if len(parts) != 2:
        resolution_failure()
    owner, name = parts
    return host, owner, name.removesuffix(".git")


def local_identity(target):
    issue = re.fullmatch(r"issue-(\d+)", target, re.IGNORECASE)
    if issue:
        return f"issue-{int(issue.group(1))}", None
    if target.isdigit():
        return None, int(target)
    return target, None


def load_targets(ledger_path, requested_target):
    targets = [requested_target]
    if os.path.exists(ledger_path):
        try:
            with open(ledger_path, encoding="utf-8") as ledger:
                for line in ledger:
                    if not line.strip():
                        continue
                    target = json.loads(line).get("target")
                    if isinstance(target, str) and target:
                        targets.append(target)
        except json.JSONDecodeError as error:
            print(f"error: invalid spawn ledger: {error}", file=sys.stderr)
            raise SystemExit(2)
    return list(dict.fromkeys(targets))


def lookup_numeric_targets(numbers, repo_root):
    if not numbers:
        return {}

    host, owner, name = repository_coordinates(repo_root)
    aliases = {
        number: f"target{index}"
        for index, number in enumerate(sorted(numbers))
    }
    fields = " ".join(
        (
            f"{alias}:issueOrPullRequest(number:{number}){{"
            "__typename "
            "... on Issue{number} "
            "... on PullRequest{closingIssuesReferences(first:10){nodes{number}}}"
            "}"
        )
        for number, alias in aliases.items()
    )
    query = (
        "query($owner:String!,$name:String!){"
        "repository(owner:$owner,name:$name){"
        f"{fields}"
        "}}"
    )
    command = ["gh", "api", "graphql"]
    if host and host != "github.com":
        command.extend(["--hostname", host])
    command.extend([
        "-F", f"owner={owner}",
        "-F", f"name={name}",
        "-f", f"query={query}",
    ])

    try:
        response = subprocess.run(
            command,
            capture_output=True,
            cwd=repo_root,
            text=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        resolution_failure()
    if response.returncode:
        resolution_failure()

    try:
        payload = json.loads(response.stdout)
        repository = payload["data"]["repository"]
    except (json.JSONDecodeError, KeyError, TypeError):
        resolution_failure()
    if payload.get("errors") or not isinstance(repository, dict):
        resolution_failure()

    identities = {}
    for number, alias in aliases.items():
        node = repository.get(alias)
        if node is None:
            identities[number] = f"issue-{number}"
            continue
        if not isinstance(node, dict):
            resolution_failure()
        if node.get("__typename") == "Issue":
            issue_number = node.get("number")
            if not isinstance(issue_number, int):
                resolution_failure()
            identities[number] = f"issue-{issue_number}"
            continue
        if node.get("__typename") != "PullRequest":
            resolution_failure()

        references = node.get("closingIssuesReferences")
        if not isinstance(references, dict):
            resolution_failure()
        nodes = references.get("nodes")
        if not isinstance(nodes, list):
            resolution_failure()
        issue_numbers = {
            reference.get("number")
            for reference in nodes
            if isinstance(reference, dict)
            and isinstance(reference.get("number"), int)
        }
        if len(issue_numbers) != 1:
            resolution_failure()
        identities[number] = f"issue-{issue_numbers.pop()}"

    return identities


def main():
    if len(sys.argv) != 3:
        raise SystemExit(2)

    ledger_path, requested_target = sys.argv[1:]
    targets = load_targets(ledger_path, requested_target)
    local_identities = {}
    lookup_numbers = set()
    for target in targets:
        identity, lookup_number = local_identity(target)
        local_identities[target] = identity
        if lookup_number is not None:
            lookup_numbers.add(lookup_number)

    looked_up_identities = lookup_numeric_targets(lookup_numbers, os.getcwd())
    resolved = {}
    for target in targets:
        identity = local_identities[target]
        if identity is None:
            identity = looked_up_identities[int(target)]
        resolved[target] = identity

    canonical_target = resolved[requested_target]
    equivalent_targets = sorted({
        canonical_target,
        *(
            target
            for target, identity in resolved.items()
            if identity == canonical_target
        ),
    })
    print(json.dumps({
        "canonical_target": canonical_target,
        "equivalent_targets": equivalent_targets,
        "error": None,
    }, separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    main()
