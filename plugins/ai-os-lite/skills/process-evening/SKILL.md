---
name: process-evening
description: Process optional free-form Evening Entry input — write a private AI Summary, triage tasks with approval, and surface only patterns supported by the user's words or user-defined frontmatter. Reflection, gratitude, and lifestyle habits are never required. The evening mirror of /process-morning. Use when the user says "process evening", "process my evening", or "/process-evening".
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
  # Obsidian MCP (patch for section replacement + task note updates + creation)
  - mcp__obsidian-mcp-tools__patch_vault_file
  - mcp__obsidian-mcp-tools__create_vault_file
  # QMD Search (for pattern detection, people lookup)
  - mcp__qmd__search
  - mcp__qmd__vector_search
  # Todoist CLI (task creation for tomorrow)
  - Bash(td task:*)
  - Bash(td comment:*)
---

# Process Evening

Process tonight's optional Evening Entry — preserve the raw words, extract useful structure, triage tasks with approval, and prepare tomorrow without imposing a reflection framework.

## Why This Exists

When the user chooses to add evening context, `/process-evening` can turn it into a concise private summary, task decisions, and evidence-supported patterns. The scheduled `/prep-evening` output remains useful even when the user adds nothing and never invokes this skill.

## Key Principles

1. **The raw content stays untouched.** `## Evening` is never modified; a legacy `## Reflection` section may be read as fallback but never written.
2. **Supported, not prescribed.** Surface patterns only when the entry or user-defined frontmatter supports them. Never require what-went-well, improvement, or gratitude content.
3. **Tomorrow's tasks default to tomorrow.** Unlike `/process-morning` (due today), evening tasks are due tomorrow.
4. **Habits are frontmatter-only.** Stamp `habit_evening_reflection: true` after processing non-empty human input. Do not infer, create, or update any other habit.
5. **Batch approval for tasks.** Never create Todoist tasks without explicit user confirmation.
6. **No silent failures.** Track every external source call. Report what succeeded, what failed, and what was skipped. See `vault-config/references/source-manifest.md`.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. This skill uses:

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read evening entry, write AI Summary | REQUIRED |
| Obsidian MCP | Patch sections, update frontmatter | REQUIRED |
| QMD Search | Pattern detection (decision loops), people lookup | MEDIUM |
| Todoist CLI | Task triage (close, defer, create) | HIGH |

## Invocation

```
/process-evening              → process tonight's entry
/process-evening 2026-03-15   → process a specific date
```

## Workflow

## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.

### Step 1: Determine Target Date

- Default: today's date
- If argument provided: parse as `YYYY-MM-DD`

### Step 2: Read Evening Entry

```bash
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md"
```

**If it doesn't exist**: Report "No evening entry found for YYYY-MM-DD. Run `/prep-evening` first or create one manually." and stop.

### Step 3: Read Frontmatter and Stamp Completion

Read every `habit_*` property already present in frontmatter. Do not parse body checkboxes and do not assume a lifestyle habit set.

Determine whether `## Evening` contains non-empty human prose, ignoring the optional comment and nested `### AI Summary` placeholder. If it is empty, leave `habit_evening_reflection: false` and stop with "No evening content to process." Defer the system-field write until Step 8 succeeds:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="frontmatter",
    target="habit_evening_reflection",
    content="true"
)
```

All other `habit_*` fields remain untouched. Do not create a gratitude or journaling habit on the user's behalf.

### Step 4: Check Idempotency

Look for an existing nested `### AI Summary` subsection in the evening entry.

- If it is missing, empty, or contains only the `*(filled by /process-evening...)*` placeholder: **first run** — proceed normally and create/replace it once under `## Evening`
- If it contains a substantive prior summary: **re-run** — warn the user

```
This evening entry has already been processed. The entry has an existing AI Summary:
> "[first ~80 chars of existing summary]..."

Would you like to re-process? Summary and mood will be refreshed.
```

Wait for confirmation before continuing. If user declines, stop.

#### Todoist Task Guard

Also check frontmatter for `todoist_tasks_created`:

- If `todoist_tasks_created: true`: **Step 6 will be skipped** unless user explicitly requests task re-creation
- If `todoist_tasks_created: false` or not present: Step 6 runs normally

### Step 5: Extract Insights from Evening Content

Read the free-form content under `## Evening`. If an older entry also has `## Reflection`, read it as a legacy fallback only; never create or modify that section. Extract only what the prose supports:

