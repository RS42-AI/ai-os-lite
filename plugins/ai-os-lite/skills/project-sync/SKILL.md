---
name: project-sync
description: "Refresh a project hub's Current Status section with evidence from recent devlogs, notes, and external systems (Linear). Use when the user says \"project sync\", \"sync project\", \"refresh hub\", or \"/project-sync\"."
user-invocable: true
allowed-tools:
  # Gather script (deterministic context collection)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/project-sync/scripts/*.sh:*)
  - Bash(chmod:*)
  # Obsidian CLI (link traversal reads)
  - Bash(obsidian read:*)
  - Bash(obsidian search:*)
  - Bash(obsidian files:*)
  # Obsidian MCP (hub patching + task note creation)
  - mcp__obsidian-mcp-tools__patch_vault_file
  - mcp__obsidian-mcp-tools__create_vault_file
  # Linear MCP (configured workspace issues)
  - mcp__linear__list_issues
  # QMD (cross-project search fallback)
  - mcp__qmd__search
---

# Project Sync

Refresh a project hub's `## Current Status` section by gathering evidence from devlogs, task notes, knowledge notes, cross-project devlogs, and external task systems, then proposing updates with batch approval.

**This skill WRITES to vault files. Always propose changes first and wait for user approval.**

## Key Principles

1. **Task notes are the unit of work** — every tracked item is a task note with frontmatter status. Checkbox lists on hubs are replaced by Bases queries.
2. **6 evidence sources** — devlogs, task notes, knowledge notes (body scan), cross-project devlogs, hub current status, and Linear. The gather script handles deterministic sources; the skill handles MCP sources and link traversal.
3. **Batch approval before any edits** — show exactly what will change, wait for explicit "yes".
4. **Only modify Current Status text and task note frontmatter** — Bases queries auto-populate everything else.
5. **No silent failures** — track every source call, report what succeeded/failed/skipped. See `vault-config/references/source-manifest.md`.
6. **Reference shared config** — project identity from the vault's `AGENTS.md` (Cross-System Identity section), tool patterns from `vault-config/references/obsidian-patterns.md` and `vault-config/references/linear-patterns.md`.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. The gather script tracks deterministic sources automatically via `source_manifest`. MCP sources (Linear) and link traversal reads are tracked by you.

| # | Source | Used For | Criticality |
|---|--------|---------|-------------|
| 1 | Task notes (via script) | Task frontmatter + body wikilinks | REQUIRED |
| 2 | Project devlogs (via script) | 5 most recent with previews | REQUIRED |
| 3 | Knowledge notes (via script) | Resolution/Update section headings | MEDIUM |
| 4 | Hub Current Status (via script) | Current state text | REQUIRED |
| 5 | Cross-project devlogs (via script) | Mentions of this project in other Dev Log folders | MEDIUM |
| — | Linear MCP (you call this) | Configured Linear issue status | MEDIUM |
| — | Link traversal (you do this) | Follow wikilinks from tasks/knowledge notes | MEDIUM |
| — | Obsidian MCP | Patch hub + create task notes | REQUIRED |

## Invocation

```
/project-sync {project-slug}   → sync that project's hub
/project-sync                  → ask user which project
```

---

## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.

## Step 1: Run the Gather Script

Collect all deterministic context data:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-sync/scripts/gather_project_context.sh <slug>
```

Parse the JSON output. It contains:

- `project` — resolved identity: slug, area, display name, hub path, devlog/notes/tasks dirs
- `hub_status` — full text of the Current Status section from the hub
- `tasks` — all task notes in the project's `Tasks/` folder with frontmatter (status, type, linked_notes, external_ids) and body wikilinks
- `devlogs` — 5 most recent devlogs with frontmatter + 30-line content preview
- `knowledge_notes` — notes in the project's `Notes/` folder, scanned for `## Resolution`, `## Update`, or `## Status` headings (`has_resolution_section: true/false`)
- `cross_project_devlogs` — devlog entries in *other* projects' `Dev Log/` folders that mention this project's slug or display name (with line-level match context)
- `workitems` — external work-item stub (inert; connect Linear via MCP)
- `staleness` — days since last devlog, `is_stale` flag (threshold: 7 days)
- `source_manifest` — what succeeded and what failed per source

If the script fails to execute:

```bash
chmod +x ${CLAUDE_PLUGIN_ROOT}/skills/project-sync/scripts/gather_project_context.sh
```

**If `project.hub_exists` is false**: Report "Project hub not found for slug '{slug}'. Valid project slugs are derived from the `2. Projects/` tree — see Cross-System Identity in the vault's `AGENTS.md`." and stop.

---

## Step 2: Supplement with MCP Tools and Link Traversal

