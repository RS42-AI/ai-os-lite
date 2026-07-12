---
name: process-journal
description: Process a morning journal entry — extract AI summary, mood, gratitude, people, and daily planning intent. Write private reflection to the journal and render the committed daily hub as Work Anchor, Control Queue, Today's Plan, and Routing Exceptions. Extracted actionable items can become task notes/Todoist mirrors with dedup and batch approval. Use when the user says "process journal", "process today's journal", or "/process-journal".
user-invocable: true
allowed-tools:
  # Obsidian CLI (file read/write via Bash)
  - Bash(obsidian read:*)
  - Bash(obsidian search:*)
  - Bash(obsidian append:*)
  - Bash(obsidian create:*)
  - Bash(obsidian files:*)
  - Bash(obsidian property:read:*)
  - Bash(obsidian property:set:*)
  # Obsidian MCP (patch for section replacement, file creation)
  - mcp__obsidian-mcp-tools__patch_vault_file
  - mcp__obsidian-mcp-tools__create_vault_file
  # QMD Search (for people lookup)
  - mcp__qmd__search
  - mcp__qmd__vector_search
  # Todoist CLI (task creation and dedup)
  - Bash(td task:*)
  - Bash(td comment:*)
  # Process-journal scripts (data collection + git commit)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/*.sh:*)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/match_task_note.sh:*)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/*.py:*)
  - Bash(chmod:*)
---

# Process Journal

Extract structured insights from a raw morning journal transcript. Write the full AI analysis to the **journal entry** (private) and a daily operating plan to the **daily hub** (visible).

## Key Principles

1. **The raw transcript stays untouched.** The voice transcript under `## Morning` and `## Evening` is never modified.
2. **Full insights go to the journal entry.** The `### AI Summary` section (with mood, all priorities, gratitude) replaces the placeholder at the bottom of the journal entry (nested under `## Morning`). This is the private reflection space.
3. **The daily hub gets the committed operating plan.** This is the ONLY place the Work Anchor, Control Queue, Today's Plan, and Routing Exceptions are written — not the morning entry. The old Must do / Focus work / If time render is deprecated for v3.
4. **No silent failures.** Track every external source call. Report what succeeded, what failed, and what was skipped. See `vault-config/references/source-manifest.md`.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. This skill uses:

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read journal transcript, write AI Summary | REQUIRED |
| Obsidian MCP | Patch sections, create task notes | REQUIRED |
| QMD Search | People lookup in vault contacts | LOW |
| Todoist CLI | Task creation, dedup check | HIGH |
| Vault git | Processing output commit (Step 8j) | MEDIUM |

## Invocation

```
/process-journal                       → process today's entry
/process-journal 2026-03-08            → process a specific date
/process-journal 2026-05-18 --dry-run  → render to stdout/tmpfile, do not write the vault
```

**Dry-run mode** (`--dry-run` flag):
- Step 6 (AI Summary) and Step 8 (daily hub render) write their would-be content to `/tmp/process-journal-dryrun-$today.md` instead of patching the vault.
- Step 7 (task notes / Todoist) is skipped entirely — no creates, no Todoist API calls.
- Step 4 (idempotency marker check) still runs, but a detected marker just emits a warning — no prompt to re-run.
- The bottom marker append (Step 7g) is skipped.

Pass `--dry-run` as the second argument after any date: `/process-journal 2026-05-18 --dry-run`.

## Workflow

## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.

### Step 1: Determine Target Date

- Default: today's date
- If argument provided: parse as `YYYY-MM-DD`
- Validate format

### Step 2: Read Source Files

**Use Obsidian CLI (NOT MCP) for reads:**

```bash
# Journal entry (raw transcript)
obsidian read path="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md"

# Daily note hub (target for Work Anchor / Control Queue / Today's Plan)
obsidian read path="1. Daily/YYYY-MM-DD.md"
```

**DO NOT use** `mcp__obsidian-mcp-tools__get_vault_file` — use `obsidian read` per the Tool Rules above.

**If journal entry doesn't exist**: Report "No journal entry found for YYYY-MM-DD" and stop.

**If daily note doesn't exist**: Report "No daily note found for YYYY-MM-DD. Create one first with Cmd+Shift+D in Obsidian." and stop.

### Step 3: Read Habit Data from Frontmatter

Read **all** `habit_*` properties present in the journal entry's frontmatter — do not assume a fixed set. The habit schema is owned by the journal template (`system-settings/Templates/Journal Entry Template.md`); this skill reads whatever `habit_*` fields the entry actually carries. They are the single source of truth — the user sets them via Obsidian's Properties panel.

Extract every `habit_*` line from the frontmatter block:

```bash
obsidian read path="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md" \
  | awk '/^---$/{c++; next} c==1 && /^habit_/'
```

This lists each `habit_*: value` pair the entry carries (e.g. the starter set `habit_journaled`, `habit_exercise` — but read what's there, don't hardcode; users define their own set in the journal template). If the user tracks a gratitude habit (`habit_gratitude`), it may be set to `true` during Step 6 when 3 gratitude items are extracted.

No parsing or syncing needed — frontmatter IS the data.

Store the values for use in the Step 9 report (habits summary).

### Step 4: Check Idempotency — Bottom Marker Line

Scan the journal entry body for a bottom marker line matching:
`*Processed YYYYMMDDHHMM · N tasks created in Todoist*`

**Search command:**
```bash
obsidian read path="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md" | grep -E '^\*Processed [0-9]{12}'
```

- **If no marker found**: this is a **first run** — proceed normally. Step 7 will append a marker at the end.
- **If a marker is found**: this is a **re-run**. Extract the timestamp and Todoist count from the marker. Warn the user:

  ```
  This journal was already processed on YYYY-MM-DD at HH:MM ({N} Todoist tasks created).
  Re-processing will refresh the AI Summary, mood, and grouped priorities.
  Task notes and Todoist tasks that were already created will be preserved (not duplicated).

  Would you like to re-process? [y/N]
  ```

  Wait for confirmation. If the user declines, stop with a short message.

