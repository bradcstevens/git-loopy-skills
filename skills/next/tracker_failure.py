#!/usr/bin/env python3
"""Classify tracker failures by whether they prove a target is invalid."""

import re


PERMANENT_FAILURE_PATTERNS = (
    r"\bcould not resolve to an issue\b",
    r"\bdoes not resolve\b",
    r"\bhttp(?: status)?\s*404\b",
    r"\bstatus(?: code)?\s*404\b",
    r"\b404\s+not found\b",
    r"\b(?:invalid|malformed)\s+(?:issue(?: number)?|target)\b",
    r"\bissue(?: number)?\s+(?:is|was)\s+(?:invalid|malformed)\b",
)


def classify_tracker_failure(message: str) -> str:
    for pattern in PERMANENT_FAILURE_PATTERNS:
        if re.search(pattern, message, flags=re.IGNORECASE):
            return "permanent"
    return "transient"