#### AI Summary (2-3 sentences)
Concise summary of the person's entry. Warm, observational tone. Cover what happened, their state when stated, and anything they want to preserve.

#### Mood (single word or short phrase)
End-of-day emotional state. Examples: "calm, satisfied", "tired but proud", "restless", "grateful".

#### What Went Well (optional)
Include only when the prose supports it. Preserve the user's words and lightly edit for clarity.

#### What Could Improve (optional)
Include only when the user raises an improvement or friction. Frame constructively and keep their voice.

#### Gratitude (optional)

Include gratitude only when the person explicitly states it. Never infer it, require a count, or prompt for it. If absent, omit the field silently.

#### Tomorrow Intentions
Only if explicitly stated in the evening content ("tomorrow I want to...", "planning to..."). If not mentioned: "No specific plans mentioned."

#### People Mentioned
Identify people mentioned by name. Look up in vault contacts for wikilinks:

```python
mcp__qmd__search(query="PersonName", collection="vault")
```

If found: `[[Full Name]]`. If not found: plain text.

### Step 6: Task Triage — Review Still Open + Propose New Tasks

This is the interactive step. Two inputs feed into one unified batch approval:

1. **Still Open tasks** from `/prep-evening` (at the bottom of the entry) — cross-referenced against optional evening input
2. **New actionable items** from the evening content — same as before

#### Finding Matching Task Notes

For each Still Open item, check if a corresponding task note exists:

1. If the item has an `external_id` reference (Linear RS4-, Todoist:), search:
   ```bash
   grep -rl "{external_id}" ~/Claude/ObsidianVault/"2. Projects"/*/*/Tasks/*.md ~/Claude/ObsidianVault/"6. Main Notes/"*.md 2>/dev/null
   ```

2. If no external_id, fuzzy match by task name against existing task note filenames:
   ```bash
   find ~/Claude/ObsidianVault/"2. Projects"/*/*/Tasks/ -name "*.md" 2>/dev/null | grep -i "{keywords}"
   ```

3. Store the task note path (if found) for use in CLOSE/DEFER/CREATE operations below.

#### 6a: Read Still Open Section

Read the `###### Still Open` section from the bottom of the evening entry. Parse each checkbox item into a task with its area, project, description, and priority.

#### 6b: Cross-Reference Still Open Against Evening Input

For each Still Open task, scan `## Evening` and any read-only legacy `## Reflection` content for mentions or relevant context:

| If the user says... | Triage action |
|---------------------|---------------|
| "I did X" / "knocked out X" / "finished X" | **CLOSE** — task was completed |
| "don't need X anymore" / "X is enough" / "not doing X" | **CLOSE** — task is no longer relevant |
| "deferring X until Y" / "depends on Z decision" / "waiting on..." | **DEFER** — remove due date, add context |
| "still need to X" / "tomorrow I'll X" | **KEEP** — no change, or update due date to tomorrow |
| No mention of the task | **KEEP** — no change |

#### 6c: Detect New Actionable Items from Evening Input

Scan the evening content for new actionable items not already in Still Open or Todoist:

| If the user mentions... | Classification |
|------------------------|----------------|
| Specific next action ("need to email X", "should research Y") | **CREATE** → due tomorrow |
| Multi-day effort ("want to start exploring Z") | **INITIATIVE** → @initiative, no due date |
| Vague reflection ("need to be better about...") | **SKIP** → stays in the entry |

#### 6d: Dedup Against Existing Todoist Tasks

```bash
td task list --filter "search:{keyword}" --json
```

If a matching task exists, add a mention comment instead of duplicating.

#### 6e: Present Unified Batch for Approval

Present all triage actions and new task proposals in one prompt:

```
Task triage from YYYY-MM-DD evening:

CLOSE (N — done or no longer needed):
├─ ✓ [[Health & Fitness|Health]] — Get a gym membership — you said "calisthenics is enough"
└─ ✓ [[{WorkArea}]] — Review tasks for Monday — you knocked out {Project} + {Project3} today

DEFER (N — waiting on a decision):
└─ ⏸ [[Personal]] — Go look at a car — depends on Bali decision, removing due date

CREATE (N new — due tomorrow):
└─ + [[Personal]] — Research Bali trip: flights, dates, costs, PTO → p3

INITIATIVE (N new):
└─ + [[{SideArea2}]] — Explore {Project} for work productivity → @initiative

KEEP (N — unchanged):
└─ → [[{WorkArea}]] / [[{Project}]] — Wire Linear → Todoist sync

SKIP (N — not actionable):
└─ "I wish I could meet more people" — optional reflection, stays in the entry

Apply these? [Y/n/edit]
```

