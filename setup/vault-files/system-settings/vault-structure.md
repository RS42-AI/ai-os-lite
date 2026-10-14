# Vault Structure — Reference

Load-on-demand structural detail linked from [[AGENTS]]. `AGENTS.md` holds the routing rules and the non-inferable area / `type` tables; this file holds the descriptive structure an agent reads only when it needs the full picture.

## Hub-and-Spoke Architecture

Area dashboards in `3. Areas/` (and `Personal/` for personal life) link to project hubs, which auto-populate via Obsidian Bases queries on the three routing properties (`type`, `area`, `project`). Content routes itself into the correct dashboard views.

## Folders

Numeric prefixes order the top-level folders in the sidebar; `Personal/` and `system-settings/` sit alongside without a prefix.

| Folder | Purpose | Note types |
|--------|---------|------------|
| `1. Daily/` | Daily note hubs (one per day) | `daily` |
| `2. Projects/` | Project docs organized by area | `project` hubs + `note`/`resource`/`task`/`devlog` |
| `3. Areas/` | Per-area dashboards + `Goals/` subfolder | `area-dashboard`, `goal` |
| `4. Contacts/` | People and meeting notes | — |
| `4. Contacts/People/` | Contact notes | `person` |
| `4. Contacts/Meetings/` | Meeting notes | `meeting` |
| `5. Resources/` | Human-curated reference material by area | `resource` |
| `5. Resources/Personal/` | Personal reference material; holds the compatibility `Journal/` subtree for Morning Briefs and Evening Entries | `resource`, `journal` |
| `6. Main Notes/` | General knowledge, not project-specific | `note`/`idea`/`thought` |
| `Personal/` | Self-contained `personal` area at the vault root, including `Personal.md` | `area-dashboard` |
| `Personal/1. Goals/` | Personal goal sub-hubs | `goal` |
| `Personal/2. Projects/` | Personal project units | `project` hubs + project content |
| `Personal/Tasks/` | Area-level personal tasks not tied to a project | `task` |
| `system-settings/` | Vault configuration | — |
| `system-settings/Contracts/` | Reviewed shape definitions; candidates are advisory | — |
| `system-settings/Templates/` | Note scaffolds that render reviewed contracts | — |
| `system-settings/Pasted Images/` | Media assets | — |

## Project Folders

Every established project uses the same six-container layout. Empty containers
are intentional destinations and are created by setup and structure repair:

```
{Project}/
├── {Project}.md       # Project hub with embedded Bases
├── Tasks/             # Actionable work items
├── Notes/             # Knowledge notes for this project
├── Resources/         # Reference material
├── Artifacts/         # Working documents and other project outputs
├── Specs/             # Design specs for this project
└── Dev Log/           # Project-specific session logs
```

**Where project folders live:**

- **Work / business projects** → `2. Projects/{Area}/{Project}/`
- **Personal-life projects** → `Personal/2. Projects/{Project}/`

For work or business areas, tasks without a project live at
`2. Projects/{Area}/Tasks/`; references spanning projects live at
`5. Resources/{Area}/`. Personal tasks without a project live at
`Personal/Tasks/`; personal-wide references live at `5. Resources/Personal/`.
Project-specific references remain in that project's `Resources/` container.

The project hub `.md` file (`type: project`) makes the project discoverable.
Setup finds established hubs and creates any missing containers without
changing their files. Existing direct `Personal/{Project}/` layouts migrate
only through `/update-structure`, after an exact preview and collision check.

## Goals

One file per goal: `3. Areas/{Area}/Goals/{Goal Name}.md` (`type: goal`). Each goal is its own sub-hub — an Objective plus Key Results — rather than a single horizon-aggregate file per quarter. Personal goals use `Personal/1. Goals/{Goal Name}.md`; business areas use their `3. Areas/{Area}/Goals/` folder.

## Morning Brief, Evening Entry & Daily Paths

The `journal` type and `Journal/` folder names remain stable for backward compatibility. User-facing workflows call these records Morning Briefs and Evening Entries. The kit ships with one area (`personal`), so the concrete paths are:

| Content | Path |
|---------|------|
| Daily note hub | `1. Daily/YYYY-MM-DD.md` |
| Morning Brief | `5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md` |
| Evening Entry | `5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md` |

## Knowledge Notes vs Devlogs

| | Knowledge Notes | Devlogs |
|--|-----------------|---------|
| Purpose | HOW things work | WHERE you left off |
| Title | By concept (no date prefix) | By date + session topic |
| Lifespan | Permanent, updated over time | Ephemeral, archived when project completes |
| Location | `6. Main Notes/`, `{Project}/Notes/` | `{Project}/Dev Log/` |
| Search priority | First-class | Second-class — exclude from "how does X work?" queries |
| Chain-linking | No | Yes — `Previous:` / `Next:` wikilinks per project |
