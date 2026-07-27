# AGENTS.md (write-note lint fixture)

## Areas

| Area folder | `area` slug |
|-------------|-------------|
| `3. Areas/1. Work/` | `work` |
| `Personal/` | `personal` |

### `type` values — CLOSED LIST

| Value | Description | Where it lives |
|-------|------------|----------------|
| `note` | General knowledge | `6. Main Notes/` or `{Project}/Notes/` |
| `resource` | Curated reference material | `5. Resources/{Area}/` |
| `task` | Actionable work item | `*/Tasks/` |
| `person` | Contact note | `4. Contacts/People/` |
| `devlog` | Session work log | `{Project}/Dev Log/` |

### `status` values — CLOSED LIST (per type)

| `type` | allowed `status` (progression →) | pause / terminal |
|--------|-----------------------------------|------------------|
| `task` | `todo` → `active` → `done` | `on-hold`, `archived` |
| `note` | `capture` → `done` | `superseded` |
| `devlog` | `capture` | — |
| `daily`, `journal`, `person`, `resource` | *(no `status` field)* | — |

### Relationship verbs — CLOSED LIST (the ontology T-box)

| Verb | Meaning (A —verb→ B) | Written as |
|---|---|---|
| `blocks` / `unlocks` | B waits on A / completing A enables B | `blocked_by:` (on the blocked note) / `unlocks:` |
| `serves_goal` | work advances goal G | `goal:` / `quarter_goal:` (plus `kr` — a plain label, not a link field) |
| `part_of` | containment | `project:` / `area:` (+ folder placement) — **never a separate field** |
| `uses_system` | process/project runs on this tool/system | `uses_system:` |
| `informs` | knowledge input to a decision | `informs:` |
| `owned_by` | accountability rests with this person | `owned_by:` |
