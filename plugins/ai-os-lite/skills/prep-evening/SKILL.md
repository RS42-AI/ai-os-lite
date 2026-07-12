---
name: prep-evening
description: Evening prep that writes today's accomplishments, highlights, and a gentle wind-down prompt to the evening journal page. The evening mirror of /start-day. Designed to run as a cron job (~8pm) but can also be invoked manually. Use when the user says "prep evening", "evening prep", or "/prep-evening".
user-invocable: true
allowed-tools:
  # Obsidian CLI (file read/write)
  - Bash(obsidian read:*)
  - Bash(obsidian search:*)
  - Bash(obsidian append:*)
  - Bash(obsidian create:*)
  - Bash(obsidian files:*)
  - Bash(obsidian property:read:*)
  - Bash(obsidian property:set:*)
  # Obsidian MCP (patch for section replacement)
  - mcp__obsidian-mcp-tools__patch_vault_file
  # Todoist CLI (completed tasks, remaining tasks)
  - Bash(td task:*)
  # Google Workspace CLI (calendar review)
  - Bash(gws calendar:*)
  # QMD Search (for devlog lookup)
  - mcp__qmd__search
  - mcp__qmd__vector_search
  # Linear MCP (task cross-reference for RS42 devlogs)
  - mcp__linear__list_issues
---

# Prep Evening

Prep tonight's evening journal page with today's accomplishments, highlights, and a gentle wind-down prompt. This is Phase A of the evening loop: **AI preps the reflection before you journal.**

## Why This Exists

The end of the day leads to a great start the next day. Without a structured wind-down, the evening drifts → time gets lost → next morning starts behind. `/prep-evening` provides the transition point: review what you accomplished, reflect, check habits, and set up tomorrow.

## Key Principles

1. **Write to the evening journal page.** The context goes to `5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md`.
2. **Create the file if it doesn't exist.** Unlike `/start-day` (which requires a daily hub), this skill creates the evening entry on demand.
3. **Tone is warm and encouraging.** This is a wind-down, not a performance review. Highlight what went well. Gently note what could improve.
4. **Keep it brief.** Short bullets. You'll glance at this before reflecting.
5. **Don't overlap with /process-evening.** This skill preps context; `/process-evening` processes the user's voice/written reflection, triages Still Open tasks, and suggests new tasks.
6. **Still Open lives at the bottom.** The Still Open section is placed after the Reflection section — it's the interactive part that `/process-evening` will update after processing the user's reflection.
7. **No silent failures.** Track every external source call. Report what succeeded, what failed, and what was skipped. See `vault-config/references/source-manifest.md`.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. This skill uses:

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read/write evening entry, devlogs, daily hub | REQUIRED |
| Obsidian MCP | Patch sections into evening entry | REQUIRED |
| QMD Search | Devlog lookup (backup to glob) | MEDIUM |
| Todoist CLI | Completed tasks, remaining tasks | HIGH |
| GWS Calendar | Tomorrow preview | MEDIUM |
| Linear MCP | Cross-reference devlogs against RS42 issues | LOW |
| Task Notes | Task note frontmatter (all projects) | MEDIUM |

## Invocation

```
/prep-evening              → prep tonight's entry
/prep-evening 2026-03-14   → prep a specific date
```

**Cron setup** (future): Schedule to run daily at ~8:00 PM local time.

## Workflow

## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.

### Step 1: Determine Target Date

- Default: today's date
- If argument provided: parse as `YYYY-MM-DD`

### Step 2: Create or Open Evening Entry

Check if the evening journal entry exists:

```bash
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md"
```

**If it doesn't exist**: Create it with the evening template content (resolved, not Templater syntax):

```bash
obsidian create path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md" content="---\ndate: YYYY-MM-DD\ntype: journal\njournal_type: evening\ntags:\n  - journal\nhabit_journaled: false\ntodoist_tasks_created: false\n---\n\n## Evening Habits\n- [ ] Journaled\n\n### Today's Accomplishments\n\n### Tomorrow Preview\n\n### Wind Down\n\n---\n## Evening\n\n\n## Reflection\n\n**What went well today:**\n\n\n**What could I improve:**\n\n\n**Grateful for:**\n1.\n2.\n3.\n\n---\n\n###### Still Open\n"
```

**If it already exists**: Check for existing `### Today's Accomplishments` section. If present, replace individual sections (idempotent re-run).

### Step 3: Gather Today's Context

