---
id: 2026-07-10-goal-rollup-fields
date: 2026-07-10
description: Reconcile project and spec templates to the simplified goal lifecycle without reviving retired intermediate states.
also_see: "[[2026-09-06-project-structure-and-lifecycle]]"
---

## Context

The original version of this update introduced an extra project-goal
classification and an intermediate review status. Later human review simplified
the contract: a draft project may have an empty `goal:`, an active project must
have one resolving goal link, and inactive lifecycle states remove active
pressure. The extra goal classification and project/spec review status are
retired migration debt. This compatibility revision keeps the historical update
id while ensuring an older vault cannot receive the retired model before it
reaches the September 6 structure update.

## Detection

This update applies when either shipped template still contains the retired
goal-classification field or the retired project/spec review status, or when the
Project Hub Template does not default to `status: draft` with `goal:` present.

Existing notes that contain those retired values are inventory for a reviewed
migration. Their presence does not authorize a bulk lifecycle decision.

## Changes

### File: `system-settings/Templates/Project Hub Template.md`

Merge the current kit template without overwriting unrelated user
customizations. The frontmatter defaults to `status: draft`, keeps an empty
`goal:`, and offers `quarter_goal:`, `kr:`, `shared_id:`, and
`shared_hub_url:`. Remove the retired goal-classification field. The template
must explain that changing a project to `active` requires a resolving goal.

### File: `system-settings/Templates/Spec Template.md`

Remove the retired intermediate review status from the lifecycle reference.
Allowed project/spec progress is `draft` → `active` → `done`, with `on-hold`,
`superseded`, and `archived` as pause or terminal states. `done` remains a human
decision.

### Existing project and spec notes

Prepare an exact inventory before editing:

- A draft or inactive project may have the retired goal-classification field
  removed without changing its status or goal.
- An active project with a resolving goal may have that field removed without
  another lifecycle decision.
- An active project with an empty or unresolved goal needs a human choice: add
  a real goal, return it to `draft`, or use an allowed inactive state. Do not
  infer the choice.
- A project or spec using the retired intermediate review status needs a human
  choice between `draft`, `active`, or an allowed inactive state. Do not map it
  automatically.

Do not backfill optional shared identity fields into existing hubs. They are
only written when a real external hub identity exists.

## Verification

- The Project Hub Template defaults to `status: draft`, has an empty `goal:`,
  and contains the two optional shared identity fields.
- Neither template offers the retired project/spec review status.
- The Project Hub Template does not offer the retired goal-classification
  field.
- Every changed existing hub retained its project identity and content.
- Unresolved active hubs and lifecycle choices are reported as open instead of
  being silently marked compliant.

## Rollback

Restore both templates and any individually approved note edits from the
vault's pre-update Git state. If the vault is not in Git, restore the exact
files from the preview backups created before applying this update. Re-running
the update after rollback must produce the same inventory.
