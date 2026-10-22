---
id: 2026-07-10-agents-md-closed-enums
date: 2026-07-10
description: Retire the historical automatic instruction rewrite and defer current closed-enum wording to human review.
also_see: "[[2026-09-06-project-structure-and-lifecycle]]"
---

## Context

The original form of this update told an agent to replace large sections of
`AGENTS.md`. It also carried project lifecycle rules that were superseded by a
later human decision. Instruction files are human-owned, so a structure updater
must not mutate them. The current template and folder changes are delivered by
the September 6 update; matching instruction wording is an exact proposal for
the vault owner to ratify and paste manually.

## Detection

This historical automatic rewrite never applies. Record it as vacuously
applied. If the installed instruction wording differs from the current Kit
proposal, report the difference during the September 6 update without editing
the file.

## Changes

### File: `AGENTS.md`

Make no automatic change. Preserve the owner's area list, routing choices,
project identities, privacy rules, and other local instructions. Present the
current generic proposal and explain its user-visible routing and lifecycle
effect. Only the human owner may ratify and paste it.

### File: `CLAUDE.md`

Make no change. Preserve the existing pointer or local Claude-specific
instructions.

## Verification

- `git diff -- AGENTS.md CLAUDE.md` is empty for this update.
- The September 6 structure update remains available to align templates and
  folders without claiming that instruction wording was ratified.
- Any instruction mismatch is reported as a human-content gate rather than a
  successful automatic repair.

## Rollback

No rollback is needed because this compatibility update writes no files. If an
older updater already changed an instruction file, the human owner must compare
it with their pre-update Git version and decide what to restore.