Collect four categories of context:

#### 3a: Today's Accomplishments (Devlogs)

Find devlogs created today using a two-pronged approach (body search misses frontmatter dates):

**Primary — glob by filename** (devlogs always have the date in the filename):

```bash
obsidian files pattern="*/Dev Log/YYYY-MM-DD*"
```

**Backup — QMD keyword search** (catches any devlogs the glob misses):

```python
mcp__qmd__search(query="YYYY-MM-DD", collection="vault")
```

Filter QMD results to only files under `*/Dev Log/` paths with today's date.

Also check today's daily hub for devlog references. For each devlog found, extract:
- Project name
- Session topic
- `tasks:` property (list of linked task IDs — Linear RS4-, Todoist task name)
- 1-line summary of what was accomplished

#### 3a-cross: Cross-Reference Devlogs Against Active Tasks

For each devlog, determine its task linkage:

1. **If `tasks:` property exists and is non-empty** → use those references directly
2. **If `tasks:` property is empty or missing** → search for a matching active task:
   - Search Todoist: `td task list --filter "search:{session_topic_keywords}" --json`
   - If area=rs42: `mcp__linear__list_issues` for matching issues
3. **If match found** → note the task reference for the accomplishment line
4. **If no match found** → flag as unlinked work

#### 3b: Completed Todoist Tasks

```bash
td task list --filter "completed today" --json --full
```

If no completed tasks API exists, check today's morning journal for the work priorities that were set and note them.

Group completed tasks by project. For each, note the task content and project.

#### 3c: Remaining / Carry-Forward Tasks

```bash
td task list --filter "overdue | today" --json --full
```

These are tasks that were planned for today but not yet completed. Present them as "still open" — not as failures, but as items to either complete tonight, reschedule, or acknowledge.

#### 3c-task: Task Notes with Active or Todo Status

Read task notes with `status: active` or `status: todo` across all projects:

```bash
for dir in ~/Claude/ObsidianVault/"2. Projects"/*/*/Tasks/; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"*.md; do
    [[ -f "$f" ]] || continue
    status=$(awk '/^---$/{if(f){exit}f=1;next}f' "$f" | grep '^status:' | sed 's/^status: *//')
    if [[ "$status" == "active" || "$status" == "todo" ]]; then
      echo "=== $(basename "$f" .md) ==="
      head -20 "$f"
    fi
  done
done
```

Also check `6. Main Notes/` for area-level task notes:
```bash
grep -rl "^type: task" ~/Claude/ObsidianVault/"6. Main Notes/"*.md 2>/dev/null
```

Merge task notes with Todoist remaining tasks (dedup by `external_id` match). For task notes that don't have a Todoist mirror, include them in Still Open with a `*(task note, pN)*` tag.

#### 3c-cross: Annotate Still Open with Devlog Progress

Cross-reference each remaining Todoist task against today's devlogs (from Step 3a):

1. For each Still Open task, check if any devlog's `tasks:` property references it (by Todoist task name or Linear ID)
2. Also fuzzy-match the task content against devlog `session_topic` and project names
3. If devlog matches found:
   - Count the number of matching sessions
   - Add a progress annotation: `*(p3, N sessions today — brief summary of what was done)*`
   - This helps the user decide during evening triage whether to CLOSE, KEEP, or note progress
4. If no devlog matches: standard format `*(pN)*` with optional encouraging note

**Example**:
```markdown
###### Still Open
- [ ] [[{WorkArea}]] / [[{Project}]] — Design carry-forward task lifecycle *(p3, 4 sessions today — task triage, evening flow, format unification)*
- [ ] [[{WorkArea}]] / [[{Project}]] — Brainstorm leveraging {Project} for work productivity *(p3, related: daily loop end-to-end redesign)*
- [ ] [[Personal]] — Research Bali trip *(p3)* → no rush
```

#### 3d: Tomorrow's Calendar (Preview)

```bash
gws calendar events list --params '{"calendarId":"primary","timeMin":"YYYY-MM-DD+1T00:00:00-06:00","timeMax":"YYYY-MM-DD+1T23:59:59-06:00","singleEvents":true,"orderBy":"startTime"}'
```

Quick preview of tomorrow so the user can mentally prepare. If empty, note "No meetings tomorrow."

### Step 4: Write Context to Evening Journal

Write context to three separate sections in the evening entry. No `## Context` wrapper — sections sit directly between `## Evening Habits` and the `---` before `## Evening`.

