---
name: vault-config
description: Shared operational config for the AI-OS Lite plugin — MCP/CLI tool patterns, integrations, search strategy, and error observability. Points at the vault's AGENTS.md for vault structure, taxonomy, and project identity. Referenced by all other skills — not user-invocable.
user-invocable: false
---

# Vault Configuration Hub

This skill is the shared home for the AI-OS Lite plugin's **operational config** — tool-selection patterns, integration setup, search strategy, and error observability. Other skills reference files in `references/` rather than duplicating this config.

**Vault structure, frontmatter taxonomy, and cross-system project identity are NOT defined here.** They are canonical in the vault's own instruction file, `~/Claude/ObsidianVault/AGENTS.md` — read it directly. Project and area existence is derived from the `2. Projects/` filesystem tree, never enumerated.

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

For vault structure, routing, taxonomy, or project identity → read `~/Claude/ObsidianVault/AGENTS.md` (and the `system-settings/vault-structure.md` it links for descriptive detail).

For operational tool patterns, read the relevant reference file:

```
Read references/tool-selection.md     → which tool for which operation
Read references/obsidian-patterns.md  → Obsidian MCP tool calls
Read references/todoist-patterns.md   → Todoist CLI patterns
Read references/linear-patterns.md    → Linear MCP tool calls
Read references/source-manifest.md    → source tracking + execution reports
```

All paths in reference files are relative to the user's Obsidian vault at `~/Claude/ObsidianVault/`.
