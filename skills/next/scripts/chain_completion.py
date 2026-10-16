"""Completion and recovery behind the frozen chain CLI."""

import datetime
import json
import os
import subprocess
import sys

from chain_ledger import is_open, ledger_rewrite, load_ledger, matches_run, owner_is_gone
from chain_worktree import remove_clean_worktree
from tracker_failure import run_tracker


def complete(ledger_path: str, tracker_bin: str) -> tuple:
    target_identity = os.path.join(os.path.dirname(__file__), "target-identity.py")
    # Required because `complete` reads them on every path, and for no other reason.
    # sessionId scopes the match; cwd locates the repository and the worktree;
    # timestamp closes the row. Everything else the runtime sends — transcriptPath,
    # agentDisplayName, response, stopReason, and whatever a later release adds — is
    # optional, because a field that is required and never read rejects real
    # payloads and silences the whole chain (#41).
    required_fields = (
        "sessionId",
        "timestamp",
        "cwd",
    )
    # The identity of the run is itself conditional, so the fields carrying it are
    # required only on the path that reads them. About half of the real
    # subagentStop payloads measured in ADR-0005 carry neither agentId nor
    # agentType — a payload has both or neither — and one that names no agent is
    # correlated by where the run worked instead, using the agentName the runtime
    # sets to the agent type (#70).
    identity_fields = ("agentId", "agentType")

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        print(f"error: invalid subagent-stop payload: {error}", file=sys.stderr)
        raise SystemExit(2)

    if not isinstance(payload, dict):
        print("error: subagent-stop payload must be a JSON object", file=sys.stderr)
        raise SystemExit(2)

    # A payload carrying either identity field is held to both: half an identity is
    # a shape no runtime has been observed to send, and downgrading it to the
    # weaker correlation would ignore the very field it did carry.
    has_identity = any(field in payload for field in identity_fields)
    # The one field each tier cannot correlate without: agentId names the run, and
    # agentName stands in for the agent type when nothing names it.
    correlation_field = "agentId" if has_identity else "agentName"
    required_fields += identity_fields if has_identity else ("agentName",)

    missing = [field for field in required_fields if field not in payload]
    if missing:
        print(
            "error: subagent-stop payload is missing " + ", ".join(missing),
            file=sys.stderr,
        )
        raise SystemExit(2)

    invalid = [
        field
        for field in required_fields
        if field != "timestamp" and not isinstance(payload[field], str)
    ]
    if invalid:
        print(
            "error: subagent-stop payload has non-string " + ", ".join(invalid),
            file=sys.stderr,
        )
        raise SystemExit(2)
    if isinstance(payload["timestamp"], bool) or not isinstance(
        payload["timestamp"],
        (str, int, float),
    ):
        print("error: subagent-stop payload has non-string timestamp", file=sys.stderr)
        raise SystemExit(2)

    if not payload[correlation_field]:
        print(
            f"error: subagent-stop payload has an empty {correlation_field}",
            file=sys.stderr,
        )
        raise SystemExit(2)

    rows = load_ledger(ledger_path)
    payload_worktree = os.path.realpath(os.path.abspath(payload["cwd"]))
    matches = [index for index, row in enumerate(rows) if matches_run(row, payload)]
    declined = (
        {"agent_id": payload["agentId"]} if has_identity else {
            "session_id": payload["sessionId"],
            "agent_type": payload["agentName"],
            "worktree": payload_worktree,
        }
    )

    if not matches:
        unbound_matches = [
            index
            for index, row in enumerate(rows)
            if (
                isinstance(row.get("worktree"), str)
                and os.path.realpath(os.path.abspath(row["worktree"])) == payload_worktree
                and is_open(row)
                and not row.get("agent_id")
            )
        ]
        if len(unbound_matches) == 1:
            return ({
                "continue": False,
                "reason": "unbound-reservation",
                "worktree": payload_worktree,
            }, 0)
        return ({
            "continue": False,
            "reason": "unmatched-payload",
            **declined,
        }, 0)

    if len(matches) > 1:
        # Two rows the payload cannot tell apart close neither: guessing between
        # them closes the wrong run, and the wrong run is then routed on.
        return ({
            "continue": False,
            "reason": "ambiguous-payload",
            **declined,
        }, 0)

    row = rows[matches[0]]
    target = row.get("target")
    spawn_time = row.get("spawn_time")
    worktree = row.get("worktree")
    if not isinstance(target, str) or not target:
        print("error: matching spawn ledger row has no target", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(spawn_time, str) or not spawn_time:
        print("error: matching spawn ledger row has no spawn_time", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(worktree, str) or not worktree:
        print("error: matching spawn ledger row has no worktree", file=sys.stderr)
        raise SystemExit(2)

    try:
        spawn_at = datetime.datetime.fromisoformat(spawn_time.replace("Z", "+00:00"))
    except ValueError as error:
        print(f"error: matching spawn ledger row has invalid spawn_time: {error}", file=sys.stderr)
        raise SystemExit(2)
    timestamp = payload["timestamp"]
    try:
        if isinstance(timestamp, str):
            finish_at = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        else:
            finish_at = datetime.datetime.fromtimestamp(
                timestamp / 1000,
                tz=datetime.timezone.utc,
            )
    except (TypeError, ValueError, OverflowError) as error:
        print(f"error: subagent-stop payload has invalid timestamp: {error}", file=sys.stderr)
        raise SystemExit(2)
    if finish_at.tzinfo is None:
        print("error: subagent-stop payload timestamp must include a timezone", file=sys.stderr)
        raise SystemExit(2)

    def resolve_tracker_target():
        # A target that cannot be resolved is a tracker failure like any other: the
        # caller closes the row instead of leaving it open with its worktree on disk.
        try:
            resolution = subprocess.run(
                [sys.executable, target_identity, ledger_path, target],
                capture_output=True,
                cwd=payload["cwd"],
                encoding="utf-8",
                timeout=30,
            )
        except (OSError, UnicodeDecodeError, subprocess.TimeoutExpired) as error:
            return None, f"could not resolve target: {error}"
        if resolution.returncode:
            message = resolution.stderr.strip().splitlines()
            return None, (
                message[-1]
                if message
                else f"target resolver exited with status {resolution.returncode}"
            )
        try:
            canonical = json.loads(resolution.stdout)
        except json.JSONDecodeError as error:
            return None, f"target resolver returned invalid data: {error}"
        if not isinstance(canonical, dict):
            return None, "target resolver returned invalid data"
        if canonical.get("error"):
            failure = canonical["error"]
            detail = canonical.get("detail")
            return None, f"{failure}: {detail}" if detail else str(failure)
        tracker_target = canonical.get("tracker_target")
        if not isinstance(tracker_target, str) or not tracker_target:
            return None, "target resolver returned no tracker target"
        return tracker_target, None

    tracker_target, resolution_error = resolve_tracker_target()
    if resolution_error is not None:
        tracker_output, tracker_error, exit_status, tracker_failure_kind = (
            "",
            resolution_error,
            1,
            "transient",
        )
    else:
        tracker_output, tracker_error, exit_status, tracker_failure_kind = run_tracker(
            [tracker_bin, "issue", "view", tracker_target, "--json", "comments"],
            payload["cwd"],
        )
    if tracker_error is not None:
        comments = []
    else:
        try:
            tracker_response = json.loads(tracker_output)
        except json.JSONDecodeError as error:
            tracker_error = f"tracker returned invalid comment data: {error}"
            tracker_failure_kind = "transient"
            exit_status = 2
            comments = []
        else:
            comments = (
                tracker_response.get("comments")
                if isinstance(tracker_response, dict)
                else None
            )
            if not isinstance(comments, list):
                tracker_error = "tracker returned comments in an invalid format"
                tracker_failure_kind = "transient"
                exit_status = 2
                comments = []

    has_evidence = False
    if tracker_error is None:
        comment_times = []
        for index, comment in enumerate(comments):
            if not isinstance(comment, dict):
                tracker_error = f"tracker returned invalid comment data at index {index}"
                break
            created_at = comment.get("createdAt")
            if not isinstance(created_at, str):
                tracker_error = (
                    f"tracker returned comment data without createdAt at index {index}"
                )
                break
            try:
                comment_at = datetime.datetime.fromisoformat(
                    created_at.replace("Z", "+00:00")
                )
            except ValueError as error:
                tracker_error = (
                    f"tracker returned invalid comment timestamp at index {index}: {error}"
                )
                break
            if comment_at.tzinfo is None:
                tracker_error = (
                    f"tracker returned comment timestamp without timezone at index {index}"
                )
                break
            comment_times.append(comment_at)

        if tracker_error is not None:
            tracker_failure_kind = "transient"
            exit_status = 2
        else:
            has_evidence = any(
                spawn_at <= comment_at <= finish_at
                for comment_at in comment_times
            )

    outcome = (
        "tracker-failed"
        if tracker_error is not None
        else "published" if has_evidence else "no-evidence"
    )
    finish_time = (
        finish_at.astimezone(datetime.timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )
    row["finish_time"] = finish_time
    row["outcome"] = outcome
    if outcome == "no-evidence":
        row["halt_reason"] = "no-evidence"
        row["halted_at"] = finish_time
    elif outcome == "tracker-failed":
        row["tracker_error"] = tracker_error
        row["tracker_failure_kind"] = tracker_failure_kind
        if tracker_failure_kind == "permanent":
            row["halt_reason"] = "tracker-failed"
            row["halted_at"] = finish_time
    elif isinstance(row.get("chain_depth"), int) and row["chain_depth"] >= 8:
        # Record the next-hop stop before agentStop reaches its own eight-block limit.
        row["halt_reason"] = "chain-depth-limit"
        row["halted_at"] = finish_time

    result = {
        "continue": has_evidence and "halt_reason" not in row,
        "outcome": outcome,
        "target": target,
    }
    if tracker_error is not None:
        result["failure_kind"] = tracker_failure_kind
        result["error"] = tracker_error
        result["exit_status"] = exit_status
        print(
            f"error: tracker lookup failed for {target}: {tracker_error}",
            file=sys.stderr,
        )
    with ledger_rewrite(ledger_path, rows):
        if row.get("in_place") is not True and not remove_clean_worktree(worktree):
            result["retained_worktree"] = worktree
    return result, exit_status


def recover(ledger_path: str, stale_after_seconds: int, now: str) -> tuple:
    if now:
        try:
            recovered_at = datetime.datetime.fromisoformat(now.replace("Z", "+00:00"))
        except ValueError as error:
            print(f"error: --now must be an ISO-8601 timestamp: {error}", file=sys.stderr)
            raise SystemExit(2)
        if recovered_at.tzinfo is None:
            print("error: --now must include a timezone", file=sys.stderr)
            raise SystemExit(2)
    else:
        recovered_at = datetime.datetime.now(datetime.timezone.utc)

    rows = load_ledger(ledger_path)

    recovered_worktrees = []
    recovered_targets = []
    for row in rows:
        if not is_open(row):
            continue
        is_bound = bool(row.get("agent_id"))
        spawn_time = row.get("spawn_time")
        worktree = row.get("worktree")
        target = row.get("target")
        if not isinstance(spawn_time, str) or not spawn_time:
            print("error: open spawn ledger row has no spawn_time", file=sys.stderr)
            raise SystemExit(2)
        if not isinstance(worktree, str) or not worktree:
            print("error: open spawn ledger row has no worktree", file=sys.stderr)
            raise SystemExit(2)
        if not isinstance(target, str) or not target:
            print("error: open spawn ledger row has no target", file=sys.stderr)
            raise SystemExit(2)
        try:
            spawned_at = datetime.datetime.fromisoformat(spawn_time.replace("Z", "+00:00"))
        except ValueError as error:
            print(f"error: open spawn ledger row has invalid spawn_time: {error}", file=sys.stderr)
            raise SystemExit(2)
        if spawned_at.tzinfo is None:
            print("error: open spawn ledger row spawn_time must include a timezone", file=sys.stderr)
            raise SystemExit(2)
        parent_pid = row.get("parent_pid")
        parent_start = row.get("parent_start")
        parent_is_gone = False
        if isinstance(parent_pid, int) and isinstance(parent_start, str) and parent_start:
            parent_is_gone = owner_is_gone(parent_pid, parent_start)

        timed_out = (
            recovered_at - spawned_at
        ).total_seconds() >= stale_after_seconds
        if parent_is_gone or (not is_bound and timed_out):
            row["finish_time"] = (
                recovered_at.astimezone(datetime.timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z")
            )
            row["outcome"] = "reclaimed"
            row["reclaimed_at"] = row["finish_time"]
            if row.get("in_place") is not True:
                recovered_worktrees.append(worktree)
            recovered_targets.append(target)

    with ledger_rewrite(ledger_path, rows):
        retained = [
            worktree for worktree in recovered_worktrees if not remove_clean_worktree(worktree)
        ]
    result = {"recovered": len(recovered_targets), "targets": recovered_targets}
    if retained:
        result["retained_worktrees"] = retained
    return result, 0