The gather script cannot call MCP tools or follow wikilinks. Fill in those gaps now.

### 2a: Linear Issues (configured projects only)

Read the vault's `AGENTS.md` Cross-System Identity mapping. If the project has a Linear workspace/team or project mapping, query it:

```python
mcp__linear__list_issues(project="{project_name}", assignee="me")
```

If the project has no Linear mapping, skip this source without error. Record failures and continue if configured but unavailable.

### 2b: Link Traversal

For each task note in `tasks[]` that has `linked_notes` wikilinks:

```bash
obsidian read path="{linked_note_path}"
```

For each knowledge note where `has_resolution_section: true`, read the resolution/update section content to extract evidence of completion or status change.

For each cross-project devlog entry in `cross_project_devlogs`, read the surrounding context if the line-level preview is insufficient to determine relevance.

### 2c: Full Devlog Reads (if previews are insufficient)

The script provides 30-line previews. If a devlog preview is ambiguous — e.g., you cannot tell whether a task was completed from the preview alone — read the full file:

```bash
obsidian read path="{devlog_path}"
```

Only do this for devlogs where the preview is genuinely ambiguous. Do not read all 5 by default.

---

## Step 3: Analyze and Propose Updates

With all evidence gathered, determine what needs to change.

### 3a: Task Status Changes

For each task note in `tasks[]`, evaluate evidence across all sources:

- **CLOSE** — Set `status: done` + stamp `done_date: {today}` if: devlog evidence shows the work is done, OR a linked knowledge note has a `## Resolution` section confirming completion, OR Linear shows the issue is closed, OR a cross-project devlog references this task as done. If `external_id` exists and references Todoist, also complete the Todoist item.
- **ON-HOLD** — Set `status: on-hold` + set `blocked_by: "{reason}"` if: evidence shows the task is blocked, waiting on an external dependency, or explicitly deferred.
- **STALE** — Flag if `staleness.is_stale: true` and the task has had no devlog references in the stale window. Annotate with day count.
- **NO CHANGE** — Task status is consistent with evidence. No update needed.

### 3b: New Task Discovery

Review devlogs with `tasks: []` (no linked task IDs). If a devlog describes substantial work that is not tracked by any existing task note, propose creating a new task note. Verb-first task name, scoped to a single deliverable.

### 3c: Hub Status Brief

Draft a replacement for the Current Status section: 3–5 short statements, each on its own line separated by a blank line. One statement per topic (e.g., completed milestone, follow-up session, remaining work, staleness). This keeps the section scannable in Obsidian — a dense paragraph is hard to parse at a glance. Reference devlogs and task notes with pipe alias wikilinks. Include staleness flag if `is_stale: true`.

---

## Step 4: Present Proposed Changes

Show the user exactly what will change before writing anything:

```markdown
## Proposed Updates for [Project Name]

**Hub**: `{hub_path}`
**Evidence**: [N] devlogs, [N] task notes, [N] knowledge notes, [N] cross-project refs, [Linear status]
**Staleness**: [N] days since last devlog

---

### Task Status Changes

CLOSE (set status: done, stamp done_date):
- [[Task Note Name]] → done (done_date: {today})
  Evidence: [[2026-03-20 - Session Title|2026-03-20]] — "completed the ADF trigger wiring"

ON-HOLD (set status: on-hold, set blocked_by):
- [[Task Note Name]] → on-hold (blocked_by: "waiting on VPN access")
  Evidence: [[2026-03-22 - Session Title|2026-03-22]] — "can't proceed without VPN"

CREATE (new task note):
- "Wire retry logic for ADF pipeline" *(source: [[2026-03-22 - Session Title|2026-03-22]])*
  → status: todo, priority: p3

STALE (flag, no status change):
- [[Task Note Name]] — no devlog activity in 14 days *(priority: p2, due: 2026-04-01)*

NO CHANGE:
- [[Task Note Name]] — status consistent with evidence

---

### Hub Updates

**Current Status** (replace section):
> [Statement about completed work with [[wikilink|date]] evidence]
>
> [Statement about follow-up or in-progress work]
>
> [Statement about remaining work or staleness flag]

---

Apply these changes? [yes / no / edit]
```

**Wait for explicit user confirmation before proceeding to Step 5.**

---

## Step 5: Apply Approved Changes

Only after user confirms "yes" or "approve":

### 5a: Update Task Note Frontmatter

For each CLOSE task, patch the task note's `status` and `done_date` fields:

```python
# Step 1: Set status to done
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="status",
    content="done"
)

# Step 2: Stamp done_date
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="done_date",
    content="{today}"
)

# Step 3: Complete Todoist item if external_id references Todoist
# If external_id starts with "Todoist:":
# td task complete <task_id>
```

