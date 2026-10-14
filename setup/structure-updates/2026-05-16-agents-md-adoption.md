---
id: 2026-05-16-agents-md-adoption
date: 2026-05-16
description: Historical instruction-file split; owner review only.
---

## Context

Earlier Kit releases moved shared standing rules into `AGENTS.md` and used
`CLAUDE.md` as a short pointer. Both files are now explicitly human-owned.
This historical update must never automatically create or rewrite either file.

## Detection

Inspect whether the owner has both files and whether their instructions
resolve consistently. Missing or divergent files are a review finding, not
permission to install defaults over customized rules.

## Changes

Prepare an exact proposed split for the owner. Preserve every local
customization, privacy rule and source copy. Explain what would change and
which current workflow depends on it. The owner applies any accepted change.
If a user declines, retain their files and report remaining compatibility gaps.

## Verification

After the owner confirms the change, check that both files exist and that
`CLAUDE.md` points at the intended shared instructions. Confirm local rules
remain intact. Only then record this update as applied. Otherwise leave it
pending and continue independently safe non-instruction updates.

## Rollback

The owner restores their saved original instruction files. Do not automate
rollback over later edits.
