---
date: 2026-10-12
type: journal
journal_type: morning
tags:
  - journal
habit_morning_brief: false
---

%% `habit_morning_brief` is set to true by /process-morning. Add your own `habit_*` properties only if they are useful to you; no personal habit is required. The `journal` type and path remain for backward compatibility. %%

# Daily Hub: [[1. Daily/2026-10-12|2026-10-12]]

### Overall Read
> **Previous Evening**: NO EVENING ENTRY
> **Recent trend**: No captured work in the local window 10/12 -> 10/12.
> - **Key insight for today**: Choose one small project for “Add my first project”; the goal and instruction tasks depend on that choice.
> - **Meeting Prep**: No meeting notes found for today.

### Movement From Yesterday +/- 1
- No captured work in the local window.

---
### Control Queue
#### Review
- [[Personal/2. Projects/Vault-Setup/Tasks/Add my first project|Add my first project]] - ready to consider for your next action.

#### Decide
- [[Personal/2. Projects/Vault-Setup/Tasks/Set up my AGENTS|Set up my AGENTS]] - waiting on [[Set up my first goal]] — Best done after you have one real area + project in mind — gives the AI concrete answers to interview you about
- [[Personal/2. Projects/Vault-Setup/Tasks/Set up my first goal|Set up my first goal]] - waiting on [[Add my first project]] — Best done after you have one real project to anchor the goal to

#### Dispatch
- No unblocked `ai-handoff` task notes found.

### Threads To Keep Visible
- No recurring control threads found.

#### At Risk
- No source or meeting-capture exceptions found in this run.

---

## Tasks Overview

#### To Do

```base
filters:
  and:
    - type == "task"
    - status == "todo"
views:
  - type: table
    name: To Do
    order:
      - priority
      - area
      - project
      - file.name
      - due_date
    sort:
      - property: priority
        direction: ASC
      - property: area
        direction: ASC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.priority: 60
      note.area: 100
      note.project: 120
      file.name: 300
      note.due_date: 100
```

#### On Hold / Blocked

```base
filters:
  and:
    - type == "task"
    - status == "on-hold"
views:
  - type: table
    name: On Hold
    order:
      - priority
      - area
      - project
      - file.name
      - blocked_by
    sort:
      - property: priority
        direction: ASC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.priority: 60
      note.area: 100
      note.project: 120
      file.name: 300
      note.blocked_by: 200
```

#### Recently Completed

```base
filters:
  and:
    - type == "task"
    - status == "done"
views:
  - type: table
    name: Completed
    order:
      - done_date
      - area
      - project
      - file.name
    sort:
      - property: done_date
        direction: DESC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.done_date: 100
      note.area: 100
      note.project: 120
      file.name: 300
```

---

## Morning

%% Optional: write or dictate anything that would help you orient, decide, or reflect. The prepared brief above remains useful even when you add nothing here. %%

### AI Summary
*(filled by /process-morning when you add a morning entry)*
