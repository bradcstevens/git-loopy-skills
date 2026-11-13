#!/usr/bin/env python3
"""Report worktree ownership and, with --remove, reclaim the worktrees something vouches for."""

import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

sys.dont_write_bytecode = True
from sessions import repository_root
from tracker_failure import run_tracker


MARKER = ".git-loopy/worktree-owner"
LSOF_ESCAPES = {0x08: b"\\b", 0x09: b"\\t", 0x0a: b"\\n", 0x0c: b"\\f", 0x0d: b"\\r",
                0x5c: b"\\\\"}
# lsof leads other control bytes, and 0xff where char is unsigned, with a caret, so a
# caret is the only token in its spelling that a literal character can also produce.
LSOF_AMBIGUOUS = b"^"
# lsof may append an annotation such as " (deleted)", which a literal " (" can mimic.
LSOF_ANNOTATION = b" ("
# What a worktree's own git directory holds while an operation is unfinished.
OPERATION_STATE = ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD",
                   "BISECT_LOG", "sequencer")


def git_run(repo, *args):
    return subprocess.run(
        ["git", "--no-optional-locks", "-C", repo, *args],
        check=True, capture_output=True,
    )


def leave_caller_repository():
    """Drop the repository a caller such as a git hook exports, as git does entering another one."""
    # Otherwise every git and gh call would read the caller's repository, and staged work there
    # would make a worktree's own status read clean.
    names = os.fsdecode(subprocess.run(["git", "rev-parse", "--local-env-vars"], check=True,
                                       capture_output=True).stdout).split()
    for name in names:
        if name not in ("GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT"):
            os.environ.pop(name, None)


def git(repo, *args):
    return git_run(repo, *args).stdout


def rev_parse_path(repo, option):
    path = os.fsdecode(git(repo, "rev-parse", option)).removesuffix("\n")
    return os.path.realpath(os.path.join(repo, path))


def worktrees(repo):
    rows = []
    for record in git(repo, "worktree", "list", "--porcelain", "-z").split(b"\0\0"):
        fields = dict(field.partition(b" ")[::2] for field in record.split(b"\0") if field)
        if b"worktree" in fields:
            rows.append({
                "path": os.path.realpath(os.fsdecode(fields[b"worktree"])),
                "branch": os.fsdecode(fields.get(b"branch", b"")) or None,
                "bare": b"bare" in fields,
                "locked": b"locked" in fields,
                "classification": "unvouched",
                "errors": [],
                "_registered": os.fsdecode(fields[b"worktree"]),
                "_head": os.fsdecode(fields.get(b"HEAD", b"")),
                "_prunable": b"prunable" in fields,
            })
    return rows


def kernel_spelling(pwd, row):
    """Return a worktree's path as the kernel, and so lsof, spells it, recording any failure.

    A vanished worktree keeps git's spelling for the part of its path that no longer exists.
    """
    # git's record can differ in case, Unicode normalization or a firmlinked prefix.
    path, tail = row["path"], []
    if row["exists"] is False:
        # A vanished directory's nearest surviving ancestor still has a kernel spelling.
        while not os.path.isdir(path) and path != os.path.dirname(path):
            path, leaf = os.path.split(path)
            tail.insert(0, leaf)
    try:
        result = subprocess.run([pwd, "-P"], cwd=path, check=True, capture_output=True)
    except (OSError, subprocess.SubprocessError) as error:
        row["errors"].append(f"cannot read the kernel's spelling: {error_message(error)}")
        return None
    return os.path.join(os.fsdecode(result.stdout).removesuffix("\n"), *tail)


def marker_owner(path):
    marker = os.path.join(path, MARKER)
    if not os.path.lexists(marker):
        return None
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("chain.sh")), "owner", "--worktree", path],
        check=True, capture_output=True, text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    return json.loads(result.stdout)


def lsof_spellings(path):
    """Spell a path each way lsof may print it under LC_ALL=C."""
    # lsof prints byte 0xff as \xff where char is signed (x86_64, macOS) and ^? elsewhere.
    signed = unsigned = b""
    for byte in os.fsencode(path):
        if byte in LSOF_ESCAPES:
            spelled = LSOF_ESCAPES[byte]
        elif 0x20 <= byte < 0x7f:
            spelled = bytes([byte])
        elif byte < 0x20:
            spelled = LSOF_AMBIGUOUS + bytes([byte + 0x40])
        else:
            spelled = b"\\x%02x" % byte
        signed += spelled
        unsigned += LSOF_AMBIGUOUS + b"?" if byte == 0xff else spelled
    return {signed, unsigned}