#### 4a: Write Accomplishments

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Today's Accomplishments",
    content="""{devlog_bullets}
{completed_tasks_bullets}
"""
)
```

#### 4b: Write Tomorrow Preview

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Tomorrow Preview",
    content="""{calendar_bullets_or_clear}
"""
)
```

#### 4c: Write Wind Down

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Wind Down",
    content="""[Warm, personalized 1-2 sentences based on today's accomplishments. Reference specific wins. End with "Check your evening habits, reflect on what went well, and rest. Tomorrow is prepped."]
"""
)
```

#### 4d: Write Still Open (at bottom)

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Still Open",
    content="""{remaining_tasks_or_all_clear}
"""
)
```

Still Open is at the bottom of the entry (after `## Reflection`, below the `---` separator). This is intentional — it's the interactive section that `/process-evening` will update after triaging tasks against the user's reflection.

#### Format Rules

> [!warning] Accomplishments Format — MUST use unified quick-link checkbox format
> **DO THIS**: `- [x] [[{WorkArea}]] / [[{Project}]] — Fixed storage key auth bug, restored data pipelines`
> **NEVER THIS**: `- **{Project} ({WorkArea})** — Fixed storage key auth bug` ← missing wikilinks, not checkable

**Accomplishments** — devlogs + completed tasks combined. Use checked checkboxes (`- [x]`) with area/project wikilinks and task references — same format as the daily hub's Yesterday's Summary and the morning entry's Yesterday section:
```markdown
### Today's Accomplishments
- [x] [[{WorkArea}]] / [[{Project}]] — Wired trigger to server.py *(Linear {TICKET}, in progress)*
- [x] [[{WorkArea}]] / [[{Project2}]] — Debugged agent feedback *(Linear {TICKET}, in progress)*
- [x] [[{WorkArea}]] / [[{Project}]] — Built /process-evening skill *(Todoist: Design carry-forward lifecycle)*
- [x] [[{WorkArea}]] / [[{Project}]] — Redesigned daily hub template *(no task linked)*
- [x] [[{WorkArea}]] — Email {Contact} about key vault *(Todoist)*
```

Rules:
- Every line starts with `- [x]` (these are accomplished items)
- Area wikilink first: `[[{WorkArea}]]`, `[[{SideArea2}]]`, `[[Personal]]`, etc.
- Project wikilink second (if applicable): `/ [[{Project}]]`, `/ [[{Project}]]`
- Short description after ` — `
- **Task reference in parenthetical** — from devlog `tasks:` property or cross-reference search:
  - {SideArea2} devlogs: `*(Linear RS4-42, state)*`
  - Personal devlogs: `*(Todoist: task name)*`
  - **Unlinked work**: `*(no task linked)*` — flags dev sessions with no corresponding task
- Todoist-completed tasks (not from devlogs) add `*(Todoist)*` source tag

> [!warning] Still Open Format — MUST use checkbox format with quick-link wikilinks
> **DO THIS**: `- [ ] [[{WorkArea}]] / [[{Project}]] — Follow up on {Project2} stakeholder meeting *(p2)*`
> **NEVER THIS**: `**[{WorkArea}/p2]** Follow up on {Project2} stakeholder meeting` ← renders as broken purple links in Obsidian

**Still Open** — remaining Todoist tasks with devlog progress annotations. Uses the unified quick-link checkbox format. Lives at the bottom of the entry (after Reflection, below `---`). This section is a **living section** — `/process-evening` will update it after triaging tasks against the user's reflection:
```markdown
###### Still Open
- [ ] [[{WorkArea}]] / [[{Project}]] — Design carry-forward task lifecycle *(p3, 4 sessions today — task triage, evening flow, format unification)*
- [ ] [[{WorkArea}]] / [[{Project}]] — Brainstorm leveraging {Project} for work productivity *(p3, related: daily loop redesign)*
- [ ] [[Personal]] — Research Bali trip *(p3)* → no rush
- *All tasks completed today!* ← if empty
```

**Task note formats for Still Open:**
- [ ] [[{WorkArea}]] / [[{Project}]] — E2E test start-day *(task note: todo, p3)*
- [ ] [[Finances]] — File LLC annual report *(task note: active, p1, due Apr 1)*
- [ ] [[{WorkArea}]] / [[{Project}]] — Fix storage key *(Todoist + task note: active, Linear {TICKET})*
- [ ] [[Personal]] — Buy groceries *(Todoist, p4)* ← no task note, one-off

