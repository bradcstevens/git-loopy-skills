#!/usr/bin/env python3
"""Report worktree ownership and, with --remove, reclaim the worktrees something vouches for."""

import argparse
from collections import namedtuple
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
HEADS = "refs/heads/"
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
# Refs git keeps per worktree, inside its record, which go with the record.
WORKTREE_REFS = ("refs/worktree/", "refs/bisect/", "refs/rewritten/")


def git_run(repo, *args, check=True):
    return subprocess.run(
        ["git", "--no-optional-locks", "-C", repo, *args],
        check=check, capture_output=True,
    )


def ignore_exported_repository():
    """Drop the repository an invoking git hook exports, as git does entering another repository."""
    # Otherwise every git and gh call would read the hook's repository, and staged work there
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


Ledger = namedtuple("Ledger", "counts owned")


def read_ledger(path):
    """Count each worktree's spawn-ledger rows, and name the worktrees the ledger owns."""
    counts, owned = {}, set()
    # A reserve or claim interrupted before it finished leaves this record naming its worktree,
    # and the next chain.sh command rolls that transaction back.
    try:
        with open(path + ".pending", encoding="utf-8") as pending:
            record = json.load(pending)
    except FileNotFoundError:
        record = None
    if record is not None:
        if not isinstance(record, dict) or not isinstance(record.get("worktree"), str) \
                or not record["worktree"]:
            raise ValueError(f"{path}.pending: pending worktree record requires a worktree path")
        owned.add(os.path.realpath(record["worktree"]))
    try:
        ledger = open(path, encoding="utf-8")
    except FileNotFoundError:
        return Ledger(counts, owned)
    with ledger:
        for number, line in enumerate(ledger, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict) or not isinstance(row.get("worktree"), str) or not row["worktree"]:
                raise ValueError(f"{path}:{number}: ledger row requires a worktree path")
            worktree = os.path.realpath(row["worktree"])
            counts[worktree] = counts.get(worktree, 0) + 1
            # chain.sh treats a row without a finish time as open, and owns its worktree.
            if not row.get("finish_time"):
                owned.add(worktree)
    return Ledger(counts, owned)


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
        row["dirty"] = uncommitted(path)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        row["errors"].append(error_message(error))


def uncommitted(path):
    """Report whether a worktree holds staged, unstaged, untracked or submodule changes."""
    status = git_run(path, "status", "--porcelain=v1", "-z", "--untracked-files=all",
                     "--ignore-submodules=none", "--", ".", f":(exclude){MARKER}")
    # git warns about a directory it cannot read and still exits 0.
    if status.stderr:
        raise RuntimeError(os.fsdecode(status.stderr).strip())
    return bool(status.stdout)


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


def read_bytes(path):
    """Return a file's bytes, or None when they cannot be read."""
    try:
        with open(path, "rb") as file:
            return file.read()
    except OSError:
        return None


def read_marker(path):
    return read_bytes(os.path.join(path, MARKER))


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


def worktree_records(common):
    """Map each linked worktree's path to git's record of it under the common directory."""
    found = {}
    base = os.path.join(common, "worktrees")
    try:
        entries = os.listdir(base)
    except FileNotFoundError:
        return found
    for entry in entries:
        record = os.path.join(base, entry)
        gitdir = read_bytes(os.path.join(record, "gitdir"))
        if gitdir is None:
            continue
        target = os.fsdecode(gitdir).removesuffix("\n")
        # gitdir names the worktree's .git file, absolute or relative to the record itself.
        found[os.path.dirname(os.path.realpath(os.path.join(record, target)))] = record
    return found


def read_text(path):
    content = read_bytes(path)
    return None if content is None else os.fsdecode(content).strip()


def find_record(row, records):
    """Return git's record of a linked worktree: its own git directory, which removal deletes."""
    if row["exists"]:
        return rev_parse_path(row["path"], "--absolute-git-dir")
    if row["path"] in records:
        return records[row["path"]]
    raise RuntimeError("cannot find git's record of the vanished worktree")


def record_refusals(root, row, record, head):
    """Name what git's record of a worktree holds that removal would destroy, or git would refuse."""
    reasons = []
    if any(os.path.lexists(os.path.join(record, name)) for name in OPERATION_STATE):
        reasons.append("operation-in-progress")
    # A linked worktree keeps its submodules' repositories in its own record.
    if os.path.lexists(os.path.join(record, "modules")) or (
            row["exists"] and occupied_submodule(row["path"])):
        reasons.append("contains-submodule")
    if git(root, "--git-dir", record, "for-each-ref", "--count=1", *WORKTREE_REFS):
        reasons.append("worktree-refs")
    # A detached HEAD's commits may be on no branch, and the record holds its only reflog.
    if row["branch"] is None and not git(root, "for-each-ref", "--count=1", "--contains", head):
        reasons.append("unreferenced-head")
    if not row["exists"]:
        # With the directory gone, the index is the only place a staged change still exists.
        staged = git_run(root, "--git-dir", record, "diff-index", "--cached", "--quiet", "HEAD", "--",
                         check=False)
        if staged.returncode not in (0, 1):
            raise subprocess.CalledProcessError(staged.returncode, staged.args, staged.stdout,
                                                staged.stderr)
        if staged.returncode:
            reasons.append("uncommitted-changes")
    return reasons


