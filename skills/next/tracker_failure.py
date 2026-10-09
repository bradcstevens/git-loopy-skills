#!/usr/bin/env python3
"""Classify tracker failures by whether they prove a target is invalid."""

import re
import subprocess
from typing import Optional, Sequence, Tuple


PERMANENT_FAILURE_PATTERNS = (
    r"\bcould not resolve to an issue(?: or pull request)? with the number of\b",
    r"\bdoes not resolve\b",
    r"\b(?:invalid|malformed)\s+(?:issue(?: number)?|target)\b",
    r"\bissue(?: number)?\s+(?:is|was)\s+(?:invalid|malformed)\b",
)
TRACKER_TIMEOUT_SECONDS = 30


def classify_tracker_failure(message: str) -> str:
    for pattern in PERMANENT_FAILURE_PATTERNS:
        if re.search(pattern, message, flags=re.IGNORECASE):
            return "permanent"
    return "transient"


def run_tracker(
    command: Sequence[str], cwd: str
) -> Tuple[str, Optional[str], int, Optional[str]]:
    try:
        tracker = subprocess.run(
            command,
            capture_output=True,
            cwd=cwd,
            text=True,
            timeout=TRACKER_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        message = f"tracker timed out after {error.timeout} seconds"
        return "", message, 124, "transient"
    except OSError as error:
        message = f"could not run tracker: {error}"
        return "", message, 1, "transient"

    if not tracker.returncode:
        return tracker.stdout, None, 0, None

    message = (
        tracker.stderr.strip()
        or tracker.stdout.strip()
        or f"tracker exited with status {tracker.returncode}"
    )
    exit_status = tracker.returncode if 1 <= tracker.returncode <= 255 else 1
    return (
        "",
        message,
        exit_status,
        classify_tracker_failure(message),
    )