def lsof_listing():
    """Return lsof's NUL-separated listing of every process and its open names."""
    with subprocess.Popen(
        ["lsof", "-nP", "-F0pRn"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={**os.environ, "LC_ALL": "C"},
    ) as process:
        try:
            stdout, stderr = process.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
    # lsof always lists itself, so an empty listing is a failed inspection too.
    if process.returncode or stderr or not stdout:
        detail = os.fsdecode(stderr).strip() or (
            f"exit status {process.returncode} with {'partial' if stdout else 'no'} output")
        raise RuntimeError(f"lsof inspection failed: {detail}")
    return stdout, process.pid


def lies_in(name, spelling):
    """Report whether an lsof name is a spelled path or lies beneath it."""
    return (name == spelling or name.startswith(spelling + b"/")
            or name.startswith(spelling + LSOF_ANNOTATION))


def worktrees_named(name, spellings, certain):
    """Return every worktree an lsof name may lie in, innermost wherever that is certain."""
    matches = [(path, spelling) for spelling, paths in spellings.items()
               if lies_in(name, spelling)
               for path in paths]
    # A nested worktree outranks its parent only when its directory is certainly one of
    # this repository's worktrees, the name continues its path itself rather than through
    # an annotation, and nothing ambiguous lies between their spellings.
    return {path for path, spelling in matches
            if not any(inner.startswith(path + os.sep)
                       and inner in certain
                       and (name == inner_spelling or name.startswith(inner_spelling + b"/"))
                       and not any(token in inner_spelling[len(spelling):]
                                   for token in (LSOF_AMBIGUOUS, LSOF_ANNOTATION))
                       for inner, inner_spelling in matches)}


def holders(rows, kernel_paths):
    stdout, lsof_pid = lsof_listing()
    spellings = {}
    folded = {}
    for row in rows:
        for name in {row["path"], kernel_paths.get(row["path"])} - {None}:
            for spelling in lsof_spellings(name):
                spellings.setdefault(spelling, []).append(row["path"])
                if row["exists"] is False:
                    # A deleted name keeps git's spelling, so also match it ignoring ASCII case.
                    folded.setdefault(spelling.lower(), []).append(row["path"])
    certain = {row["path"] for row in rows if row["exists"] and not row["errors"]}
    found = {row["path"]: set() for row in rows}
    pid = None
    excluded = False
    for field in stdout.split(b"\0"):
        field = field.lstrip(b"\n")
        if field.startswith(b"p"):
            pid = int(field[1:])
            excluded = pid in (os.getpid(), lsof_pid)
        elif field.startswith(b"R"):
            # Linux lsof forks helpers that inherit its working directory.
            excluded = excluded or int(field[1:]) == lsof_pid
        elif field.startswith(b"n/") and pid is not None and not excluded:
            name = field[1:]
            for path in worktrees_named(name, spellings, certain):
                found[path].add(pid)
            lowered = name.lower()
            for spelling, paths in folded.items():
                if lies_in(lowered, spelling):
                    for path in paths:
                        found[path].add(pid)
    return found


def resolve_root(repo, rows):
    """Return the repository root, re-pointing a separate-git-dir entry at its checkout."""
    common = rev_parse_path(repo, "--git-common-dir")
    if rows and rows[0]["bare"]:
        root = common
    else:
        git_dir = rev_parse_path(repo, "--git-dir")
        if (rows and rows[0]["path"] == common and git_dir != common
                and not os.path.islink(os.path.join(common, "git-loopy-worktree-root"))):
            raise RuntimeError("separate-git-dir repository root is unrecorded; run from its main checkout")
        root = repository_root(repo, rows)
        if rows and rows[0]["path"] == common:
            if rev_parse_path(root, "--git-common-dir") != common:
                raise RuntimeError("recorded repository root belongs to another repository")
            rows[0]["path"] = root
    return root


def ledger_counts(path):
    counts = {}
    try:
        ledger = open(path, encoding="utf-8")
    except FileNotFoundError:
        return counts
    with ledger:
        for number, line in enumerate(ledger, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict) or not isinstance(row.get("worktree"), str) or not row["worktree"]:
                raise ValueError(f"{path}:{number}: ledger row requires a worktree path")
            worktree = os.path.realpath(row["worktree"])
            counts[worktree] = counts.get(worktree, 0) + 1
    return counts


def error_message(error):
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        detail = error.stderr
        return os.fsdecode(detail).strip()
    return str(error)


def inspect_checkout(row, common):
    """Record whether a worktree's directory exists and holds uncommitted changes."""
    path = row["path"]
    row["dirty"] = None
    try:
        row["exists"] = stat.S_ISDIR(os.stat(path).st_mode)
    except (FileNotFoundError, NotADirectoryError):
        row["exists"] = False
    except OSError as error:
        row["exists"] = None
        row["errors"].append(error_message(error))
    if not row["exists"]:
        return
    try:
        top = rev_parse_path(path, "--show-toplevel")
        if top != path and not os.path.samefile(top, path):
            raise RuntimeError("directory no longer resolves to the registered worktree")
        if not os.path.samefile(rev_parse_path(path, "--git-common-dir"), common):
            raise RuntimeError("directory belongs to another repository")
        status = git_run(path, "status", "--porcelain=v1", "-z", "--untracked-files=all",
                         "--ignore-submodules=none", "--", ".", f":(exclude){MARKER}")
        # git warns about a directory it cannot read and still exits 0.
        if status.stderr:
            raise RuntimeError(os.fsdecode(status.stderr).strip())
        row["dirty"] = bool(status.stdout)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        row["errors"].append(error_message(error))


def marker_present(row):
    """Report whether a worktree carries a marker, recording why when it cannot tell."""
    try:
        os.lstat(os.path.join(row["path"], MARKER))
        return True
    except (FileNotFoundError, NotADirectoryError):
        return False
    except OSError as error:
        row["errors"].append(error_message(error))
        return False


def read_marker(path):
    """Return a worktree's marker bytes, or None when they cannot be read."""
    try:
        with open(os.path.join(path, MARKER), "rb") as marker:
            return marker.read()
    except OSError:
        return None


def classify(row, pids, ledger_rows):
    path = row["path"]
    row.update(ledger_rows=ledger_rows, holder_pids=sorted(pids), owner_alive=None)
    marked = marker_present(row)
    row["classification"] = "held" if pids else "marked" if marked else "unvouched"
    # Kept to prove at removal time that nobody re-marked the worktree since it was judged.
    row["_marked"], row["_marker"] = marked, read_marker(path) if marked else None
    if marked:
        try:
            owner = marker_owner(path)
            if owner is None:
                row["errors"].append("marker disappeared during sweep")
            elif owner.get("reason"):
                row["errors"].append(owner["reason"])
            else:
                row["owner_alive"] = owner["alive"]
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))


