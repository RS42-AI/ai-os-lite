# Todoist Tool Patterns

## Tool Strategy

| Purpose | Tool | Why |
|---------|------|-----|
| Task CRUD (add, list, view, complete) | **Todoist CLI** (`td`) | CLI-first pattern, matches `obsidian`, `gws` |
| Comments (mention tracking, context) | **Todoist CLI** (`td comment`) | Thread updates without modifying task |
| Filter queries (cross-project, cross-label) | `td task list --filter` | Todoist's boolean filter language |

Do NOT use the Todoist MCP server — prefer the CLI (`td`) for all operations.

## CLI Version & Auth

```bash
td --version   # 1.22.1
td auth status  # check auth
td auth login   # re-authenticate if needed
```

## Task Operations

### Add Task

```bash
# Basic task with project, labels, priority, due date
td task add "Email {Contact} about key vault access" \
  --project "{WorkArea}" \
  --labels "@{workarea-slug},@waiting-for" \
  --priority p2 \
  --due "today"

# Initiative (no due date)
td task add "Explore Dallas as potential {SideArea} store location" \
  --project "{SideArea}" \
  --labels "@initiative"

# With description
td task add "Review inbox for unfiltered senders" \
  --project "{SideArea2}" \
  --labels "@{sidearea2-slug},@quick-win" \
  --priority p3 \
  --due "today" \
  --description "Check for repeat senders that slipped through Gmail filters"
```

### List Tasks

```bash
# All tasks
td task list

# By project
td task list --project "{WorkArea}"

# By label
td task list --label "@initiative"

# By priority
td task list --priority p1

# By due date
td task list --due today
td task list --due overdue

# JSON output (for parsing)
td task list --json
td task list --json --full  # all fields
```

### Filter Queries (Todoist filter language)

```bash
# Overdue + today
td task list --filter "overdue | today"

# Area-specific overdue
td task list --filter "overdue & @{workarea-slug}"

# All waiting-for items
td task list --filter "@waiting-for"

# Urgent {WorkArea} items
td task list --filter "p1 & @{workarea-slug}"

# Initiatives across all projects
td task list --filter "@initiative"

# Search by keyword
td task list --filter "search:key vault"

# Combined: overdue initiatives
td task list --filter "overdue & @initiative"

# This week's tasks
td task list --filter "due before: next Monday"
```

### View / Complete / Update

```bash
# View task details
td task view {task_id}

# Complete a task
td task complete {task_id}

# Update task
td task update {task_id} --priority p1
td task update {task_id} --due "tomorrow"
td task update {task_id} --labels "@{workarea-slug},@deep-focus"
```

### Delete Task

```bash
td task delete {task_id}
```

## Comment Operations

```bash
# Add comment to task (for mention tracking)
td comment add {task_id} --content "Mentioned again in journal 2026-03-13"

# List comments on a task
td comment list {task_id}

# View comment details
td comment view {comment_id}
```

## Project & Label Operations

```bash
# List all projects
td project list

# List all labels
td label list

# List sections in a project
td section list --project "{WorkArea}"
```

## Project Structure

```
Todoist Projects:
├── Inbox            # Unprocessed captures
├── {WorkArea}       # Employment work tasks
│   ├── Section: Active
│   ├── Section: Waiting For
│   └── Section: Blocked
├── {SideArea2}       # Side business tasks
│   ├── Section: Active
│   ├── Section: Waiting For
│   └── Section: Blocked
├── Personal         # Personal life tasks
├── Health           # Health & fitness tasks
├── Career           # Career development tasks
├── Finance          # Financial tasks
└── {SideArea}       # Family business tasks
```

## Label Taxonomy

| Label | Purpose | Example Query |
|-------|---------|---------------|
| `@initiative` | Multi-day effort, not yet graduated | `@initiative` |
| `@waiting-for` | Blocked on someone else | `@waiting-for & @{workarea-slug}` |
| `@deep-focus` | Requires concentrated work | `@deep-focus & today` |
| `@quick-win` | Under 15 minutes | `@quick-win` |
| `@follow-up` | Needs follow-up after completion | `@follow-up` |
| `@{workarea-slug}` | Area tag | `@{workarea-slug} & overdue` |
| `@{sidearea2-slug}` | Area tag | `@{sidearea2-slug} & p1` |

## Priority Mapping

| Todoist Priority | Meaning | When AI Assigns |
|-----------------|---------|-----------------|
| p1 (urgent) | Must do today / blocking others | Explicit deadline, blocker |
| p2 (high) | Important this week | Deadline this week, urgency words |
| p3 (medium) | Should do soon | Default for extracted priorities |
| p4 (normal) | Someday / low priority | Vague intention |

## Area-to-Project Mapping

| Area Wikilink | Todoist Project | Area Label |
|--------------|-----------------|------------|
| `[[{WorkArea}]]` | {WorkArea} | `@{workarea-slug}` |
| `[[{SideArea2}]]` | {SideArea2} | `@{sidearea2-slug}` |
| `[[Personal]]` | Personal | — |
| `[[Health & Fitness\|Health]]` | Health | — |
| `[[Career]]` | Career | — |
| `[[Finances]]` | Finance | — |
| `[[{SideArea}]]` | {SideArea} | — |

## Common Workflows

### Morning Carry-Forward Check
```bash
td task list --filter "overdue | today" --json
```

### Weekly Review — All Open Tasks
```bash
td task list --all --json --full
```

### Deduplication Before Creating
```bash
td task list --filter "search:{keyword}" --json
```

### Initiative Graduation Check
```bash
# Find initiative, check comment count
td task list --filter "@initiative" --json
td comment list {task_id}
# If 3+ mention comments → suggest graduation
```

## Important Notes

- Flag is `--labels` (plural), not `--label`, when creating/updating tasks
- Flag is `--label` (singular) when filtering with `td task list`
- Pro tier required for >5 projects and >3 filter views
- `td task list --filter "search:X"` is the dedup mechanism
- Tasks with `@initiative` label should NOT have due dates
- Always search before creating to prevent duplicates
