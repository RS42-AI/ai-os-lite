# External Integrations

## Granola Meetings

- **{WorkArea} folder name**: `{WorkArea}`

### Tool Patterns

```python
# Get meetings from {WorkArea} folder (PRIMARY method)
mcp__granola-mcp__get_folder_meetings(
    folder="{WorkArea}",
    from_date="7d",
    limit=15
)

# Search within folder
mcp__granola-mcp__search_meetings(
    folder="{WorkArea}",
    from_date="7d",
    limit=10
)

# Get meeting details
mcp__granola-mcp__get_meeting(meeting_id="[id]")
mcp__granola-mcp__get_meeting_notes(meeting_id="[id]")
mcp__granola-mcp__get_transcript(meeting_id="[id]")
```

## Todoist (Task Management)

- **Tier**: Pro ($5/mo annual)
- **CLI**: `td` (v1.22.1) — `npm install -g @doist/todoist-cli`
- **7 projects**: {WorkArea}, {SideArea2}, Personal, Health, Career, Finance, {SideArea} (+ Inbox)
- **7 labels**: @initiative, @waiting-for, @deep-focus, @quick-win, @follow-up, @{workarea-slug}, @{sidearea2-slug}

### Tool Patterns

```bash
# Add a task
td task add "Task description" \
  --project "{WorkArea}" \
  --labels "@{workarea-slug},@waiting-for" \
  --priority p2 \
  --due "today"

# List with filter
td task list --filter "overdue | today"
td task list --filter "@{workarea-slug} & overdue"
td task list --filter "search:key vault" --json

# Add comment (for mention tracking)
td comment add {task_id} --content "Mentioned again in journal 2026-03-13"

# Complete a task
td task complete {task_id}
```

### Key Principle

Todoist tracks *what you need to do today across your whole life*. Linear tracks *what you're building for {SideArea2}*. They don't overlap.

For full CLI reference, see `vault-config/references/todoist-patterns.md`.

## Source of Truth Hierarchy

### {WorkArea} Work
```
PRIMARY:    Granola Meetings
CONTEXT:    Obsidian Notes
TRACKING:   Linear (personal reflection only)
```

### {SideArea2} Work
```
PRIMARY:    Linear + GitHub
CONTEXT:    Obsidian Notes
```

### Personal
```
PRIMARY:    Obsidian Journal + Daily Notes
```

## Area Configuration

| Area | Primary Sources | Context Sources |
|------|----------------|-----------------|
| `{area-slug}` | Sources configured for that area | Obsidian |
| `{linear-area-slug}` | Linear, GitHub (when mapped) | Obsidian |

## Linear Workspace

### Teams
| Team | Purpose |
|------|---------|
| `{LinearTeam}` | Purpose recorded in the vault's `AGENTS.md` |