def encloses(directory, path):
    """Report whether path lies inside directory by filesystem identity, whatever its spelling."""
    try:
        inside = os.stat(directory)
    except OSError:
        return True
    while path != os.path.dirname(path):
        path = os.path.dirname(path)
        try:
            ancestor = os.stat(path)
        except OSError:
            continue
        if (ancestor.st_dev, ancestor.st_ino) == (inside.st_dev, inside.st_ino):
            return True
    return False


def unfinished_work(root, row):
    """Name work a worktree's git directory holds beyond its files, which removal would destroy."""
    reasons = []
    git_dir = os.fsdecode(git(row["path"], "rev-parse", "--absolute-git-dir")).removesuffix("\n")
    if any(os.path.lexists(os.path.join(git_dir, name)) for name in OPERATION_STATE):
        reasons.append("operation-in-progress")
    # A detached HEAD's commits may be on no branch, and its reflog goes with the worktree.
    if row["branch"] is None and not git(root, "for-each-ref", "--count=1", "--contains", row["_head"]):
        reasons.append("unreferenced-head")
    return reasons


def refusals(row, rows, main_path, common):
    """Name every reason a sweep may not remove a worktree."""
    reasons = []
    if row["path"] == main_path:
        reasons.append("main-worktree")
    if row["errors"]:
        reasons.append("inspection-errors")
    if row["holder_pids"]:
        reasons.append("held")
    if row["locked"]:
        reasons.append("locked")
    if row["exists"] is False:
        # Only the registration is left to reconcile, and git must agree that it is stale.
        if not row["_prunable"]:
            reasons.append("not-prunable")
        return reasons
    # git worktree remove deletes nested repositories, a nested worktree's unsaved work included.
    if any(other["path"].startswith(row["path"] + os.sep) or encloses(row["path"], other["path"])
           for other in rows if other is not row):
        reasons.append("contains-worktree")
    if row["path"] != main_path and encloses(row["path"], common):
        reasons.append("contains-repository")
    if row["dirty"]:
        reasons.append("uncommitted-changes")
    reasons.extend(row["_unfinished"])
    if not row["_marked"]:
        reasons.append("unvouched")
    elif row["owner_alive"]:
        reasons.append("owner-alive")
    elif row["owner_alive"] is None:
        reasons.append("owner-liveness-unknown")
    return reasons