**On re-run (user confirmed)**: extract the existing priorities from the current `### AI Summary` and the daily hub's `**Today's priorities:**` section before re-extracting in Step 5. These will be merged (dedup by description) in Step 8.

**Frontmatter flag**: the old `todoist_tasks_created` frontmatter flag is no longer used. If present on an old entry, ignore it — the marker line is the sole idempotency source.

### Step 5: Extract Insights from Journal

Extraction is no longer transcript-only. It runs five reads in parallel and merges the outputs into a unified "candidate priorities" list with provenance. Each candidate carries `{text, source, project_hint, lane_hint, context, ai_capability}` so Step 7 (task-note creation) and Step 8 (render) can set the right frontmatter tags and capability markers respectively.

#### 5-v3: Local Query Contract for Daily Planning

Before making any lane decisions, run the deterministic v3 gatherer:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/gather_daily_plan_context.py TARGET_DATE "${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}" > "$TMPDIR/process-journal-v3-context.json"
```

This script treats frontmatter as the local API and returns structured candidates:

| Bucket | Deterministic sources |
|---|---|
| `focus` | `type: task` with `status: todo/active`, due/scheduled today, or transcript/start-day project match |
| `review` | today's `type: meeting` prep/capture notes, source warnings from the `/start-day` cockpit |
| `decide` | task notes tagged `ai-pending-decision`, tasks with `blocked_by`, meeting prep `Decisions needed` |
| `dispatch` | task notes tagged `ai-handoff`, unblocked, with staged/reviewable output |
| `anchor` | habit frontmatter, mood/energy signals |
| `routing_exceptions` | always empty from the gatherer — flagging a transcript pointer that needs a new canonical home is a model judgment call made in this step and Step 7, not something inferable generically from frontmatter |

Minimum bar for a daily-hub item:
- It has a source: transcript, start-day cockpit, task note, meeting note, or source warning.
- It has or needs a canonical home: project hub, task note, meeting note, devlog, or explicit routing exception.
- It matters today.
- It has a next action, next question, or verification action.

Lane assignment is intentionally boring:

```text
Is it today's main human work? -> Focus
Does existing evidence need verification? -> Review
Is there a human fork/blocker? -> Decide
Can AI move it safely with context and staging? -> Dispatch
Is it health/life/sustainability? -> Anchor
Otherwise -> keep it in /start-day Threads To Keep Visible, not the daily hub
```

The model may synthesize the Work Anchor and timeboxed plan from this JSON, but it should not invent lane items outside these queried candidates. If the transcript mentions something important but no canonical object exists, put it in `Routing Exceptions` and create/propose the correct task or note in Step 7.

Area ordering used for sorting candidates (`priority_sort`/`focus_sort` in the gatherer) is parsed at runtime from this vault's own `AGENTS.md` areas table — never hardcode an area list here.

#### 5a: Read all five sources

| # | Source | How |
|---|---|---|
| 1 | Today's transcript (`## Morning` section) | `obsidian read path="5. Resources/Personal/Journal/Morning Entries/$today.md"` then extract under `## Morning` |
| 2 | Prior-day hub | `bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/parse_prior_hub.sh $yesterday` |
| 3 | `/start-day`'s in-journal Warm/Cold recap | `bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/parse_startday_recap.sh $today` |
| 4 | Project hub `Current Status` snapshots (only for projects named in transcript) | `obsidian read path="<hub>"` then locate `## Current Status` |
| 5 | Contact context for each named person | `bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/resolve_contact.sh "<name>"` per name |

Run sources 2, 3, and 5 unconditionally. Run source 4 only for projects the transcript explicitly names. Source 1 is the spine.

#### 5b: Carry-forward reconciliation (against prior-day hub)

For every bullet in source #2 (`parse_prior_hub.sh` output):

1. If the bullet has a `wikilink_target` that resolves to a task note via `read_task_status.sh`:
   - `status == "done"` → drop. The work shipped; do not carry forward.
   - `status` in `{"todo", "in-progress", "on-hold"}` → carry as a candidate with `lane_hint: "carry-forward"`.
   - `status` empty / `found: false` → carry as a candidate with `lane_hint: "carry-forward"` and a `(no task note)` marker.
2. If the bullet had no wikilink at all (plain text): carry as a candidate with `(no task note)` and `lane_hint: "carry-forward"`.
3. Annotate each carried bullet with its prior lane in the `context` field (e.g. `"was p1 due TODAY"`). Step 8's render uses this for the `(carry-forward from <date>)` marker on the absorbing lane.
4. **Note (5/18 delta — Decision 1):** carry-forward items do NOT render in a separate "Yesterday's open items" lane. They get absorbed into Must do / Focus work / Could-hand-off-to-AI per their content, with a `(carry-forward from <date>)` marker. Items with no concrete today-action go to "Also on the radar" with `(carry-forward p2 from <date>; no concrete edge today — stay aware)` per Decision 9.

**Caveat on `blocked_by` parsing:** `read_task_status.sh` reads `blocked_by` as a scalar via `fm_value`. When the task's `blocked_by:` frontmatter is an empty list `[]`, the script returns the literal string `"[]"`. Treat both `""` and `"[]"` as "not blocked" in 5d below.

#### 5c: Warm-band carry-through (against `/start-day` recap)

For each entry in source #3 (`parse_startday_recap.sh` output):

1. If the project's slug appears in the transcript (case-insensitive substring match against transcript text): no carry-through; the transcript-driven extraction (5a #1) will surface it directly.
2. If the project's slug does **not** appear in the transcript:
   - If a today's transcript-extracted priority resolves to a **parent area or project** that this project is a child of (e.g. {Project2} under "Re-orient on {WorkArea}"), emit as a **sub-bullet candidate** with `lane_hint: "sub-project-under-<parent>"`.
   - Otherwise emit as a standalone candidate with `lane_hint: "also-on-radar"` and `context: "{band}, {days_silent}d"`.
3. Cold band entries follow the same logic but always default to `also-on-radar` (no sub-project promotion).

Parent-resolution heuristic: a warm project is a "child" of a transcript priority when (a) they share an area, AND (b) the transcript priority's text contains a phrase like "re-orient on", "catch up on", "audit", or "review" referencing the area — the kind of meta-priority that naturally umbrellas sub-projects. When uncertain, render as standalone "Also on the radar".

#### 5d: Blocker inference (propose-confirm-record loop) — 5/18 delta extends this

For each candidate priority surfaced by 5a/5b/5c that has an associated project slug:

1. Read the task note's `blocked_by` frontmatter via `read_task_status.sh`.
   - Filled with wikilinks → use as-is. Skip inference. The chain renders inline on the bullet per Decision 3 of the 5/18 delta.
   - Literal `none` → user has confirmed no blockers. Skip inference. Render normally.
   - Empty / missing / `"[]"` / no task note → run inference (next step).
2. Run the blocker scanner:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/scan_blockers.sh "<priority text>" "<project slug>" "<transcript path>"
   ```
   ~10 second budget per priority. If the scanner returns zero hits, move on (no prompt). If hits are very high (>20), summarize the top 5 by source diversity before presenting.
3. If the scanner returns hits, propose them in a single prompt to the user:
   ```
   [[Priority]] — possible blockers I found:
     • <description> (source: <source_path> · <source_section>)
     • <description> (source: <source_path> · <source_section>)

   [Confirm + record]  [Edit]  [Skip — not blocked]
   ```
4. On **Confirm**:
   - For each proposed blocker that resolves to an existing task note → use its wikilink.
   - For each proposed blocker without a task note → flag for Task-Note Creation in Step 7 (do **not** auto-create here; the user reviews the batch then).
   - **5/18 delta (Decision 6) — Insight→action rule**: For EACH confirmed chain, ALSO propose the **first concrete unblock-step task** (verb + target). Examples: `"Email {advisor} to set a meeting date"`, `"Confirm {deadline} status and schedule the prep block"`. The user confirms creation; Step 7 (the task-creation step) then creates the task note with `← unblocks <chain>` reasoning written into the body. No chain gets confirmed without producing at least one concrete actionable task — vague execution-strategy steps are not acceptable.
   - Write `blocked_by:` to the priority's task note frontmatter (only if the task note exists).
5. On **Edit**: ask which blockers should actually apply. Re-prompt with the corrected list. Same Decision-6 rule on confirmation.
6. On **Skip**: write `blocked_by: none` to the task note. This is the permanent "user confirmed no blockers" marker — never re-infer.

If no task note exists for the priority and the user confirms blockers, the `blocked_by` write is deferred to Step 7 (the task-creation step, when the task note is created). The chain back-reference renders inline on the bullet in Step 8 (the render step) from the in-memory result, formatted per the 5/18 delta:
- `← unblocks <plain description>`
- `← part of the <cluster name>` (e.g. "the reply-debt cluster")
- `← starts the <path name>` (e.g. "the {application} approval path (next: advisor meeting → approval → decision)")

#### 5e: Contact re-grounding (per named person)

For each first-name mentioned in the transcript:

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/resolve_contact.sh "<name>"`.
2. If `found: true`: use the canonical wikilink + context summary in any priority bullet that mentions this person.
3. If `found: false`: use the raw name as a red wikilink (`[[Raw Name]]`) so clicking it creates the contact page later.
4. For names that appear in the AI Summary's `People mentioned` line (Step 6), use the same resolved wikilinks. Do not duplicate the resolution.

#### 5f: Extract from transcript (the original Step 5 logic, narrowed)

After 5b/5c/5d/5e produce their candidate sets, extract from the transcript itself:

- **AI Summary** (2–3 sentences) — same as v1. Concise summary of what the person discussed, their state of mind, and key themes. Write in third-person observational tone.
- **Mood** — same as v1. Single word or short phrase capturing the emotional tone. Examples: "reflective, motivated", "stressed but hopeful", "energized", "contemplative".
- **Themes on the mind** (new) — recurring topics that aren't actionable today. Pattern: "I wonder if…", "I've been thinking about…", "we keep coming back to…". Render in the AI Summary in Step 6.
- **Today's transcript-explicit priorities** — verbs of intent ("I want to", "I need to", "we have to", "let's", "going to"). Each becomes a candidate with `source: "transcript"` and a `project_hint` extracted from surrounding context (project name mentioned, area implied).
- **Research questions** (new) — patterns like "I wonder if X can…", "can we…", "is there a way to…". **5/18 delta (Decision 2):** these become first-class task-note candidates with `tags: [task, research]`. They do NOT render in a separate "Research questions" lane — they surface via the existing Tasks Overview Base on the daily hub. Treat as a regular candidate with `lane_hint` determined by Section 8a rules; the `research` tag is added in Step 7 (task-note creation).
- **AI-handoff candidates** (new) — explicit language like "AI can definitely handle", "the AI should be able to", "dispatch this". Each becomes a candidate with `lane_hint: "could-hand-off-to-ai"` and `ai_capability: "ai-handoff"` (set in 5h).
- **Gratitude** — same as v1. Must be explicitly stated; never inferred. If not stated, mark missing: `**Gratitude**: ⚠️ No gratitude entry today. What are 3 things you're grateful for?`
- **People mentioned** — feed into 5e.

#### 5g: Merge candidates with dedup

Combine the candidate lists from 5b + 5c + 5f into one list. Dedup by `(project_slug, normalized_text)` — two candidates that point to the same underlying work merge, with the union of their `context` fields kept on the surviving entry. Provenance is preserved (`source: ["transcript", "carry-forward"]` etc.) for the Step 8 parenthetical suffix.