def occupied_submodule(path):
    """Report whether any submodule directory in a worktree holds anything at all."""
    # A checked-out submodule makes git refuse removal, and git status never looks inside an
    # uninitialised one, so a file written there would be deleted unseen.
    for entry in git(path, "ls-files", "--stage", "-z").split(b"\0"):
        mode, _, name = entry.partition(b"\t")
        if not mode.startswith(b"160000 "):
            continue
        try:
            if os.listdir(os.path.join(path, os.fsdecode(name))):
                return True
        except (FileNotFoundError, NotADirectoryError):
            continue
    return False


def changes_since_judged(root, row, records, main_path, common, ledger):
    """Re-read a candidate just before removal, naming anything that changed since it was judged."""
    listing = worktrees(root)
    current = next((other for other in listing if other["_registered"] == row["_registered"]), None)
    if current is None:
        return ["registration-changed"]
    # Ownership, holders and errors are looked at separately, so only what can change is re-read.
    fresh = {**current, "exists": row["exists"], "holder_pids": [], "errors": [],
             "_marked": row["_marked"], "owner_alive": row["owner_alive"],
             "dirty": uncommitted(row["path"]) if row["exists"] else None,
             "_ledger_owned": row["path"] in read_ledger(ledger).owned}
    fresh["_record_refusals"] = record_refusals(root, fresh, find_record(fresh, records),
                                                current["_head"])
    reasons = []
    if (current["_head"], current["branch"]) != (row["_head"], row["branch"]):
        reasons.append("head-moved")
    return reasons + [reason for reason in refusals(fresh, listing, main_path, common)
                      if reason not in reasons]


def containment(row, rows, main_path, common):
    """Name what lies inside a worktree that removing it would delete with it."""
    reasons = []
    # git worktree remove deletes nested repositories, a nested worktree's unsaved work included.
    if any(other["path"].startswith(row["path"] + os.sep) or encloses(row["path"], other["path"])
           for other in rows if other["_registered"] != row["_registered"]):
        reasons.append("contains-worktree")
    if row["path"] != main_path and encloses(row["path"], common):
        reasons.append("contains-repository")
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
    # chain.sh owns the worktree an open spawn-ledger row or a pending transaction names.
    if row["_ledger_owned"]:
        reasons.append("ledger-owned")
    if row["exists"] is False:
        # Only git's record is left, so pruning it needs git to report it prunable.
        if not row["_prunable"]:
            reasons.append("not-prunable")
    elif row["exists"]:
        reasons.extend(containment(row, rows, main_path, common))
        if row["dirty"]:
            reasons.append("uncommitted-changes")
    reasons.extend(reason for reason in row["_record_refusals"] if reason not in reasons)
    if row["exists"]:
        if not row["_marked"]:
            reasons.append("unvouched")
        elif row["owner_alive"]:
            reasons.append("owner-alive")
        elif row["owner_alive"] is None:
            reasons.append("owner-liveness-unknown")
    return reasons


def git_worktree_remove(root, row):
    """Run git's own unforced removal, which refuses a worktree holding uncommitted changes."""
    # That refusal follows status.showUntrackedFiles, so make it see every untracked file.
    git_run(root, "-c", "status.showUntrackedFiles=all", "worktree", "remove", row["_registered"])


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
        git_worktree_remove(root, row)
    except subprocess.CalledProcessError as error:
        row["reasons"].append("removal-failed")
        row["errors"].append(error_message(error))
        if os.path.isdir(row["path"]):
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            try:
                with open(marker, "xb") as restored:
                    restored.write(row["_marker"])
            except FileExistsError:
                row["reasons"].append("marker-changed")
        # git deletes the registration even when it fails to delete the whole directory.
        if row["_registered"] not in {other["_registered"] for other in worktrees(root)}:
            row["reasons"].append("registration-lost")
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


def in_another_worktree(root, common, branch):
    """Report whether a worktree has the branch checked out, or is rebasing or bisecting it."""
    # git branch -D refuses each of these, and update-ref -d checks none of them.
    records = worktree_records(common)
    listing = worktrees(root)
    main = listing[0]["path"] if listing else None
    for other in listing:
        if other["branch"] == branch:
            return True
        # The main worktree's record is the common directory itself.
        record = common if other["path"] == main else records.get(other["path"])
        if record is None:
            raise RuntimeError(f"cannot find git's record of the worktree at {other['path']}")
        rebasing = [read_text(os.path.join(record, "rebase-merge", "head-name")),
                    read_text(os.path.join(record, "rebase-apply", "head-name"))]
        # rebase --update-refs also rewrites every branch it lists here.
        rebasing += (read_text(os.path.join(record, "rebase-merge", "update-refs")) or "").split()
        if branch in rebasing:
            return True
        if read_text(os.path.join(record, "BISECT_START")) == branch.removeprefix(HEADS):
            return True
    return False


