---
id: 2026-09-06-project-structure-and-lifecycle
date: 2026-09-06
description: Complete established project containers, migrate legacy Personal roots through an exact preview, and align project lifecycle and optional shared identity.
---

## Context

Fresh and existing vaults need the same predictable project unit without
inventing projects or filler content. Every established project receives
`Tasks/`, `Notes/`, `Resources/`, `Artifacts/`, `Specs/`, and `Dev Log/`, even
when a destination is empty. Business area tasks remain under
`2. Projects/{Area}/Tasks/`, area-wide references remain under
`5. Resources/{Area}/`, and Personal uses numbered goal and project roots.

This update also carries the reviewed project lifecycle: draft projects may
have an empty goal; active projects require a resolving goal; the retired goal
classification and project/spec review status are migration findings rather
than accepted values. Optional `shared_id` and `shared_hub_url` fields connect
a real local project to an external hub without embedding any organization or
transport assumption.

## Detection

From the vault root, locate the kit from `.vault-kit-path`, then generate a
preview with the kit's `tools/project_structure.py plan` command, targeting the
current vault and writing `.vault-structure-preview.json` in the vault root.

This update applies when the preview reports any moves or missing directories,
when a direct `Personal/{Project}/` project hub, a legacy Personal goal root,
or the old `3. Areas/Personal/Personal.md` dashboard exists,
when either canonical template still offers a retired lifecycle value, or when
the Project Hub Template lacks the optional shared identity fields.

The preview separately lists unknown direct children of `Personal/`. Leave
those roots untouched until the owner identifies them. A destination collision,
a symlink inside a managed root, a binary path consumer, or an exact old-path
reference in `AGENTS.md`/`CLAUDE.md` blocks application. Instruction consumers
go to the human review proposal and are never rewritten by the helper. Do not
merge, rename, overwrite, or follow either side of a blocked path.

If the structural preview is empty and both templates already match, record
the update as vacuously applied.

## Changes

### Exact structural preview

Read `.vault-structure-preview.json` in full. Present every `mkdir`, every
source → target move, every path consumer and replacement count, every blocked
instruction/binary/symlink consumer, every collision, and every unknown legacy
root. The scan includes Obsidian configuration plus scripts and other UTF-8
files. Explain that directory creation is additive, moves preserve the
directory contents, and only boundary-matched old path strings (including
percent-encoded Markdown paths) in inventoried text consumers are rewritten.

Ask for approval of this exact preview. If approved, run the helper's `apply`
command against that preview and pass its `approval_token` unchanged.
Application stops if a source, destination, consumer, or plan changed since
preview. It writes a local receipt under `.vault-structure-migrations/` and
backs up rewritten consumers under `.vault-structure-backups/`. Do not record
this structure update as applied if the command stops.

### File: `system-settings/Templates/Project Hub Template.md`

Diff the installed template against the kit template. Merge only the reviewed
fields and lifecycle wording if the user customized other content:

- default `status: draft` and an empty `goal:`;
- optional `quarter_goal:`, `kr:`, `shared_id:`, and `shared_hub_url:`;
- no retired goal-classification field;
- an active project requires a resolving goal;
- an `## Artifacts` section that points to authoritative working files.

Do not backfill shared identity into existing project notes unless a real
external identity is supplied by the owner.

### File: `system-settings/Templates/Spec Template.md`

Remove the retired intermediate review status from the lifecycle reference.
Preserve customized spec sections and all existing spec notes.

### Existing lifecycle findings

Inventory existing project/spec notes that use a retired value. Remove the
retired goal-classification field mechanically only when the project's current
status and resolving goal already satisfy the simplified contract. Active
projects with empty or unresolved goals and notes using the retired
intermediate review status require a human lifecycle choice. Report them and
leave them unchanged until that choice is made.

### Human-owned instruction files

Do not edit `AGENTS.md` or `CLAUDE.md`. Show the owner the matching instruction
proposal for manual ratification. Template and structural changes may proceed;
instruction wording remains an explicit human gate.

## Verification

- Every detected established project at a supported business or numbered
  Personal root has all six required containers.
- Every immediate business area has `2. Projects/{Area}/Tasks/` and
  `5. Resources/{Area}/`; Personal has `Personal/Tasks/`,
  `Personal/1. Goals/`, `Personal/2. Projects/`, and
  `5. Resources/Personal/`.
- Approved legacy sources moved to their exact numbered destinations with file
  bytes preserved; blocked and unknown roots remain untouched.
- Every inventoried boundary-matched old-path consumer now points to the target,
  and no project name that merely shares a prefix was changed.
- The applied plan had no blocked instruction, binary, collision, or symlink
  consumer. Instruction files are byte-identical to their pre-update state.
- The Project Hub Template has the reviewed default, goal rule, identity
  fields, and Artifacts section; the Spec Template omits the retired status.
- Generate a second preview. It reports zero moves, zero missing directories,
  and zero consumers for the applied paths.
- Existing content, frontmatter identity, status, privacy, area names, project
  slugs, and journal paths are unchanged except for individually approved
  lifecycle edits.

## Rollback

Run the helper's `rollback` command with the exact receipt path printed by
`apply`. Rollback refuses to overwrite a source or restore a consumer that
changed after application. It reverses approved moves, restores rewritten
consumers from local backups, removes only still-empty directories created by
the migration, and keeps unrelated content. Restore template edits from the
pre-update Git state or their exact preview backups. Then generate a new
preview to verify the original migration inventory has returned.
