# `PHASE-BOUNDARIES.md` is duplicated into `/next`, not shared with `/skill-router`

`skills/next/` and `skills/skill-router/` each carry their own full copy of `PHASE-BOUNDARIES.md`.
Duplication normally reads as an error, so the reason is recorded here: skills install
individually. `npx skills add bradcstevens/git-loopy-skills --skill=next` copies only
`skills/next/`, so a reference from one skill directory into another dangles for anyone who
installed just one of them. A shared file would be correct in this repo and broken on every
partial install.

## Consequences

- **The copies will drift.** Nothing about the format prevents one being edited without the other.
  `scripts/validate-skills.sh` already runs in CI, so it is where a checksum comparison of the two
  copies belongs.
- **Editing means editing twice.** Both copies are authoritative for their own skill; neither is the
  source the other derives from.

## Considered options

**Promote it to `docs/` and have both skills link there.** Rejected for the same reason — `docs/`
does not travel with an installed skill either, so the link resolves only inside this repo.