**Wait for user confirmation before executing any actions.**

#### 6f: Execute Triage on Approval

```bash
# CLOSE — complete Todoist AND update task note
td task complete <task_id>
```

# If a matching task note exists (from Finding Matching Task Notes above):
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="status",
    content="done"
)
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="{task_note_path}",
    operation="replace",
    targetType="frontmatter",
    target="done_date",
    content="{today}"
)

```bash
# DEFER — remove Todoist due date AND set task note on-hold
td task update <task_id> --due ""
```

# If a matching task note exists:
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
    content="{reason from triage}"
)

```bash
# CREATE — new task (due tomorrow)
td task add "Task description" \
  --project "ProjectName" \
  --labels "label1,label2" \
  --priority p3 \
  --due "tomorrow"
```

# If task warrants a note (has due date, multi-session, p1/p2):
mcp__obsidian-mcp-tools__create_vault_file(
    filename="2. Projects/{Area}/{Project}/Tasks/{Task Name}.md",
    # OR "6. Main Notes/{Task Name}.md" for area-level tasks
    content="""---
date: {today}
type: task
status: todo
area: {area}
project: {slug}
priority: {p_level}
due_date: "{due_date}"
scheduled_date: ""
done_date: ""
blocked_by: ""
external_id: "Todoist: {task_name}"
tags:
  - task
---

# {Task Name}

> **Project**: [[{Project Hub}]]

{Context from evening input}

## Dev Log

\`\`\`base
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
\`\`\`
"""
)

```bash

# INITIATIVE — new initiative (no due date)
td task add "Initiative description" \
  --project "ProjectName" \
  --labels "@initiative"

# KEEP — no Todoist action needed
# SKIP — no action
```

#### 6g: Update Still Open Section

After triage, update the `###### Still Open` section in the evening entry to reflect results:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Still Open",
    content="""{updated_still_open_items}
"""
)
```

Updated format:
- **CLOSE** items → `- [x] [[Area]] / [[Project]] — description *(closed — reason)*`
- **DEFER** items → `- [ ] [[Area]] / [[Project]] — description *(deferred — reason)*`
- **KEEP** items → `- [ ] [[Area]] / [[Project]] — description *(p2)*` (unchanged)
- **CREATE** items → added as new `- [ ]` lines (these are now in Todoist for tomorrow)

#### 6h: Set Todoist Guard Flag

After task batch is presented (regardless of whether user creates or skips):

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="frontmatter",
    target="todoist_tasks_created",
    content="true"
)
```

### Step 7: Proactive Pattern Detection

After extraction, scan for patterns. This is what makes it **proactive, not passive**.

#### 7a: Optional Frontmatter Signal Awareness

Read recent `habit_*` frontmatter only when the current entry actually contains user-defined habit fields or when the user asks for trend analysis:

```bash
# Check recent evening entries
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD-1.md"
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD-2.md"
# ... up to 7 days back
```

The system fields `habit_morning_brief` and `habit_evening_reflection` may be reported as workflow-completion signals. Any other habit is user-defined and may be summarized only because it already exists.

Do not nudge about false or missing lifestyle habits. Do not infer completion from prose. If no user-defined fields exist, skip lifestyle-habit analysis entirely.

#### 7b: Decision-Loop Detection

If the evening content contains language like "still figuring out", "need to decide", "keep going back and forth" about a topic, search for that topic in recent entries:

```python
mcp__qmd__vector_search(query="<decision topic>", collection="vault")
```

If the same topic appears in 3+ recent entries, flag it:
- "You've mentioned [topic] in N of the last M entries. Consider scheduling a focused decision session."

#### 7c: Explicit Pattern Awareness

If the user explicitly asks about a self-chosen habit or mentions a repeated pattern, respond with **data, not judgment**:

- "Day 0 reset on [habit]. Previous streak: N days."
- If enough data: "Pattern: slips tend to follow [social events / stressful work days / evenings without plans]."

Never use language like "failed", "fell off", "broke". Use "reset", "new start", "day 0".

#### 7d: Tomorrow Readiness