def unregister(root, row):
    """Run git's own unforced removal, which refuses a worktree holding uncommitted changes."""
    # That refusal follows status.showUntrackedFiles, so make it see every untracked file.
    git_run(root, "-c", "status.showUntrackedFiles=all", "worktree", "remove", row["_registered"])


def registered_paths(root):
    listing = git(root, "worktree", "list", "--porcelain", "-z")
    return {os.fsdecode(field[len(b"worktree "):])
            for field in listing.split(b"\0") if field.startswith(b"worktree ")}


def remove_worktree(root, row):
    """Remove a vouched worktree, restoring its marker if the worktree stays on disk."""
    # Mirrors chain.sh's remove_worktree, which handles the marker the same way.
    marker = os.path.join(row["path"], MARKER)
    if read_marker(row["path"]) != row["_marker"]:
        row["reasons"].append("marker-changed")
        return False
    # Removal stays unforced so git refuses work that appeared after the worktree was judged
    # clean, which means the marker must go first: git counts an unignored marker as untracked.
    os.unlink(marker)
    try:
        os.rmdir(os.path.dirname(marker))
    except OSError:
        pass
    try:
        unregister(root, row)
    except subprocess.CalledProcessError as error:
        row["reasons"].append("removal-failed")
        row["errors"].append(error_message(error))
        # git deletes the registration even when it fails to delete the whole directory.
        if row["_registered"] not in registered_paths(root):
            row["reasons"].append("registration-lost")
        if os.path.isdir(row["path"]):
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            with open(marker, "wb") as restored:
                restored.write(row["_marker"])
        return False
    return True


def merge_status(root, name, tip):
    """Ask GitHub whether a pull request from this repository's branch merged at its local tip."""
    # A squash merge leaves a merged branch outside the default branch's ancestry.
    stdout, error, _, _ = run_tracker(
        ["gh", "pr", "list", "--head", name, "--state", "merged",
         "--json", "headRefOid,isCrossRepository", "--limit", "100"], root)
    if error is not None:
        raise RuntimeError(f"cannot ask GitHub whether {name} merged: {error}")
    pulls = json.loads(stdout)
    if not isinstance(pulls, list) or not all(isinstance(pull, dict) for pull in pulls):
        raise ValueError(f"unexpected pull request listing for {name}")
    ours = [pull for pull in pulls if pull.get("isCrossRepository") is False]
    if any(pull.get("headRefOid") == tip for pull in ours):
        return "merged"
    return "merged-at-another-commit" if ours else "not-merged"


def branch_tip(root, branch):
    return os.fsdecode(git(root, "rev-parse", "--verify", branch)).strip()


def reclaim_branch(root, row, rows):
    """Delete the branch a removed worktree freed, once GitHub shows it merged at its tip."""
    branch = row["branch"]
    if not branch or not branch.startswith("refs/heads/"):
        return
    row["branch_outcome"] = "kept"

    def keep(reason, error=None):
        row["branch_reasons"].append(reason)
        if error is not None:
            row["errors"].append(error_message(error))

    if any(other is not row and other["branch"] == branch
           and other["outcome"] not in ("removed", "pruned") for other in rows):
        return keep("checked-out-elsewhere")
    name = branch[len("refs/heads/"):]
    try:
        tip = branch_tip(root, branch)
    except subprocess.CalledProcessError as error:
        return keep("branch-unreadable", error)
    try:
        verdict = merge_status(root, name, tip)
    except (RuntimeError, ValueError) as error:
        return keep("merge-status-unknown", error)
    if verdict != "merged":
        return keep(verdict)
    try:
        if branch_tip(root, branch) != tip:
            return keep("branch-moved")
        git_run(root, "branch", "-D", "--", name)
    except subprocess.CalledProcessError as error:
        return keep("deletion-failed", error)
    row["branch_outcome"] = "deleted"