### 5a-bis: Set On-Hold Task Notes

For each ON-HOLD task, patch both fields:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="status",
    content="on-hold"
)

mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="blocked_by",
    content="{reason}"
)
```

### 5b: Create New Task Notes

For each CREATE task, create a new task note in `2. Projects/{Area}/{Project}/Tasks/`:

```python
mcp__obsidian-mcp-tools__create_vault_file(
    filename="2. Projects/{Area}/{Project}/Tasks/{Task Name}.md",
    content="""---
date: {today}
type: task
status: todo
area: {area}
project: {slug}
priority: p3
due_date: ""
scheduled_date: ""
done_date: ""
blocked_by: ""
external_id: ""
tags:
  - task
---

# {Task Name}

> **Project**: [[{Project Hub}]]

## Context

{1-2 sentences from the originating devlog}

## Dev Log

```base
filters:
  and:
    - type == "devlog"
    - tasks == "[[{Task Name}]]"
views:
  - type: table
    name: Related Sessions
    order:
      - date
      - file.name
      - session_topic
    sort:
      - property: date
        direction: DESC
```
"""
)
```

### 5c: Patch Hub Current Status

Replace the Current Status section. This pattern works whether the heading is `##` or `###`:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{hub_path}",
    operation="replace",
    targetType="heading",
    target="Current Status",
    content="""<!-- Refreshed by /project-sync on {today} -->

{Statement about completed work with [[wikilink|date]] evidence}

{Statement about follow-up or in-progress work}

{Statement about remaining work or staleness flag}
"""
)
```

### 5d: Update Last Updated Date

If the hub has a `**Last Updated**` line:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{hub_path}",
    operation="replace",
    targetType="content",
    target="**Last Updated**",
    content="**Last Updated**: {today}"
)
```

---

## Step 6: Report Results

Display a summary followed by the execution report:

```markdown
Project hub synced for [{project_name}].

**Changes**: N tasks closed, N tasks created, N stale flagged, hub status updated
**Staleness**: [current / stale (Nd)]

Hub: [[{hub_path}]]

---
### Execution Report

#### Sources
- [x] Gather script — hub status, N task notes, N devlogs, N knowledge notes, N cross-project refs
- [x] Linear — N issues (or skipped: not configured / FAILED: error)
- [x] Link traversal — N notes read
- [x] Obsidian MCP — hub patched, N task notes updated, N task notes created

#### Warnings
- [only if there are actual warnings]

#### Fix
- [only if there are failed sources with actionable fixes]
```

Only include Warnings and Fix sections if there are actual issues.

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Hub not found | Report with valid slugs derived from the `2. Projects/` tree, stop |
| No devlogs exist | "No devlogs found. Hub cannot be synced from evidence." |
| No Current Status section | "Hub has no Current Status section. Consider adding one." |
| No Tasks/ folder | Skip task note sources, note in execution report, continue |
| External system unavailable | Continue with devlog evidence, note failure in execution report |
| No changes needed | "Project hub is already current. No updates proposed." |
| Hub was manually updated today | Still run — may find devlog details not captured in manual update |
| Project is stale (>7d) | Flag staleness; suggest `status: paused` if >30d stale |
| Re-run same day | Idempotent — propose only changes not already applied |
| Task note with no devlog refs | Include in report as unverified; do not auto-close |

---

## What This Skill Does NOT Do

- **Todoist completion** — completes Todoist item on CLOSE if task note has external_id with Todoist reference. Does not create or defer Todoist tasks.
- **Does not write to Linear** — read-only from external systems
- **Does not create devlogs** — devlogs are created during work sessions
- **Does not modify Knowledge Notes or Devlogs** — only touches hub Current Status and task note frontmatter
- **Does not run across all projects** — single-project invocation; batch mode is for `/weekly-review` (future)

---

## Format Rules

- CLOSE proposals: `[[Task Name]] → done (done_date: {today})` with evidence quote and devlog wikilink
- ON-HOLD proposals: `[[Task Name]] → on-hold (blocked_by: "{reason}")` with evidence
- CREATE proposals: verb-first task name (e.g., "Wire retry logic for ADF pipeline")
- STALE flags: `[[Task Name]] — no devlog activity in {N} days`
- Hub status brief: 3–5 short statements, one per line separated by blank lines — not a paragraph. Past-tense for completed work, present-tense for active work
- All devlog references use pipe alias format: `[[2026-03-20 - Session Title|2026-03-20]]`
- Section links use: `[[devlog#Section|date → Section]]`
- Task note wikilinks use display name only: `[[Task Note Name]]`
