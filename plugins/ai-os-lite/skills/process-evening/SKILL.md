---
name: process-evening
description: Process an evening journal entry — extract AI summary, mood, habits, gratitude, propose tomorrow's tasks, and detect patterns (streaks, decision loops, habit-slip awareness). The evening mirror of /process-journal. Use when the user says "process evening", "process tonight's journal", or "/process-evening".
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

Process tonight's evening journal entry — extract insights, track habits, propose tomorrow's tasks, and proactively surface patterns. This is Phase B of the evening loop: **AI processes your reflection and prepares you for tomorrow.**

## Why This Exists

The evening reflection is the richest signal for self-awareness: what went well, what didn't, how you feel, what you want tomorrow to look like. Without processing, these insights stay locked in prose. `/process-evening` extracts structure from reflection, tracks habits over time, and proactively surfaces patterns the user might not notice.

## Key Principles

1. **The raw content stays untouched.** `## Evening` and `## Reflection` sections are never modified.
2. **Proactive, not passive.** Don't just summarize — detect patterns, flag decision loops, track streaks, and nudge.
3. **Tomorrow's tasks default to tomorrow.** Unlike `/process-journal` (due today), evening tasks are due tomorrow.
4. **No shame, only data.** When habits slip, respond with facts and patterns, not judgment.
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

### Step 3: Parse Evening Habits

Read the `## Evening Habits` section from the evening entry and parse **every** checkbox present — do not assume a fixed set. The evening journal template owns the habit schema; users add their own habits as checkbox lines with matching `habit_*` frontmatter properties. Map each checkbox label to its property slug (lowercase, spaces → underscores, prefixed `habit_`):

```markdown
## Evening Habits
- [x] Journaled               → habit_journaled: true
- [ ] <Any user-added habit>  → habit_<any_user_added_habit>: false
```

**Update frontmatter** for each parsed habit (example shown for `habit_journaled`; repeat per habit found):

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="frontmatter",
    target="habit_journaled",
    content="true"
)
# Repeat for habit_journaled
```

### Step 4: Check Idempotency

Look for an existing `## AI Summary` section in the evening entry.

- If no `## AI Summary` section exists: **first run** — proceed normally
- If it already exists: **re-run** — warn the user

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

Read `## Evening` (voice transcript or typed) and `## Reflection` sections. Extract:

#### AI Summary (2-3 sentences)
Concise summary of the evening reflection. Warm, observational tone. What happened today, how they feel, what's on their mind.

#### Mood (single word or short phrase)
End-of-day emotional state. Examples: "calm, satisfied", "tired but proud", "restless", "grateful".

#### What Went Well
From `## Reflection` → "What went well today:" — preserve the user's words. Lightly edit for clarity only.

#### What Could Improve
From `## Reflection` → "What could I improve:" — frame constructively, not as failure. Keep the user's voice.

#### Gratitude (3 items — MUST be explicitly stated)

**CRITICAL**: Only include gratitude items that the person actually stated. Do NOT infer or generate gratitude from content. If not explicitly stated:

```markdown
**Grateful for**: ⚠️ No gratitude entry tonight. What are 3 things you're grateful for?
```

When gratitude IS explicitly stated:
```markdown
**Grateful for**:
1. [item]
2. [item]
3. [item]
```

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

1. **Still Open tasks** from `/prep-evening` (at the bottom of the entry) — cross-referenced against the evening reflection
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

#### 6b: Cross-Reference Still Open Against Reflection

For each Still Open task, scan the `## Evening` and `## Reflection` content for mentions or relevant context:

| If the user says... | Triage action |
|---------------------|---------------|
| "I did X" / "knocked out X" / "finished X" | **CLOSE** — task was completed |
| "don't need X anymore" / "X is enough" / "not doing X" | **CLOSE** — task is no longer relevant |
| "deferring X until Y" / "depends on Z decision" / "waiting on..." | **DEFER** — remove due date, add context |
| "still need to X" / "tomorrow I'll X" | **KEEP** — no change, or update due date to tomorrow |
| No mention of the task | **KEEP** — no change |

#### 6c: Detect New Actionable Items from Reflection

Scan the evening content for new actionable items not already in Still Open or Todoist:

| If the user mentions... | Classification |
|------------------------|----------------|
| Specific next action ("need to email X", "should research Y") | **CREATE** → due tomorrow |
| Multi-day effort ("want to start exploring Z") | **INITIATIVE** → @initiative, no due date |
| Vague reflection ("need to be better about...") | **SKIP** → stays in journal |

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
└─ "I wish I could meet more people" — evening reflection, stays in journal

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

{Context from evening reflection}

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

#### 7a: Habit Streak Awareness

Read the last 7 days of evening entries to check habit frontmatter:

```bash
# Check recent evening entries
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD-1.md"
obsidian read path="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD-2.md"
# ... up to 7 days back
```

Also check morning entries for the `habit_*` frontmatter fields — read whatever `habit_*` properties the morning entry carries; the schema is owned by the journal template (`system-settings/Templates/Journal Entry Template.md`), not this skill.