When a transcript candidate matches a carry-forward candidate (same task note or same normalized text): the carry-forward annotation is dropped from the parenthetical (the transcript reinforces today; no need to surface "carry-forward" since it's already actively on the mind). The `(carry-forward from <date>)` marker only renders when the user did NOT re-mention it.

#### 5h: AI capability classification (5/18 delta — Decisions 4–5)

For each merged candidate from 5g, classify into one of three AI-capability levels. This drives the task-note `tags:` frontmatter (Step 7, the task-creation step) and the bullet capability marker (Step 8, the render step).

| Classification | Tag set | Bullet marker | Rule |
|---|---|---|---|
| `human-only` | `[task]` | *(unmarked)* | Replies, person-to-person comms, identity-level decisions, anything requiring tacit context the AI can't fully see |
| `ai-handoff` | `[task, ai-handoff]` | 🤖 | Codebase work + research + structured queries with clear inputs — AI can run autonomously now |
| `ai-pending-decision` | `[task, ai-pending-decision]` | ⏳ | Code/work that depends on a specific human decision named in the note body |

Persist the classification on the candidate as `ai_capability`. Step 7 (task-creation) reads it to set `tags:` on the task note; Step 8 (render) reads it to render the marker prefix.

**Note on GWS-CLI deferral:** Reply-drafting via GWS-CLI is deferred until permissions land. Once shipped, draftable replies graduate to `ai-pending-decision` (AI drafts → user reviews → user sends). Until then, replies stay `human-only`.

### Step 6: Write AI Summary to Journal Entry

The `### AI Summary` heading already exists at the bottom of the journal entry (placed by `ensure_journal.sh` with placeholder text, nested under `## Morning`). Render the private summary from the same v3 context JSON used by the daily hub, then replace the heading body.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/gather_daily_plan_context.py TARGET_DATE "${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}" > "$TMPDIR/process-journal-v3-context.json"
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/render_ai_summary.py "$TMPDIR/process-journal-v3-context.json" > "$TMPDIR/process-journal-ai-summary.md"
```

Script-only runs may apply the rendered summary directly:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/write_ai_summary.py "$TMPDIR/process-journal-v3-context.json" "${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}"
```

Interactive skill runs compose the full body — the rendered work-signal paragraphs from `render_ai_summary.py`, plus the model's own Mood/Gratitude/People-mentioned extraction from the transcript (per the extraction rules below) — and patch it in one call:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="AI Summary",
    content="""<rendered paragraphs from process-journal-ai-summary.md>

**Mood**: [extracted mood]
**Gratitude**:
1. [item 1]
2. [item 2]
3. [item 3]
**People mentioned**: [[Person 1]], [[Person 2]]
"""
)
```

**What's NOT in the AI Summary:**
- **Habits** — already tracked in frontmatter properties (single source of truth). Weekly review aggregates from frontmatter.
- **Priorities extracted** — actionable ones flow to the daily hub (Step 8, the render step) and are classified for task note creation (Step 7). No need to duplicate in AI Summary.

**People mentioned** — always use `[[wikilinks]]` for people, even if no contact page exists yet (red links in Obsidian prompt page creation later). Search vault contacts first for full names:

```python
mcp__qmd__search(query="{Contact}", collection="vault")
```

If found: `[[{Contact} {ContactLastName}]]` (full name from contact page)
If not found: `[[{Contact}]]` (red link — creates page when clicked)

**Re-processing (merge behavior)**: If the user re-processes an already-processed entry (Step 3 confirmed):

1. **Summary and mood**: Replace with fresh extraction (these are subjective — always use the latest read)
2. **Gratitude and people**: Replace with fresh extraction
3. **Daily hub plan**: re-render the v3 Work Anchor / Control Queue / Today's Plan in Step 8. Deduplicate by canonical task/note link where possible.

Use `replace` on the existing `AI Summary` heading instead of `append`. Do NOT include `### AI Summary` in the content when using `replace` — the heading itself is preserved by the patch tool.

### Step 6b: Task Note Cross-Referencing

Cross-reference extracted priorities against existing task notes:

1. For each extracted priority, use the shared helper:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/match_task_note.sh "distinctive keywords"
   ```
   This searches all `*/Tasks/*.md` locations (`2. Projects/{Area}/Tasks/`, `2. Projects/{Area}/{Project}/Tasks/`, `Personal/Tasks/`, `Personal/{Project}/Tasks/`).

2. If a matching task note exists: note it for the daily hub display (include task note status and priority)
3. If no task note exists and the priority warrants one (specific action, due date, multi-session): flag for creation in Step 7 (task-creation step)

### Step 6c: Previous Evening Chain Link (safety net)

`/start-day` Step 4b renders the Previous Evening link inside the `### Last Night's Reflection` blockquote. This step is a safety net for when `/start-day` was skipped: if the `### Last Night's Reflection` section has no Previous Evening link, insert one inside that section's blockquote:

```markdown
> **Previous Evening**: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD-1|Last Night's Evening]]
```

Where `YYYY-MM-DD-1` is yesterday's date. If the link is already present (the normal case — `/start-day` ran), do nothing. Never insert it at the top of the file.

### Step 7: Create Task Notes and Todoist Mirrors

Task notes are the source of truth. Todoist is a notification/reminder layer. This step creates task notes first, then optionally mirrors them to Todoist. **This step runs BEFORE Step 8 (render)** so that every actionable bullet on the rendered hub wikilinks to a real task note — no `(no task note — create)` placeholders.

#### 7a: Classify each priority

| Classification | Criteria | Action |
|---------------|----------|--------|
| **Task note warranted** | Specific action, has a due date, spans sessions, or p1/p2 | Create task note (7c), optionally mirror to Todoist (7e) |
| **Quick action** | Sub-15-min, no tracking needed | Todoist-only (7e) or skip entirely |
| **Reflection** | Vague intention, life decision, habit/routine | Skip — leave in journal only |

#### 7b: Dedup against existing task notes

For each priority classified as "task note warranted", run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/match_task_note.sh "distinctive keywords"
```

If a matching task note is found:
- Do NOT create a new task note
- If the matched task note has `status: done`, note it for the batch presentation ("mentioned again — reopen?")
- Otherwise, use the existing task note (its wikilink will be placed in Step 8)

#### 7c: Route new task notes to the correct folder

Per spec Section 4 (Area-Level Task Routing):

| Priority's area | Task note location |
|-----------------|-------------------|
| Work/business project ({WorkArea}/{SideArea2}/{SideArea} + project) | `2. Projects/{Area}/{Project}/Tasks/{Task Name}.md` |
| Work/business area (no project) | `2. Projects/{Area}/Tasks/{Task Name}.md` |
| Personal life project (APAC-Trip, Health, Finances, etc.) | `Personal/{Project}/Tasks/{Task Name}.md` |
| Personal life area (no project) | `Personal/Tasks/{Task Name}.md` |

**Never** route task notes to the knowledge-notes folder — task notes live exclusively under `*/Tasks/` per the table above.

#### 7d: Task note frontmatter

The `tags:` block is set from the candidate's `ai_capability` field (assigned in Step 5h):

| `ai_capability` | `tags:` |
|---|---|
| `human-only` (default) | `[task]` |
| `ai-handoff` | `[task, ai-handoff]` |
| `ai-pending-decision` | `[task, ai-pending-decision]` |

If the candidate is a research question (per Step 5f), the `research` tag is added on top of the above. These tags mirror to Todoist/Linear labels via Step 7e (the Todoist mirror sub-step).

```python
# Determine tags based on the candidate's ai_capability (from Step 5h)
if candidate.ai_capability == "ai-handoff":
    tags = "tags:\n  - task\n  - ai-handoff"
