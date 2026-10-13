# The chain's core is one Python module behind chain.sh

The chain's deterministic core moves into a flat set of Python modules shipped inside `/next`,
behind the existing `chain.sh` CLI. The embedded programs duplicated repository lookup, ledger
storage and liveness across bash and Python, allowing a non-UTC hook to reclaim a live ledger lock
and lose a concurrent write (#110). Ordinary modules give every port the same ledger implementation
without shell-quoting hazards or repeated interpreter starts.

## Invariants

- **The interface is frozen throughout the strangler.** Existing subcommands, usage forms, flags
  (including `gate`'s aliases), environment variables, stdout decisions, exit codes, pause gates
  and on-disk formats remain unchanged. The only additions are `reenter` and `CHAIN_PYTHON`, which
  defaults to `python3` and rejects an interpreter older than Python 3.9 before changing state.
  `bind --agent-name` remains write-only and `claim --ledger` remains ignored without
  `--create-branch`; #119 tracks those quirks separately.
- **Every owner record is UTC.** Ledger locks name the holder's PID and its `ps -o lstart=` start
  time read under `TZ=UTC`, with whitespace collapsed. Readers compare parsed timestamps; an
  unparseable start cannot prove a live process gone. Stale reclaim uses the existing recovery
  guard, including the configured timeout for an ownerless lock. `reenter` waits about one second
  before `ledger-busy`; other commands keep waiting. Bash and Python writers must interoperate
  during the transition.
- **Python 3.9 and the standard library only.** No runtime union syntax, `match`, package install
  or new runtime dependency. Copying the skill directory is sufficient. CI exercises the chain
  under both the default interpreter and the explicitly selected 3.9 interpreter.
- **Hook responsibilities stay separate.**
  [ADR-0004](./0004-two-hook-events-carry-the-chain.md) still assigns completion to `complete` and
  parent re-entry to `reenter`. Payload validation follows
  [ADR-0005](./0005-hook-payload-fields-are-required-only-where-they-are-read.md); requests,
  confirmation and the three-attempt cap follow
  [ADR-0008](./0008-a-route-is-confirmed-not-assumed.md).

The entry dispatches to modules for the ledger, re-entry, worktree transactions, targets and merge
gate, retaining the tracker port's existing import path. The claim-recovery CLI becomes a wrapper
around the ledger's liveness functions. The eventual entry starts one interpreter per call;
unported bash commands temporarily retain their interpreter starts, all using `CHAIN_PYTHON`.

Each ticket ports its named commands and removes their old bodies in the same change, keeping
the existing chain and hook suites unmodified. #113 introduces the entry, ledger and `reenter`;
later tickets port the remaining commands and remove the residual bash implementation. New tests
drive the chain CLI, including lock interoperability under a non-UTC clock, rather than pinning
internal module structure.

The setup helper is at most ten lines, resolving `/next` in the Copilot home skill directory first
and then as a sibling, and execing `chain.sh reenter`. Its three imported lock names remain aliases
for the existing suite's pinned helper entry point, not a second implementation. This repository's
committed hooks stay unchanged; consumer repositories re-run setup once to replace their frozen
helper copy with the shim.

The later merge-gate port will ship the review-clean record producer inside `/code-review` and a
byte-identical, drift-checked copy inside `/next`, so merge evidence works outside this repository
without changing the gate's exact-head guarantee.

## Considered options

**Ledger core only.** Rejected because it leaves the quoted programs and repeated interpreter
starts, and forces subsequent chain tickets to keep editing bash-hosted Python.

**`reenter` only.** Rejected as the final design because the next writer could still duplicate and
drift from the hook's lock. It is the first increment, not the destination.

**One big-bang change.** Rejected because the frozen CLI covers races, interruptions, worktree
cleanup and evidence decisions. Small, independently green strangler changes can be reviewed and
reverted without replacing every subsystem at once.

**A package layout.** Rejected because skills install by directory copy, with no package manager
or distribution metadata. Flat co-installed modules provide imports without a new installation
contract.