def reclaim_branch(root, row, common):
    """Delete the branch a removed worktree freed, once GitHub shows it merged at its tip."""
    branch = row["branch"]
    if not branch or not branch.startswith(HEADS):
        return
    row["branch_outcome"] = "kept"

    def keep(reason, error=None):
        row["branch_reasons"].append(reason)
        if error is not None:
            row["errors"].append(error_message(error))

    def reason_to_keep():
        """Name why another worktree's claim keeps the branch, or None when nothing claims it."""
        try:
            return "in-another-worktree" if in_another_worktree(root, common, branch) else None
        except (RuntimeError, subprocess.CalledProcessError) as error:
            row["errors"].append(error_message(error))
            return "branch-check-failed"

    name = branch.removeprefix(HEADS)
    reason = reason_to_keep()
    if reason:
        return keep(reason)
    try:
        tip = branch_tip(root, branch)
    except subprocess.CalledProcessError as error:
        return keep("branch-check-failed", error)
    try:
        verdict = merge_status(root, name, tip)
    except (RuntimeError, ValueError) as error:
        return keep("merge-status-unknown", error)
    if verdict != "merged":
        return keep(verdict)
    # Look again, because a worktree may have taken the branch up during the lookup.
    reason = reason_to_keep()
    if reason:
        return keep(reason)
    try:
        # Deleting against the tip GitHub vouched for refuses a branch that moved since.
        git_run(root, "update-ref", "-d", branch, tip)
    except subprocess.CalledProcessError as error:
        try:
            moved = branch_tip(root, branch) != tip
        except subprocess.CalledProcessError:
            moved = False
        return keep("branch-moved") if moved else keep("deletion-failed", error)
    # update-ref leaves behind the configuration git branch -D would also remove.
    git_run(root, "config", "--remove-section", f"branch.{name}", check=False)
    row["branch_outcome"] = "deleted"


def reclaim(root, rows, kernel_paths, main_path, common, ledger):
    """Remove every vouched worktree and prune every vanished one, then decide freed branches."""
    records = worktree_records(common)
    for row in rows:
        row["_record_refusals"] = []
        if row["exists"] is not None and not row["errors"] and row["path"] != main_path:
            try:
                row["_record_refusals"] = record_refusals(root, row, find_record(row, records),
                                                          row["_head"])
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                row["errors"].append(error_message(error))
    for row in rows:
        row.update(outcome="declined", reasons=refusals(row, rows, main_path, common),
                   branch_outcome=None, branch_reasons=[])
    candidates = [row for row in rows if not row["reasons"]]
    for row in candidates:
        try:
            # Another look just before each removal narrows the window in which a process can
            # enter a worktree it is about to lose.
            holder_pids = holders(rows, kernel_paths)[row["path"]]
            changed = [] if holder_pids else changes_since_judged(root, row, records, main_path,
                                                                  common, ledger)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))
            row["reasons"].append("inspection-errors")
            continue
        if holder_pids:
            row["holder_pids"] = sorted(set(row["holder_pids"]) | holder_pids)
            row["classification"] = "held"
            row["reasons"].append("held")
            continue
        try:
            if changed:
                row["reasons"].extend(changed)
            elif row["exists"] is False:
                if os.path.lexists(row["path"]):
                    row["reasons"].append("reappeared")
                else:
                    git_worktree_remove(root, row)
                    row["outcome"] = "pruned"
            elif remove_worktree(root, row):
                row["outcome"] = "removed"
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))
            if "removal-failed" not in row["reasons"]:
                row["reasons"].append("removal-failed")
    # Branches wait for every removal, so slow GitHub lookups never widen the window above.
    decided = {}
    for row in candidates:
        if row["outcome"] != "removed":
            continue
        if row["branch"] in decided:
            row["branch_outcome"], row["branch_reasons"] = decided[row["branch"]]
            continue
        try:
            reclaim_branch(root, row, common)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            row["errors"].append(error_message(error))
        if row["branch"]:
            # Worktrees forced onto one branch share its single decision.
            decided[row["branch"]] = (row["branch_outcome"], list(row["branch_reasons"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="path inside the repository (default: current directory)")
    parser.add_argument("--ledger", default=os.environ.get("CHAIN_LEDGER"),
                        help="spawn ledger (default: repository .git-loopy/subagents.jsonl)")
    parser.add_argument("--remove", action="store_true",
                        help="remove vouched worktrees and the merged branches they free")
    args = parser.parse_args()
    try:
        ignore_exported_repository()
        repo = args.repo or os.getcwd()
        rows = worktrees(repo)
        root = resolve_root(repo, rows)
        main_path = rows[0]["path"] if rows and not rows[0]["bare"] else None
        ledger = os.path.abspath(args.ledger or os.path.join(root, ".git-loopy", "subagents.jsonl"))
        rows = [row for row in rows if not row.pop("bare")]
        ledger_rows = read_ledger(ledger)
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
            classify(row, pids_by_worktree[row["path"]], ledger_rows.counts.get(row["path"], 0))
            row["_ledger_owned"] = row["path"] in ledger_rows.owned
        if args.remove and rows:
            reclaim(root, rows, kernel_paths, main_path, common, ledger)
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