elif candidate.ai_capability == "ai-pending-decision":
    tags = "tags:\n  - task\n  - ai-pending-decision"
else:  # human-only (default)
    tags = "tags:\n  - task"

# If candidate is a research question (per Step 5f), add `research` tag
if candidate.is_research_question:
    tags += "\n  - research"
```

```python
mcp__obsidian-mcp-tools__create_vault_file(
    filename="{routed_path}",
    content=f"""---
date: YYYY-MM-DD
type: task
status: todo
area: {area_slug}
project: {project_slug}
priority: {p_level}
due_date: "{YYYY-MM-DD if known else empty}"
scheduled_date: ""
done_date: ""
blocked_by: ""
external_id: ""
{tags}
---

# {Task Name}

> **Project**: [[{Project Hub}]]

{1-2 sentences of context from the journal transcript}

## Dev Log

<triple-backtick>base
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
<triple-backtick>
"""
)
```

(Replace `<triple-backtick>` above with three literal backticks when writing actual task note content. The skill doc can't inline nested triple-backticks cleanly.)

#### 7e: Optional Todoist mirror

For each new task note (or existing task note re-mentioned today), decide whether to mirror to Todoist:

| Create Todoist mirror? | When |
|----------------------|------|
| Yes | Has a due date, or priority p1/p2, or user needs a reminder notification |
| No | Reference task that lives in the task note alone (e.g., "figure out X") |

If mirroring:
```bash
td task add "Task description" \
  --project "{AreaProject}" \
  --labels "{area_label}" \
  --priority p3 \
  --due "today"
```

Record the Todoist task ID in the task note's `external_id` frontmatter:
```bash
obsidian property:set path="{task note path}" property="external_id" value="Todoist: {task_id}"
```

#### 7f: Present batch for approval

Before creating anything, present the batch:

```
Task proposals from YYYY-MM-DD journal:

CREATE TASK NOTES ({N}):
├─ [{Area}/{Project}/Tasks/{Name}] — {summary} [priority, due_date]
└─ ...

MIRROR TO TODOIST ({M}):
├─ Task note {Name} → Todoist "{Name}" [project, p-level, due]
└─ ...

TODOIST-ONLY / QUICK ACTIONS ({Q}):
├─ "{text}" → Todoist [project, p4]
└─ ...

SKIP ({S} — not actionable):
├─ "{text}" — reflection
└─ ...

EXISTING TASK NOTES ({E} — already present):
├─ {Name} (status: todo) — mentioned again, comment added to Todoist
└─ ...

Create these? [Y/n/edit]
```

Wait for user confirmation. If user says "edit", ask which items to modify. If "n", skip creation and proceed to Step 7g.

#### 7g: Append bottom marker line

After all creation steps complete (even if the user skipped all), append a marker line to the journal entry body.

**First run** (no existing marker):
```bash
obsidian append path="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md" content="
*Processed ${timestamp} · ${todoist_count} tasks created in Todoist*"
```

Where `timestamp` is `YYYYMMDDHHMM` (e.g., `202604201239`) and `todoist_count` is the number of Todoist tasks actually created in this run.

**Re-run** (existing marker detected in Step 4): REPLACE the existing marker line in place — do NOT append a second marker line. Use direct file edit (read the file, `sed`-replace the `*Processed ...` line, write back). Appending would compound the MCP `patch_vault_file` bottom-append bug that motivated this refinement.

**Do NOT** set any frontmatter flag — `todoist_tasks_created` and `journal_processed` are both dropped. The marker line is the sole idempotency source.

### Step 8: Write Daily Hub v3

This step writes the committed daily operating plan to the daily hub via a single heading patch on `Morning Journal`. For v3, use the deterministic context and renderer scripts:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/gather_daily_plan_context.py TARGET_DATE "${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}" > "$TMPDIR/process-journal-v3-context.json"
python3 ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/render_daily_hub_v3.py "$TMPDIR/process-journal-v3-context.json" > "$TMPDIR/process-journal-v3-hub.md"
```

The rendered block must use this section contract:

```markdown
> [[5. Resources/Personal/Journal/Morning Entries/TARGET_DATE|Open Morning Entry]]

### Work Anchor
### Control Queue
**Focus**
**Review**
**Decide**
**Dispatch**
**Anchor**
### Today's Plan
### Routing Exceptions
```

`Routing Exceptions` is conditional. Render it only when the gatherer found a placement/correction/verification issue.

Patch via:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename=f"1. Daily/{today}.md",
    operation="replace",
    targetType="heading",
    target="Morning Journal",
    content="<full v3 block from process-journal-v3-hub.md>",
)
```

The model may refine the Work Anchor and plan wording after reading the context JSON, but it must preserve the queried lane membership unless it can point to a source object in `process-journal-v3-context.json`.

#### 8-legacy: Six-Lane Priorities Renderer (deprecated for v3)

The notes below describe the old Must do / Focus work / If time / Could hand off / Also on radar / Execution strategy renderer. Do not use them for current v3 daily hubs.

This legacy step composes the 6-lane priorities block and writes it to the daily hub via a single MCP heading patch on `Morning Journal`. The lanes are populated from the merged candidate list produced in Step 5g, classified by `lane_hint`, then rendered with capability markers, inline chain back-references, and contextual suffixes. By the time this step runs, Step 7 has already created task notes for every actionable candidate — so every bullet wikilinks to a real note, no `(no task note — create)` placeholders.

#### 8-pre: Read existing hub state

```bash
obsidian read path="1. Daily/$today.md"
```

Confirm the `## Morning Journal` heading exists at H2. On a re-run, extract any existing bullets under each lane for merge (8i).

#### 8a: Lane classification — assign each candidate to one of six lanes

Walk each candidate from Step 5g; assign to **exactly one** lane based on the rules below (first-match wins, top to bottom):