Based on the morning calendar data (if available from today's `/start-day` context) + remaining tasks + user's stated intentions:

- "Tomorrow: N meetings, M tasks carry forward, you mentioned wanting to focus on [X]. Looks manageable."
- Or: "Tomorrow is packed — N meetings + M overdue tasks. Consider what you can defer."

### Step 8: Write AI Summary to Evening Entry

Replace the nested `### AI Summary` subsection under `## Evening`. If an older entry lacks it, append `### AI Summary` under `## Evening` once and use replace on future runs.

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="AI Summary",
    content="""
**Summary**: [2-3 sentences]
**Mood**: [mood]

**What went well**: [only when supported]
**What could improve**: [only when supported]

**Grateful for**: [only when explicitly present; otherwise omit]

**People mentioned**: [[Person]]

**Patterns detected**:
- [pattern flags from Step 7 — decision loops, streak data, habit-slip awareness, tomorrow readiness]

"""
)
```

Omit optional fields the entry does not support. Re-processing uses the same replace operation. First-run fallback appends content beginning with `### AI Summary` to the `Evening` H2 without replacing raw prose.

After the AI Summary write succeeds, set `habit_evening_reflection: true` using the frontmatter patch shown in Step 3. Never change other `habit_*` fields.

### Step 9: Add Chain Link to Evening Entry

Add a forward link to tomorrow's Morning Brief before the `###### Still Open` heading:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="prepend",
    targetType="heading",
    target="Still Open",
    content="""---
> **Next Morning Brief**: [[5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD+1|Tomorrow's Morning Brief]]

"""
)
```

Where `YYYY-MM-DD+1` is tomorrow's date. Only add if not already present (check first).

#### Final Evening Entry Structure

After both `/prep-evening` and `/process-evening` run, the entry looks like:

```
(frontmatter, including habit_evening_reflection)
### Today's Accomplishments           ← /prep-evening
### Tomorrow Preview                  ← /prep-evening
### Wind Down                         ← /prep-evening
---
## Evening                            ← user fills (voice/typed)
### AI Summary                        ← /process-evening
---
> Next Morning Brief link             ← /process-evening
###### Still Open                     ← /prep-evening creates, /process-evening updates
```

### Step 10: Report Results

Display a summary followed by the execution report (per `vault-config/references/source-manifest.md`):

```markdown
Evening processed for YYYY-MM-DD.

**Summary**: [2-3 sentences]
**Mood**: [mood]
**Habits**: Evening Entry processed; list other user-defined fields only when present
**Task triage**: N closed, N deferred, N kept | N new tasks created for tomorrow
**Patterns**: [any flags from Step 7]

Evening entry updated: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD]]

---
### Execution Report
#### Sources
- [x] Obsidian CLI — Evening Entry read; historical entries read only when relevant
- [x] Obsidian MCP — frontmatter updated, AI Summary written, Still Open updated
- [x] QMD Search — pattern detection, N entries scanned
- [x] Todoist — N tasks triaged (M closed, K deferred, J created)

#### Warnings
- [only if there are actual warnings]

#### Fix
- [only if there are failed sources with actionable fixes]
```

Only include Warnings and Fix sections if there are actual issues.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No evening entry for date | Report and stop — suggest running `/prep-evening` first |
| Already processed (AI Summary exists) | Warn and ask. On confirm: replace summary/mood, merge content |
| Evening section is empty | Report "No evening content to process" and stop |
| Legacy `## Reflection` section | Read as fallback only; never write it |
| No explicit gratitude | Omit gratitude silently — never fabricate or prompt |
| No actionable items and no Still Open | Skip triage — "No task changes" |
| Still Open section empty or missing | Skip triage of existing tasks, still propose new ones from reflection |
| Recent entries unavailable for requested trend | Report only what available frontmatter supports and note gaps |
| User asks about a self-chosen habit | Data only, no judgment; never infer completion |
| Re-run with tasks already created | Skip Step 6 unless user requests re-creation |

## What This Skill Does NOT Do

- Does not modify raw content (`## Evening`; legacy `## Reflection` also stays untouched)
- Does not create tasks without approval (batch approval pattern)
- Does not process the Morning Brief (that's `/process-morning`)
- Does not show personal content on the daily hub
- Does not create lifestyle habits or expose them in the note body
- Does not prep the evening page (that's `/prep-evening`)
- Does not create the evening entry if missing (that's `/prep-evening`)
