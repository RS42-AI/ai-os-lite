---
name: vault-config
description: Shared operational config for the AI-OS Lite plugin — MCP/CLI tool patterns, integrations, search strategy, and error observability. Points at the vault's AGENTS.md for vault structure, taxonomy, and project identity. Referenced by all other skills — not user-invocable.
user-invocable: false
---

# Vault Configuration Hub

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


This skill is the shared home for the AI-OS Lite plugin's **operational config** — tool-selection patterns, integration setup, search strategy, and error observability. Other skills reference files in `references/` rather than duplicating this config.

**Vault structure, frontmatter taxonomy, and cross-system project identity are NOT defined here.** They are canonical in the vault's own instruction file, the selected vault's `AGENTS.md` — read it directly. Project and area existence is derived from the `2. Projects/` filesystem tree, never enumerated.

## Substituting example placeholders

The skill prose and reference files use **shape placeholders** — `{WorkArea}`, `{SideArea}`, `{SideArea2}`, `{Project}`, `{Contact}`, `{TICKET}` (and their slug forms `{workarea-slug}`, `{sidearea-slug}`, `{sidearea2-slug}`, `{project-slug}`) — wherever a concrete example would otherwise hardcode one person's life. They are **shapes, not literal text.** Before emitting anything that contains one, substitute the user's real value:

| Placeholder | Substitute with |
|---|---|
| `{WorkArea}`, `{SideArea}`, `{SideArea2}` | An area *name* from the `AGENTS.md` areas table — the primary work area, and secondary areas (side business, family, etc.) respectively |
| `{workarea-slug}`, `{sidearea-slug}`, `{sidearea2-slug}` | The matching `area` *slug* from that same table |
| `{Project}`, `{Project1}`, `{Project2}`, `{Project3}` | A real project from the `2. Projects/{Area}/` filesystem |
| `{project-slug}` | That project's slug (lowercase, spaces → hyphens) |
| `{Contact}`, `{Contact1}` | A person from `4. Contacts/People/` relevant to the current context |
| `{TICKET}` | The Linear team prefix from the `AGENTS.md` cross-system identity table (e.g. `RS4-42`); omit the ticket annotation entirely if the area has no Linear team |

**If a placeholder cannot be substituted** — no work area defined, no projects under the area, no Linear team configured — **drop that example clause entirely** rather than print the token. A user must never see a literal `{WorkArea}`, `{Project}`, or any other life-shaped placeholder in rendered output (daily notes, tasks, journal hubs, commit messages, Todoist entries).

This rule is specifically about the life-shaped placeholders above. Structural tokens like `{Area}` (path notation for "any area"), `{today}`, and JSON-field names (`{reason}`, `{slug}`) are ordinary template variables filled from the filesystem or runtime — leave those as the consuming skill describes.

## Reference Files

| File | Contents |
|------|----------|
| `references/integrations.md` | Granola, Todoist, area configuration |
| `references/todoist-patterns.md` | Todoist CLI patterns, filter queries, project/label taxonomy |
| `references/obsidian-patterns.md` | Obsidian MCP tool patterns and search strategies |
| `references/linear-patterns.md` | Linear MCP tool patterns and batch approval workflow |
| `references/tool-selection.md` | CLI-vs-MCP tool selection matrix |
| `references/search-and-discovery.md` | Two-layer (structural + semantic) search strategy |
| `references/source-manifest.md` | Error observability — source tracking, execution reports, failure recovery |

## How to Use

For vault structure, routing, taxonomy, or project identity → read the selected vault's `AGENTS.md` (and the `system-settings/vault-structure.md` it links for descriptive detail).

For operational tool patterns, read the relevant reference file:

```
Read references/tool-selection.md     → which tool for which operation
Read references/obsidian-patterns.md  → Obsidian MCP tool calls
Read references/todoist-patterns.md   → Todoist CLI patterns
Read references/linear-patterns.md    → Linear MCP tool calls
Read references/source-manifest.md    → source tracking + execution reports
```

All paths in reference files are relative to the selected vault. Pass its path explicitly to helper scripts or set `PERSONAL_OS_VAULT`; the historical home-directory default is only a fallback.

## Local files and optional connections

The base workflow uses ordinary local Markdown files. Prefer the runtime's
filesystem read/write tools for that selected vault when the Obsidian CLI or
MCP connection is absent. A named command in an example is not proof that the
tool is installed. Check availability; preserve sections and human input when
substituting a bounded local edit for an Obsidian patch.

Todoist examples use the optional `td` CLI specifically. Installing the Lite
plugin or another Todoist integration does not install that CLI. When it is
absent, skip external Todoist reads/writes and continue with vault task notes;
do not tell the user that their local tasks are missing. If a configured tool
fails, report the failure separately from an unconfigured source. External
sync or task creation still requires the workflow's explicit authorization.