def reclaim(root, rows, kernel_paths, main_path, common):
    """Remove every vouched worktree and prune every vanished one, then decide freed branches."""
    for row in rows:
        row["_unfinished"] = []
        if row["exists"] and not row["errors"]:
            try:
                row["_unfinished"] = unfinished_work(root, row)
            except (OSError, subprocess.SubprocessError) as error:
                row["errors"].append(error_message(error))
    for row in rows:
        row.update(outcome="declined", reasons=refusals(row, rows, main_path, common),
                   branch_outcome=None, branch_reasons=[])
    candidates = [row for row in rows if not row["reasons"]]
    if not candidates:
        return
    # A second look, just before the removals begin, narrows the window in which a process can
    # enter a worktree it is about to lose.
    second_look = holders(rows, kernel_paths)
    for row in candidates:
        if second_look[row["path"]]:
            row["holder_pids"] = sorted(set(row["holder_pids"]) | second_look[row["path"]])
            row["classification"] = "held"
            row["reasons"].append("held")
            continue
        try:
            if row["exists"] is False:
                if os.path.lexists(row["path"]):
                    row["reasons"].append("reappeared")
                else:
                    unregister(root, row)
                    row["outcome"] = "pruned"
            elif remove_worktree(root, row):
                row["outcome"] = "removed"
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))
            if "removal-failed" not in row["reasons"]:
                row["reasons"].append("removal-failed")
    # Branches wait for every removal, so slow GitHub lookups never widen the window above.
    for row in candidates:
        if row["outcome"] == "removed":
            try:
                reclaim_branch(root, row, rows)
            except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                row["errors"].append(error_message(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="path inside the repository (default: current directory)")
    parser.add_argument("--ledger", default=os.environ.get("CHAIN_LEDGER"),
                        help="spawn ledger (default: repository .git-loopy/subagents.jsonl)")
    parser.add_argument("--remove", action="store_true",
                        help="remove vouched worktrees and the merged branches they free")
    args = parser.parse_args()
    try:
        leave_caller_repository()
        repo = args.repo or os.getcwd()
        rows = worktrees(repo)
        root = resolve_root(repo, rows)
        main_path = rows[0]["path"] if rows and not rows[0]["bare"] else None
        ledger = os.path.abspath(args.ledger or os.path.join(root, ".git-loopy", "subagents.jsonl"))
        rows = [row for row in rows if not row.pop("bare")]
        ledger_row_counts = ledger_counts(ledger)
        # Resolve pwd before entering any worktree, where a relative PATH entry could find another.
        pwd = shutil.which("pwd")
        if pwd is None:
            raise RuntimeError("pwd not found on PATH")
        pwd = os.path.abspath(pwd)
        common = rev_parse_path(repo, "--git-common-dir")
        kernel_paths = {}
        for row in rows:
            inspect_checkout(row, common)
            if row["exists"] is not None:
                kernel_paths[row["path"]] = kernel_spelling(pwd, row)
        pids_by_worktree = holders(rows, kernel_paths) if rows else {}
        for row in rows:
            classify(row, pids_by_worktree[row["path"]], ledger_row_counts.get(row["path"], 0))
        if args.remove and rows:
            reclaim(root, rows, kernel_paths, main_path, common)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"error: {error_message(error)}", file=sys.stderr)
        return 1
    for row in rows:
        for key in [key for key in row if key.startswith("_")]:
            del row[key]
    counts = {name: sum(row["classification"] == name for row in rows)
              for name in ("held", "marked", "unvouched")}
    if args.remove:
        counts.update({name: sum(row["outcome"] == name for row in rows)
                       for name in ("removed", "pruned", "declined")})
    print(json.dumps({"worktrees": rows, "counts": counts, "ledger": ledger}))
    return int(any(row["errors"] for row in rows))


if __name__ == "__main__":
    sys.exit(main())
