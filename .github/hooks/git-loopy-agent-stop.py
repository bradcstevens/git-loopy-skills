#!/usr/bin/env python3
import os
import sys

template = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "skills",
    "setup-git-loopy-skills",
    "git-loopy-agent-stop.py",
)
os.execv(sys.executable, [sys.executable, template])
