---
name: vault-audit
description: Deterministic vault conformance audit — grades the live vault against AGENTS.md's closed enums, routing, goal wiring, connectivity, structure, hygiene, and privacy contracts, then reports violations vs smells and offers the human-gated structure repair. Use when the user says "vault audit", "audit the vault", "vault health", "vault doctor", or "/vault-audit".
user-invocable: true
allowed-tools:
  # Deterministic checkers (read-only; repair is dry-run by default)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/vault-audit/scripts/audit_vault.py:*)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/vault-audit/scripts/repair_structure.py:*)
  - Bash(jq:*)
---

# Vault Audit

Grades the live vault against the contracts in `AGENTS.md` and reports a
categorized health read. The checking is **deterministic scripts** — the AI
layer only ranks, summarizes, and (with approval) drives the repair tool.

## Key Principles

1. **The contract is AGENTS.md.** The auditor parses the closed enums from the
   vault's own `AGENTS.md` at runtime. A contract parse failure (exit 2) is a
   finding in itself — report it, don't work around it.
2. **Report-only by default.** The audit never mutates the vault.
   `repair_structure.py` runs dry-run first; `--apply` only after the user
   approves the printed plan.
3. **Never write `status: done`** — on anything. Proposing completion is fine;
   stamping it is human-only.
4. **Violations ≠ smells.** Violations are contract breaches (report first);
   smells are confidence signals (report second, never inflate).
5. **Manual-first.** No cron, no scheduling. Arming a weekly run is a separate,
   later decision by the human.

## Invocation

```
/vault-audit           → audit the vault, report, offer structure repair
/vault-audit report    → audit + full markdown report, no repair offer
```

## Step 1: Run the auditor

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/vault-audit/scripts/audit_vault.py "<vault path>" --no-fail > "$TMPDIR/vault-audit.json" 2>"$TMPDIR/vault-audit.banner"
cat "$TMPDIR/vault-audit.banner"
```

The vault path comes from the session's working vault (CWD when launched
inside the vault). Exit 2 = contract failure: show the CONTRACT ERROR lines
and stop — the fix is editing AGENTS.md, not bypassing it.

## Step 2: Read and rank

Parse the JSON (`jq`): lead with the banner verdict, then `by_check` counts.
Summarize the top gaps — violations grouped by check with file lists (cap 10
per check), then smells as counts only unless the user asks. Never paste the
raw JSON into chat.

## Step 3: Offer structure repair (only if structure.* findings exist)

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/vault-audit/scripts/repair_structure.py "<vault path>"
```

Show the dry-run plan. **Ask the user** before re-running with `--apply`.
After applying, re-run Step 1 and report the delta.

## Step 4: Report

End with: health verdict, violations/smells counts, top 3 actions (which may
include "edit AGENTS.md" or "run /update-structure" for contract gaps), and
what was repaired (if anything).

## What This Skill Does NOT Do

- Auto-fix taxonomy/routing/connectivity findings (structure repair is the only
  fixer, and it is human-gated)
- Write `status: done`, promote notes to resources, or archive anything
- Schedule itself (manual-first; see the AI-OS scheduling engine for arming)
- Audit external systems (Linear/ADO/Todoist)