Report:
- **Current streaks**: "Meditation: 2 days, Workout: 4 days, Vitamins: 5 days"
- **Broken streaks**: "Workout streak ended today (was 5 days)"
- **Nudges for unchecked evening habits**: "<Habit> unchecked — still time tonight?" (use the user's actual habit labels from their entry)

#### 7b: Decision-Loop Detection

If the evening content contains language like "still figuring out", "need to decide", "keep going back and forth" about a topic, search for that topic in recent entries:

```python
mcp__qmd__vector_search(query="<decision topic>", collection="vault")
```

If the same topic appears in 3+ recent entries, flag it:
- "You've mentioned [topic] in N of the last M entries. Consider scheduling a focused decision session or checking your Life Strategy Matrix."

#### 7c: Habit Slip Awareness (Sensitive — No Shame)

If the user mentions slipping on a habit or breaking a streak in the evening content, respond with **data, not judgment**:

- "Day 0 reset on [habit]. Previous streak: N days."
- If enough data: "Pattern: slips tend to follow [social events / stressful work days / evenings without plans]."

Never use language like "failed", "fell off", "broke". Use "reset", "new start", "day 0".

#### 7d: Tomorrow Readiness

Based on the morning calendar data (if available from today's `/start-day` context) + remaining tasks + user's stated intentions:

- "Tomorrow: N meetings, M tasks carry forward, you mentioned wanting to focus on [X]. Looks manageable."
- Or: "Tomorrow is packed — N meetings + M overdue tasks. Consider what you can defer."

### Step 8: Write AI Summary to Evening Entry

Insert `## AI Summary` section **after** the `## Reflection` section (between user content and the `---` separator before Still Open). AI Summary is post-processing output — it belongs after the raw content, not before it.

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="append",
    targetType="heading",
    target="Reflection",
    content="""
## AI Summary
**Summary**: [2-3 sentences]
**Mood**: [mood]

**What went well**: [from reflection]
**What could improve**: [from reflection]

**Grateful for**:
1. [item]
2. [item]
3. [item]

**People mentioned**: [[Person]]

**Patterns detected**:
- [pattern flags from Step 7 — decision loops, streak data, habit-slip awareness, tomorrow readiness]

"""
)
```

**Re-processing (merge behavior)**: If re-processing, use `replace` on the existing `AI Summary` heading instead of `append`.

### Step 9: Add Chain Link to Evening Entry

Add a forward link to tomorrow's morning. This goes between the AI Summary and the `###### Still Open` section — prepend before the Still Open heading:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD.md",
    operation="prepend",
    targetType="heading",
    target="Still Open",
    content="""---
> **Next Morning**: [[5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD+1|Tomorrow's Morning]]

"""
)
```

Where `YYYY-MM-DD+1` is tomorrow's date. Only add if not already present (check first).

#### Final Evening Entry Structure

After both `/prep-evening` and `/process-evening` run, the entry looks like:

```
(frontmatter)
## Evening Habits                     ← template
### Today's Accomplishments           ← /prep-evening
### Tomorrow Preview                  ← /prep-evening
### Wind Down                         ← /prep-evening
---
## Evening                            ← user fills (voice/typed)
## Reflection                         ← user fills
## AI Summary                         ← /process-evening
---
> Next Morning link                   ← /process-evening
###### Still Open                     ← /prep-evening creates, /process-evening updates
```

### Step 10: Report Results

Display a summary followed by the execution report (per `vault-config/references/source-manifest.md`):

```markdown
Evening processed for YYYY-MM-DD.

**Summary**: [2-3 sentences]
**Mood**: [mood]
**Habits**: N/M evening habits | Streaks: [workout Xd, meditation Xd, ...]
**Task triage**: N closed, N deferred, N kept | N new tasks created for tomorrow
**Patterns**: [any flags from Step 7]

Evening entry updated: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD]]

---
### Execution Report
#### Sources
- [x] Obsidian CLI — evening entry read, N historical entries for streaks
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
| No reflection section | Extract from `## Evening` only, note that reflection wasn't completed |
| No explicit gratitude | Write "⚠️ No gratitude entry tonight" — never fabricate |
| No actionable items and no Still Open | Skip triage — "No task changes" |
| Still Open section empty or missing | Skip triage of existing tasks, still propose new ones from reflection |
| Recent entries unavailable for streak calc | Report streaks based on available data, note gaps |
| Habit slip detected | Data only, no judgment. Report streak reset and pattern if available |
| Re-run with tasks already created | Skip Step 6 unless user requests re-creation |

## What This Skill Does NOT Do

- Does not modify raw content (`## Evening`, `## Reflection` content stays untouched)
- Does not create tasks without approval (batch approval pattern)
- Does not process the morning journal (that's `/process-journal`)
- Does not show personal content on the daily hub
- Does not track streaks itself — reads historical frontmatter data to calculate
- Does not prep the evening page (that's `/prep-evening`)
- Does not create the evening entry if missing (that's `/prep-evening`)