Rules:
- Every line starts with `- [ ]` (these are open items)
- Area wikilink first, project wikilink second (if applicable)
- Short description after ` — `
- Priority in parenthetical: `*(pN)*`
- **If devlogs reference this task**: add session count and brief summary: `*(p3, N sessions today — what was done)*`
- **If devlogs are related but not directly linked**: `*(p3, related: brief context)*`
- **If no devlog activity**: standard format with optional encouraging note after ` → `
- If a Todoist task has a corresponding task note, show both sources: `*(Todoist + task note: status, pN)*`
- Task-note-only items (no Todoist mirror): `*(task note: status, pN)*`
- Include `due_date` in parenthetical if set: `*(task note: active, p1, due Apr 1)*`

**Tomorrow Preview**:
```markdown
### Tomorrow Preview
- 10:00–10:30 — Manager 1:1
- *No meetings tomorrow* ← if empty
```

**Wind Down** — always present, warm tone:
```markdown
### Wind Down
Time to step back. You got things done today. Check your evening habits, reflect on what went well, and rest. Tomorrow is prepped.
```

### Step 4e: Cross-Off Completed Priorities on Daily Hub

Read today's daily hub at `1. Daily/YYYY-MM-DD.md` and find the **Today's priorities** section. Cross-reference each priority against today's devlogs:

1. Read the daily hub and parse the "Today's priorities" section
2. For each unchecked priority (`- [ ]`):
   - Match against today's devlogs by project name, task ID, or description keywords
   - If a devlog session clearly addresses the priority → check it off: `- [x]`
3. Write the updated priorities back to the daily hub

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="1. Daily/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Morning Journal",
    content="""> [[5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD|Open Morning Entry]]


**Today's priorities:**
- [ ] [[{WorkArea}]] / [[{Project3}]] — Build the integration connector (Linear {TICKET})
- [ ] [[{WorkArea}]] / [[{Project3}]] — Prepare server access (Linear {TICKET})
- [x] [[{WorkArea}]] / [[{Project}]] — Figure out carry-forward task lifecycle
"""
)
```

**Rules:**
- Only check off priorities where a devlog clearly corresponds to the work described
- Don't check off a priority just because a devlog is in the same project — the session topic must match the priority's intent
- If a priority was partially addressed, add an annotation: `- [ ] ... *(in progress — N sessions today)*`
- Leave unrelated priorities unchanged

### Step 5: Report Results

Display a brief summary followed by the execution report (per `vault-config/references/source-manifest.md`):

```markdown
Evening prep complete for YYYY-MM-DD.

**Accomplishments**: N devlog sessions, M tasks completed
**Still open**: N tasks remaining
**Tomorrow**: N meetings scheduled

Evening journal prepped: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD]]
Time to wind down.

---
### Execution Report
#### Sources
- [x] Obsidian CLI — evening entry created, N devlogs found, daily hub updated
- [x] QMD Search — backup devlog search, N results
- [x] Todoist completed — N items
- [x] Todoist remaining — N items
- [ ] GWS Calendar — FAILED: auth token expired
- [x] Linear cross-ref — N devlogs matched

#### Warnings
- GWS integration unavailable — tomorrow preview shows "Calendar unavailable". Run `gws auth login` to refresh.
- N devlogs found with no task linked.

#### Fix
- GWS: Run `gws auth login` to refresh OAuth token
```

Only include the Warnings and Fix sections if there are actual warnings.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No devlogs today | Write "No dev sessions today" |
| No completed Todoist tasks | Write "No tasks completed in Todoist" (doesn't mean nothing was done — devlogs may show work) |
| No remaining tasks | Write "All tasks completed today!" |
| Calendar API fails | Write "Calendar unavailable", record `FAILED` in execution report, continue |
| Evening entry already has sections | Replace individual heading content (idempotent) |
| Run before 5pm | Still works, but context will be incomplete (may add more devlogs later) |
| Weekend / no work | Still runs — personal accomplishments and habits still matter |

## What This Skill Does NOT Do

- Does not process the evening voice transcript (that's `/process-evening`)
- Does not create Todoist tasks (that's `/process-evening` or manual)
- Does not update the daily hub
- Does not read habit checkboxes (that's `/process-evening`)
- Does not track streaks (that's `/weekly-review`, future)
