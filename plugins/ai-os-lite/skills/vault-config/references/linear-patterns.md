# Linear MCP Tool Patterns

## Safety: Batch Approval Pattern

**NEVER update or create Linear issues without explicit user approval.**

### Mandatory Write Flow

1. **Analyze** — Review data, determine what should change
2. **Propose** — Present changes in checklist format with evidence
3. **Wait** — Ask for explicit user confirmation
4. **Execute** — Only after "yes" / "approve" / "go ahead"
5. **Verify** — Confirm successful updates

```markdown
## Proposed Linear Updates

### Tasks to Mark Complete
- [ ] [PROJ-123] "Task title" — Evidence: [source]

### New Issues to Create
- [ ] "New task" — Source: [evidence]

**Review these changes. Would you like me to apply them?**
```

## Read Patterns (Safe, No Approval Needed)

### Get My In-Progress Tasks
```python
mcp__linear__list_issues(
    assignee="me",
    state="In Progress"
)
```

### Get All My Tasks
```python
mcp__linear__list_issues(
    assignee="me"
)
```

### Get Project Issues
```python
mcp__linear__list_issues(
    project="{Project}"
)
```

### Get Issue Details
```python
mcp__linear__get_issue(
    id="RS4-123"
)
# Returns: title, description, status, assignee, priority, labels, comments
```

### Get Project Details
```python
mcp__linear__get_project(
    query="{Project}"
)
```

### List All Projects
```python
mcp__linear__list_projects()
```

### List Teams
```python
mcp__linear__list_teams()
```

### List Available Statuses
```python
mcp__linear__list_issue_statuses(
    team="RS42"
)
```

## Write Patterns (Require Approval)

### Update Issue Status
```python
# After user approval
mcp__linear__save_issue(
    id="RS4-123",
    state="Done"
)
```

### Create Issue
```python
# After user approval
mcp__linear__save_issue(
    team="RS42",
    title="Implement process-journal skill",
    project="{Project}",
    description="Details...",
    priority=2,
    labels=["feature"]
)
```

### Create Comment
```python
# After user approval
mcp__linear__create_comment(
    issueId="RS4-123",
    body="Status update: completed initial implementation."
)
```

## Teams

| Team | Purpose |
|------|---------|
| RS42 | Internal projects, plugins, tools |
| {WorkArea} | Client work (personal tracking only) |

## Best Practices

### Reads
- Filter early with `assignee`, `state`, `project`
- Use `limit` parameter (default 50 is usually sufficient)
- Get specific issue when ID is known

### Writes
- **Always propose first** — never write without showing user
- **Evidence-based** — only suggest updates backed by clear evidence
- **Batch together** — propose multiple changes at once
- **Confirm success** — verify write operations succeeded

### Safety Guardrails
- Never auto-update without approval
- Never guess at task status without evidence
- Never create tasks for minor notes
- Never retry failed writes automatically
