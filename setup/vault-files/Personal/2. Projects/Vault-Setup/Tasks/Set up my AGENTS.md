---
date: 2026-05-09
type: task
status: todo
area: personal
project: vault-setup
priority: p3
due_date: ""
scheduled_date: ""
done_date: ""
blocked_by:
  - "[[Set up my first goal]]"
blocked_reason: "Optional customization after choosing context; personal disclosure is not required"
unlocks: []
external_id: ""
tags:
  - task
  - onboarding
---

# Set up my AGENTS.md

> This task customizes the generic baseline; it does not expose private information unless you add it yourself.

## Why

`AGENTS.md` at the vault root is the **AI's instruction manual for your vault**. Every AI session in the vault — Claude Code, Codex, anything that follows the agent-instructions convention — reads it before doing anything. It tells the AI:

- What areas exist in *your* life (the `area` slugs)
- Which external systems you mirror projects into (GitHub, Linear, ADO, Notion — if any)
- Whether you use private projects (and how privacy inherits)
- Your conventions, preferences, workflow rules

The kit ships with a **generic AGENTS.md baseline** — universal structure, one placeholder `personal` area, optional sections stubbed but unfilled. Your job is to make it match *your* life.

This is the *first-time customization* task. For ongoing updates when the kit ships improvements, the vault has a separate mechanism — see [Updating later](#updating-later).

## Steps (first-time setup)

### 1. Open a Claude Code (or other AI assistant) session in your vault

Working directory must be the vault root so the assistant reads the correct instructions. It may propose targeted edits, but must not write them without your direct approval of the exact changes.

### 2. Paste this prompt

```
Read AGENTS.md at the vault root. It is the shipped generic baseline.
I want to tailor it to my life.

Interview me about:
- What areas I actually have (the kit ships only `personal` — what
  else? work, health, finances, side projects, etc.)
- Whether I mirror projects to any external system (GitHub, Linear,
  ADO, Notion); if so, build the Cross-System Identity table
- Whether I need additional privacy configuration; preserve the
  shipped privacy rules
- Any vault-specific conventions or routing rules I want to add

When you have my answers, propose targeted edits to AGENTS.md.
Preserve the shipped standing rules verbatim — only modify the
curated-config sections (Areas, Cross-System Identity, Privacy
configuration, anything custom I add). Show me the exact diff and wait
for my direct approval before writing. Let me skip questions that are
not relevant; do not invent areas, goals or account mappings.
```

The assistant should reuse context already given and ask only for needed choices. You may apply the exact diff yourself or directly authorize those edits. General permission to set up a workspace is not approval to change its instructions.

### 3. Commit

```bash
git add AGENTS.md
git commit -m "docs: set up AGENTS.md for my vault"
```

From now on, every AI session in your vault reads *your* version.

## Updating later

When the kit ships improvements to the canonical vault shape — a new section in `AGENTS.md`, a refreshed template, a renamed file — the kit's `structure-updates/` folder gets a new dated migration doc describing the change.

To apply outstanding updates, run the `/update-structure` slash command in Claude Code inside your vault:

```
/update-structure
```

It reads `structure-updates/` from the kit, detects which migrations apply to your current vault state, and walks you through each change with confirmation. Your customizations stay; the kit's improvements layer in. Re-runs are safe (idempotent).

For an inventory of what's applied vs. pending:

```
/update-structure --list
```

For a dry-run preview without changing anything:

```
/update-structure --dry-run
```

The AI will flag anything ambiguous and ask before changing it — that's expected, not an error.

## Done when

- [ ] You reviewed the proposed customization and applied or explicitly authorized the exact edits you wanted; retaining the starter area is allowed
- [ ] External-system identity captured if you use one (GitHub / Linear / ADO / Notion mapping)
- [ ] Applicable privacy rules are preserved and any additional configuration is your choice
- [ ] Reviewed the AI's report (what was added, what was omitted, any flagged questions)
- [ ] `AGENTS.md` is committed to git

## See also

- [[Vault-Setup]] — back to the orientation hub
- [[AI-Native Architecture - Business Logic as Agent Instructions]] — *why* an instruction file is the right architecture, not a hack
- `commands/update-structure.md` (in the kit) — the slash-command runner used for ongoing updates
