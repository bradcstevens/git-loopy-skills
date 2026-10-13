#!/usr/bin/env python3
import os
import sys
scripts = os.path.join(os.environ.get("COPILOT_HOME") or os.path.expanduser("~/.copilot"), "skills", "next", "scripts")
if not os.path.isfile(os.path.join(scripts, "chain.sh")):
    scripts = os.path.join(os.path.dirname(__file__), "..", "next", "scripts")
if __name__ == "__main__":
    os.execv(os.path.join(scripts, "chain.sh"), ["chain.sh", "reenter"])
sys.path.insert(0, scripts)
from chain_ledger import acquire_lock, lock_is_stale, release_lock