| Lane | Triggers (any match → this lane) |
|---|---|
| **Must do** | priority p1 or p2 (from task note); OR due today/overdue; OR transcript uses urgency language ("I have to", "I need to today", "overdue", "must"); OR `lane_hint == "reply-debt"` (set when context contains "promised", "owed", "follow-up rule") |
| **🤖 Could hand off to AI** | `ai_capability == "ai-handoff"` (set by 5h) AND not Must-do urgency |
| **Focus work** | the priority has a project hint matching today's session work, OR carries a parent for sub-project promotion (5c step 2), OR is the transcript's primary topic |
| **If time** | low-energy language ("maybe", "eventually", "if I get to it", "would be nice"); OR no urgency signal and no project anchor |
| **Also on the radar** | `lane_hint == "also-on-radar"` (set by 5c); OR `lane_hint == "carry-forward"` AND the candidate has no concrete today-action (Decision 9) |
| **Execution strategy** | synthesis lane — populated in 8e after all bullet lanes are settled |

Carry-forward absorption rule (5/18 delta — Decision 1): candidates with `lane_hint: "carry-forward"` that DO have a concrete today-action are absorbed into Must do / Focus / Could-hand-off-to-AI per the rules above, with a `(carry-forward from <date>)` marker appended to their context. Carry-forwards WITHOUT a concrete today-action go to "Also on the radar" with `(carry-forward p2 from <date>; no concrete edge today — stay aware)`.

Research-question candidates (`tags: [task, research]` from Step 5f / Step 7 task-note creation) classify like any other candidate — they don't get a dedicated lane. They surface separately via the existing Tasks Overview Base on the daily hub.

If a candidate matches none of the lanes above, default to **Focus work**.

#### 8b: Meta-theme subtitle synthesis

Synthesize a single `(meta-theme: …)` subtitle from the transcript + carry-forward state. Goal: one phrase that captures what the day is *about*. Examples from prior days:

- `*(meta-theme: system-build has been blocking deliverables; today is about closing the loop — ship process-journal v2, batch the comms debt, dispatch the autonomous-handoff layer)*`

Heuristics:
- If a single project dominates Must do + Focus work, the meta-theme is "ship X" or "close the loop on X".
- If carry-forward is heavy, the meta-theme references catching up or unblocking.
- If reply-debt is heavy, the meta-theme references comms cleanup.

Render this subtitle on the priorities header (see 8g).

#### 8c: Notation legend

Immediately under the priorities header, render this exact italic legend line:

```
> **Notation:** 🤖 = AI can run autonomously now · ⏳ = AI can run after the named human decision · *(unmarked)* = human-only · `← unblocks <X>` = back-reference to a chain context inline on bullets
```

#### 8d: Render lanes 1–5

Render each lane only if it has at least one bullet. Lane order is FIXED:

1. **Must do** — with an optional subtitle when all bullets share a theme (e.g. `*(reply debt — all overdue)*`). Bullet format:
   ```
   - [<marker?>] [[Task Note Wikilink]] *(<context>)* ← <chain back-reference if any>
   - [<marker?>] [[Reply to Person]] *(48hr rule, 5+ wk past)* ← part of the reply-debt cluster
   ```
   Marker `🤖` / `⏳` / *(unmarked)* per the task note's `ai_capability` from 5h. ALL named entities in the bullet must be wikilinks (Decision 12 — see Section 8f).

