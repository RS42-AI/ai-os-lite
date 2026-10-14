---
name: write-note
description: Write or edit a vault note to ontology standard — canon-live routing, closed-enum frontmatter, typed links as triples, propose-don't-invent. Use when the user says "write a note", "capture this as a note", "add this to the vault", "note this down", or "/write-note". Also the write path other AI-OS Lite skills should delegate note creation to.
user-invocable: true
allowed-tools:
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/write-note/scripts/lint_note.py:*)
---

# Write Note

## Human license check

Before performing this AI-OS Lite workflow, verify the selected workspace has
a current human-response record for this installed package's exact license
version, SHA-256 and draft/release state. Follow the shared
[license review and receipt flow](../setup-context/SKILL.md#license-review-before-setup-writes).
A matching record is reused without another prompt. If missing, stale or
incomplete, show the complete bundled license through that flow and wait for
the person's actual YES, typed name, capacity and organizational authority
where applicable. Never infer assent, fabricate a record, accept for the user,
or use a terminal to impersonate human input. A draft record is nonoperative.
Read-only license orientation may continue while review is pending. Reading
this reference as part of the license review does not require prior assent.
This is an instruction-level check; it does not authenticate identity or
technically prevent direct execution of individual helper scripts.


Creates or edits one vault note so it grows the vault's ontology instead of
eroding it. Zero embedded schema: every routing rule, enum value, and verb
comes from the vault's `AGENTS.md` **read at runtime**. If this file and
AGENTS.md ever disagree, AGENTS.md wins.

Shared config (vault path, search tooling): see the `vault-config` skill.

## Key Principles

1. **Compile the live canon.** Read closed enums, routing, relationships, and
   standing policy from `AGENTS.md`, then read `system-settings/Contracts/`.
   Only `ratified` profiles with approval receipts govern new AI output.
   Candidate or missing profiles are reported as coverage gaps and never
   promoted into blocking schema.
2. **No sentence, no link.** Every typed relationship must be sayable as
   `A —verb→ B` using only the vault's ratified verb table.
3. **Propose, don't invent.** No fitting verb → `proposed_verbs`; unknown
   entity → `new_entity_candidate`. Proposals go to the human, never the canon.
4. **Never write `status: done`** or promote note→resource — human-only stamps.
5. **Lint before claiming success.** A note that fails `lint_note.py` is not
   written; fix and re-lint.

## The write path

### Phase 1 — Load the canon

Read from the vault's `AGENTS.md`: the "File Routing — Decision Tree" section,
the `type` values table, the per-type `status` table, and the
"Relationship verbs — CLOSED LIST" table. Compile the matching node, body, and
relationship profiles from `system-settings/Contracts/`. Enforce a profile for
new output only when it is `ratified`, has an approval receipt, and its scope is
`writer_only` or `all_instances`. Report candidate, incomplete, malformed, and
missing profiles as advisory coverage gaps. Never infer shape from them.

Resolve the canonical template through `template-contract.json` when it exists,
accepting its current `system-settings/Contracts/` location and the historical
`system-settings/Templates/` location during upgrades. A template renders the
compiled rules; it never creates schema. If the manifest/profile is missing or
candidate, use the template only as scaffolding, follow the standing rules in
`AGENTS.md`, lint, and report the gap without blocking otherwise valid writing.

If AGENTS.md has no Relationship-verbs table, the ontology contract isn't
installed in this vault yet — pause and suggest running `/update-structure`
(kit update `2026-07-26-relationship-verbs-ontology`) before writing typed
links. Routing and enum phases still apply.

### Phase 2 — Search before create

Search the vault for existing coverage per AGENTS.md's "Vault Search Strategy"
section and the `vault-config` skill's `references/search-and-discovery.md`.
Overlap decision tree:
- **Strong overlap** (same concept) → extend the existing note; one canonical
  note per concept.
- **Partial overlap** → new note + typed link to the neighbor.
- **No overlap** → new note.

### Phase 3 — Route

Walk the AGENTS.md decision tree top to bottom; the first matching rule wins.
Never a remembered folder. Final rule (unsure) → ask the user.

### Phase 4 — Frontmatter

Follow an effective ratified node profile when one exists and render with the
canonical template; otherwise use the template as advisory scaffolding. The
current deterministic lint implements ratified body-anchor checks and the
standing enum, route, and relationship-syntax rules. It reports reviewed node
or relationship profiles as coverage until their deterministic checks exist;
the writer still follows those reviewed profiles and discloses that tool gap.
Values only from the closed enums; `area:` /
`project:` resolved per AGENTS.md Cross-System Identity. Verb fields are
**only-when-true**: written only when the relationship exists, never empty.

### Phase 5 — Typed linking (the ontology core)

Extract the note's relationships as triples with this contract:

> Extract relationships as triples `subject —verb→ object` using ONLY the verb
> vocabulary from AGENTS.md's relationship-verbs table. Subjects/objects must
> be existing vault entities, or be flagged `new_entity_candidate`. If no
> approved verb fits, DO NOT invent one — list it under `proposed_verbs` with
> one example sentence. Every triple cites the supporting line of the note.

Write surviving triples as frontmatter list properties on the subject note
(e.g. `uses_system: ["[[Obsidian]]"]`). `part_of` is never a field —
it is `project:`/`area:` + folder placement. Prose wikilinks that pass the
sentence test may also get a typed field; those that don't stay as untyped
ambience. Every new note declares a parent (`> **Parent**: [[Hub]]`) and at
least one typed relation.

### Phase 6 — Provenance, lint, and the human gate

1. Stamp `created_by: ai` in the frontmatter (AI-authored notes only).
2. Before writing, resolve the destination from the installed area-folder table
   and the actual project hub directory. Follow the installed instruction
   routing for new personal projects. Both `Personal/{Project}/` and
   `Personal/2. Projects/{Project}/` are supported; a structure profile alone
   does not authorize replacing a human-owned routing rule or moving an
   existing project. Never send a business-area task to `Personal/Tasks/`.
3. Write the note, then lint it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/skills/write-note/scripts/lint_note.py <vault> <note>
```

   Exit 1 → fix the reported violations and re-lint. Exit 2 → the canon
   itself failed to parse; report it, do not work around it.
4. Report to the human: the note path, its typed relations as sentences, and
   any `proposed_verbs` / `new_entity_candidate` items. Append proposals to
   `6. Main Notes/Ontology Proposal Ledger.md` (create from the note template
   on first use, `type: note`, `status: capture`) — one dated bullet per
   proposal so rule-of-three counting is a grep. Ratifying a proposal (new
   verb or entity type) is a human-only constitutional act.

## Edit mode

When invoked on an existing note (adding a discovered relationship, extending
coverage): apply Phases 1, 5, and 6 only — never rewrite routing or type of an
existing note without the user asking.