2. **Focus work** — with optional subtitle `*(today's deep work — <synthesized theme>)*`. Bullet format:
   ```
   - [<marker?>] [[Task Note]] *(<carry-forward state if any>)* ← <chain back-reference>
   - [[Re-orient on {WorkArea} work — status and next steps]] *(carry-forward p2 from 5/16; no concrete edge today — stay aware)*
     ↳ Warm sub-projects under this:
       • [[{Project3}]] — 7d since [[Request {Project3} license from {Contact1}]]
       • [[{Project2}]] — 14d since [[2026-05-04 - {Last Session Title}]] *(just flipped Warm → Cold)*
   ```
   (Note: the carry-forward-p2-with-no-edge example actually belongs in "Also on the radar" per Decision 9 — included here only to show the sub-project nesting pattern. Sub-project bullets come from Step 5c's parent-resolution.)

3. **If time** — bullet format:
   ```
   - [<marker?>] [[Task Note]] *(<context>)*
   ```

4. **🤖 Could hand off to AI** *(dispatch in parallel — autonomous TODAY)* — note the 🤖 prefix on the lane header itself as a section signpost. Bullet format:
   ```
   - 🤖 [[Mobile app bug review and fix pass]] *([[Portfolio]] · cold, 71d)* — verbatim: "right now the mobile is kind of buggy..." ← first live test of the autonomous-dev pattern
   ```
   Include a `verbatim: "<transcript quote>"` suffix when the transcript explicitly says "AI can handle" / "dispatch" / similar.

5. **Also on the radar** *(transcript-named or implied, not today-actionable)*. Bullet format:
   ```
   - [[Project Hub]] *(warm, 7d)* — <context for why mentioned>
   - [[Carry-Forward p2 Item]] *(carry-forward p2 from 5/16; no concrete edge today — stay aware)*
     ↳ Warm sub-projects under this:
       • [[Sub-Project]] — Nd since [[recent file]]
   ```

#### 8e: Synthesize the Execution strategy lane

Compose a numbered day plan that orders the Must do + Focus work + Could-hand-off-to-AI bullets into a feasible sequence. **Every numbered step `→` points at a wikilink to a bullet already rendered above** (Decision 8). No item lives only in the strategy — if a step describes work that has no corresponding bullet above, the bullet is missing from a lane and must be added.

Step format:
```
N. **<Phase label>** → <wikilink(s) to bullets above> (<lane reference>)
```

Examples (5/18 fixture):
```
1. **Now** → [[Ship /process-journal v2 today]] (Must do)
2. **Quick discovery** → [[Email {advisor} to set meeting date]] + [[Confirm {deadline} status and schedule prep block]] (Must do)
3. **Reply batch — single 30-min block** → [[Reply to {Contact}...|{Contact}]] · [[Reply to {Contact1}...|{Contact1}]] · ... (Must do)
4. **🤖 Dispatch AI handoffs in background** → [[Mobile app bug review and fix pass|Portfolio fix]] · ... (Could hand off to AI — all N)
N. **Before EOD** *(housekeeping — not bullets)* → confirm carry-forward outcomes, lock fork decisions
N+1. **EOD** *(housekeeping — not bullets)* → `/vault-commit` · [[5. Resources/Personal/Journal/Evening Entries/$today|evening journal]]
```

Heuristic phase ordering:
1. **Now** — foreground session work (usually inferred from the most-recent transcript paragraph).
2. **Quick discovery** — small lookups / status checks that unblock later work.
3. **Reply batch** — batched reply debt.
4. **🤖 Dispatch AI handoffs in background** — Could-hand-off-to-AI lane in parallel.
5. **Foreground (pick one)** — the top Focus work item.
6. **Before EOD** *(housekeeping — not bullets)* — verification / anchor commitments.
7. **EOD** *(housekeeping — not bullets)* — `/vault-commit`, evening journal.

Omit any numbered step whose source lane is empty. Renumber sequentially.

#### 8f: Wikilink discipline (Decision 12)

Every named entity in the rendered hub MUST be a wikilink to its canonical vault note:
- **People** → `4. Contacts/People/<Name>.md` (resolved via 5e contact re-grounding; voice-fuzz tolerance handled by `resolve_contact.sh`)
- **Actions** → task notes in `*/Tasks/` (created by Step 7 — the task-creation step that ran before this render)
- **Projects** → project hubs in `2. Projects/<Area>/<Project>/` (used only when a project-level reference is meant, not a specific action)
- **Devlogs, design notes, plans** → their canonical paths
- **Housekeeping references** ({SideArea} hubs, {Project1}, {Project2} in `/vault-commit` context) → project hubs

Pipe aliases (`[[Long Task Name|short label]]`) are encouraged where the canonical filename is verbose.

#### 8g: Compose the full block + patch

Assemble in this exact order (omit empty lanes):

```
> [[5. Resources/Personal/Journal/Morning Entries/$today|Open Morning Entry]]

**Today's priorities** *(meta-theme: <synthesized day theme from 8b>)*

> **Notation:** 🤖 = AI can run autonomously now · ⏳ = AI can run after the named human decision · *(unmarked)* = human-only · `← unblocks <X>` = back-reference to a chain context inline on bullets

**Must do** *(<subtitle if unifying theme>)*:
- [<marker?>] [[Task Note]] *(<context>)* ← <chain back-reference>
- ...

**Focus work** *(today's deep work — <theme>)*:
- ...

**If time** *(<subtitle if fork decision>)*:
- ...

**🤖 Could hand off to AI** *(dispatch in parallel — autonomous TODAY)*:
- 🤖 [[...]] — verbatim: "..." ← <chain ref>
- ...

**Also on the radar** *(transcript-named or implied, not today-actionable)*:
- [[Project Hub]] *(warm, Nd)* — <context>
- ...

**Execution strategy** *(today's order — every actionable bullet above maps to a step here)*:
1. **Now** → [[...]] (<lane>)
2. **<Phase>** → [[...]] (<lane>)
...
N. **Before EOD** *(housekeeping — not bullets)* → ...
N+1. **EOD** *(housekeeping — not bullets)* → ...
```

Two trailing blank lines after the last lane, then the existing `---` separator stays intact.

Patch via:
```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename=f"1. Daily/{today}.md",
    operation="replace",
    targetType="heading",
    target="Morning Journal",
    content="<full block above>",
)
```

#### 8h: Guard against duplicate sections

After patching, re-read the daily hub. If a duplicate `Morning Journal` section appears at the bottom (known MCP `patch_vault_file` issue), remove it via direct file edit.

#### 8i: Re-run merge behavior

If Step 4's idempotency check detected an existing bottom marker and the user confirmed re-run:

1. Re-classify all candidates fresh (today's date may have shifted urgency).
2. For each lane, dedup new bullets against existing bullets in the same lane (compare by normalized description text after stripping wikilinks).
3. Preserve any `← unblocks <X>` chain annotations from existing bullets unless inference found different chains (then prompt: "Replace existing chain context? [y/N]").
4. Re-render the entire block; do NOT attempt surgical bullet-level patches.

### Step 8j: Commit the Processing Output

Snapshot the processing run's output in the vault git repo so the morning-recording → processing → nightly-`/vault-commit` chain shows up as three distinct, legible git steps instead of folding processing into `/vault-commit`'s nightly pass:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/process-journal/scripts/commit_journal_processing.sh TARGET_DATE VAULT_PATH [TASK_NOTE_REL...]
```

`VAULT_PATH` is `${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}`. Pass the vault-relative paths of every task note created or modified in Step 7c as additional arguments. The script commits:

- `5. Resources/Personal/Journal/Morning Entries/TARGET_DATE.md` (AI Summary written in Step 6, bottom marker appended in Step 7g)
- `1. Daily/TARGET_DATE.md` (priorities block written in Steps 8a–8g)
- Any task notes passed as arguments (created in Step 7c)

with the message `docs: process-journal for TARGET_DATE`.

**If the task note list is empty** (user declined all creation in Step 7f, or this is a re-run with no new task notes): omit the task note arguments — the script falls back to the two core paths.

Parse the JSON output:
- `{committed: true, sha, ...}` — report the commit in Step 9's execution report.
- `{committed: false, reason: "no_changes"}` — re-run with nothing new to commit; report as skipped, not a failure.
- `{committed: false, error: "..."}` — the commit failed. **Warn, don't abort**: continue to Step 9 and surface the error in the Warnings section. The journal entry and daily hub are already written; a missed snapshot must not block the morning workflow.

### Step 9: Report Results

Display a summary followed by the execution report (per `vault-config/references/source-manifest.md`):

```markdown
Journal processed for YYYY-MM-DD.

**Summary**: [2-3 sentence summary]
**Mood**: [mood]
**Habits**: N/M completed (list checked items, note missed items)
**Daily hub**: v3 plan rendered:
  - Focus: N
  - Review: N
  - Decide: N
  - Dispatch: N
  - Anchor: N
  - Routing Exceptions: N
**Todoist**: [created count] tasks created, [initiative count] initiatives, [skip count] skipped, [existing count] already existed
**Gratitude**: [3 items written to journal / already present / ⚠️ not mentioned — prompt shown]
**People**: [list or "none mentioned"]

Journal entry updated: [[5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD]]
Daily hub updated: [[1. Daily/YYYY-MM-DD]]

---
### Execution Report
#### Sources
- [x] Obsidian CLI — journal read, daily hub read/write
- [x] Obsidian MCP — N sections patched
- [x] QMD Search — people lookup, N contacts resolved
- [x] Todoist — N tasks created, M deduped
- [x] Processing commit — abc1234 `docs: process-journal for YYYY-MM-DD`

#### Warnings
- [only if there are actual warnings]

#### Fix
- [only if there are failed sources with actionable fixes]
```

Only include the Warnings and Fix sections if there are actual warnings.

## Verification (v3 render contract)

Before shipping a change to Step 5, Step 7, Step 8, or the v3 gather/render scripts, feed `gather_daily_plan_context.py` a fixture vault (or synthetic context JSON matching its documented output shape) and confirm:

- the deterministic local gather creates Focus, Review, Decide, Dispatch, and Anchor candidates (Routing Exceptions stays empty unless the model adds one in Step 5/7)
- `render_daily_hub_v3.py`'s output includes `### Work Anchor`, `### Control Queue`, `### Today's Plan`, and conditional `### Routing Exceptions`
- the old `**Today's priorities:**` block does not render
- the work-budget sentence (`5.5-6.5 usable focus hours`) stays visible

## Verification (legacy 5/18 fixture)

The 2026-05-18 daily hub is the byte-level regression target for the v2 render shape. After any change to Step 5 / Step 7 / Step 8, run a dry-run against 2026-05-18 and diff vs the committed hub.

### Acceptance criteria

**Acceptable deviations (paraphrasing):**
- Lane subtitle wording (e.g. "reply-debt + chain-unblockers" vs "reply debt — all overdue")
- Chain descriptor wording inside `← unblocks <X>` annotations
- Execution-strategy step labels (the *phase labels*, not the underlying wikilinks)
- Meta-theme subtitle wording
- The exact ordering of bullets within a single lane (provided the lane content is equivalent)

**NOT acceptable (regressions — investigate and fix):**
- Lane order differs from: Must do · Focus work · If time · 🤖 Could hand off to AI · Also on the radar · Execution strategy
- Any lane present in the committed hub is missing in the rendered output (or vice versa)
- Capability markers (🤖 / ⏳ / *(unmarked)*) on bullets missing or wrong
- Any actionable bullet rendering as plain text instead of a wikilink to a task note — i.e. `(no task note — create)` placeholders appearing post-Step-7
- Inline `← unblocks <X>` / `← part of the <cluster>` / `← starts the <path>` annotations missing on chain bullets
- The `> **Notation:** ...` legend line missing under the priorities header
- The `*(meta-theme: ...)*` subtitle on the priorities header missing
- Sub-project nesting under "Also on the radar" carry-forward-p2 items (`↳ Warm sub-projects under this:`) missing
- Step 7 (task creation) running AFTER Step 8 (render) — sequence flip is mandatory per Decision 7

### Regression triage

If a "not acceptable" item appears, trace back:
- Missing lane or wrong ordering → Step 8a lane classification rules
- Missing capability marker → Step 5h AI capability classification OR Step 7d task-note tag wiring
- `(no task note — create)` placeholder → Step 7 (task creation) failed to run before Step 8 (render); check workflow ordering
- Missing `← unblocks` annotation → Step 5d blocker inference loop didn't propose the chain, or 8d/8e didn't render it
- Missing meta-theme subtitle → Step 8b synthesis didn't run or returned empty
- Missing notation legend → Step 8c literal-string render missing

### Live-fire test

The first real verification is the user's morning invocation: `/process-journal` on today's transcript. Confirm all 6 lanes render (or are correctly omitted when empty), carry-forward absorbs prior open items, blocker inference asks the right questions on at least one priority, contact re-grounding produces canonical wikilinks, and capability markers appear on bullets matching their `ai_capability` tags. Capture any hand-edits required as a gap note under {Project} and iterate.

## Extraction Guidelines

When analyzing the raw transcript:

1. **Preserve authenticity** — the summary should reflect what was actually said, not sanitize it
2. **Infer priorities from intent** — "I want to continue with {Project2}" → `- [ ] [{WorkArea}] Continue {Project2} work`
3. **Detect implicit mood** — tone, word choice, and topics reveal emotional state
4. **Be conservative with people** — only flag named individuals, not generic references
5. **Handle rambling transcripts** — voice transcripts are often unstructured; extract signal from noise
6. **Never hallucinate gratitude** — gratitude must be explicitly stated by the person, not inferred from positive sentiments in the transcript. This is a mindfulness practice; fabricating entries defeats its purpose
7. **Respect the `## Morning` / `## Evening` split** — only process content under the relevant section heading

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No journal entry for date | Report and stop |
| No daily note for date | Report and stop |
| Already processed (bottom marker line present) | Warn and ask. On confirm: refresh AI Summary and re-classify priorities (preserve task notes already created) |
| Journal is empty / very short | Extract what you can, note brevity |
| No priorities mentioned | Write "No explicit priorities mentioned" in both locations |
| No daily-plan candidates extracted | Daily hub renders the v3 section scaffold with empty-state bullets in each lane |
| No explicit gratitude | Write "⚠️ No gratitude entry today. What are 3 things you're grateful for?" — never fabricate gratitude items |
| No people mentioned | Omit the "People mentioned" line |
| Evening section present | Only process `## Morning` section (ignore Evening) |
| Gratitude already in journal | Do not duplicate — keep existing gratitude section |
| Re-run with no processing changes since last commit | Step 8j skips with `reason: no_changes` — no duplicate commit |
| Re-run that refreshed the AI Summary, priorities, or bottom marker | Step 8j commits a fresh snapshot (same message) — legitimate, not a duplicate |
| Processing commit fails (merge in progress, locked index) | Warn in execution report, do not abort — journal and hub are already written |

## What This Skill Does NOT Do

- Does not modify the raw transcript (`## Morning` / `## Evening` content stays untouched)
- Does not auto-create tasks without approval (always presents batch for confirmation)
- Does not process the Evening section (separate future skill: `/process-evening`)
- Does not create the daily note if missing
- Does not handle task graduation to Obsidian project pages (flags for graduation, but creation is manual)
