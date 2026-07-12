---
name: start-day
description: Morning prep that writes a daily cockpit into the journal page before you record: Overall Read, Movement, candidate Control Queue, Threads To Keep Visible, and At Risk. Creates the context that makes voice journal entries specific and actionable. Use when the user says "start day", "morning prep", or "/start-day".
user-invocable: true
allowed-tools:
  # Gather script (deterministic context collection)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/*.sh:*)
  - Bash(chmod:*)
  # Todoist CLI (for Linear → Todoist sync)
  - Bash(td task:*)
  # Obsidian CLI (for supplementary reads if needed)
  - Bash(obsidian read:*)
  - Bash(obsidian search:*)
  - Bash(obsidian files:*)
  - Bash(obsidian property:read:*)
  - Bash(obsidian property:set:*)
  # Obsidian MCP (patch for section writing)
  - mcp__obsidian-mcp-tools__patch_vault_file
  # QMD Search (backup devlog discovery)
  - mcp__qmd__search
  # Linear MCP (RS42 issues — can't be scripted)
  - mcp__linear__list_issues
---

# Start Day

Prep today's journal page with yesterday's context — devlogs, carry-forward tasks, calendar, and evening reflection. This is Phase A of the daily loop: **AI preps the meeting before you journal.**

## Key Principles

1. **Write to the journal page only** — the recap and full briefing go to the morning entry. Today's priorities go to the daily hub only after /process-journal processes the morning reflection.
2. **Recap window = days with captured work** — the gather script walks back through tiers (3 → 5 → 7 days) until it finds the most recent surfaceable content. The window covers `[from..today]`, with empty days between gaps rendered as a one-liner.
3. **Keep it scannable** — short bullets, not paragraphs. Group by project, not by file.
4. **Don't duplicate /process-journal** — this skill preps, it does not extract or create tasks.
5. **No silent failures** — track every source call, report what succeeded/failed/skipped. See `vault-config/references/source-manifest.md`.
6. **Task visibility via Bases queries** — the journal template's `## Tasks Overview` queries render tasks from `type: task` frontmatter. This skill does not write task lists.
7. **No task note creation** — `/process-journal` owns task note creation after the morning meeting.
8. **Privacy is respected without prompting** — files in private projects (project hub has `private: true`) are silently excluded. The gather script also stamps `private: true` directly into excluded files' frontmatter as a one-way durable marker so future tools see the flag without re-traversing the project hub.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. The gather script tracks CLI sources automatically via `source_manifest`. MCP sources (Linear, QMD) are tracked by you in Step 2.

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read/write journal, daily hub, devlogs | REQUIRED |
| Obsidian MCP | Patch sections into journal + hub | REQUIRED |
| QMD Search | Devlog lookup (backup to glob) | MEDIUM |
| Todoist CLI | Today's tasks, carry-forward, Linear sync | HIGH |
| GWS Calendar | Today's calendar events | MEDIUM |
| Linear MCP | RS42 issues → Todoist sync | MEDIUM |
| Task Notes | Task note frontmatter (all projects) | MEDIUM |
| Vault git | Scaffold snapshot commit (Step 5b) | MEDIUM |

## Invocation

```
/start-day              → prep today's journal page
/start-day 2026-03-15   → prep a specific date
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
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/gather_morning_context.sh [optional-date]
```

Parse the JSON output. It contains:
- `dates` — today, yesterday (calendar), day names
- `files` — journal/hub paths and existence flags
- `recap_window` — `{from, to, beyond_lookback, days_empty[], days[]}` where each day has `{date, day_name, devlogs[], notes[]}`. `from == to` means single-day window (the common case). `beyond_lookback: true` means the tiered probe (3/5/7 days) found no captured work — render the escape-hatch message instead of an empty recap.
- `commits` — `{available, commits[]}` where each commit has `{sha, date, subject, kind, files[], projects[], areas[]}`. Drives "What Moved Forward" and "What Changed Structurally".
- `active_projects` — `[{slug, area, hub_path}, ...]` — all `status: active` project hubs vault-wide.
- `hot` — `[{slug, area, hub_path, last_activity_date, days_silent, area_priority_rank, recency_source, plan_path, latest_in_project_age_days}, ...]` — projects with 0–3d recency. **Suppressed at render** — tracked for completeness only.
- `warm` — `[{slug, area, hub_path, last_activity_date, days_silent, area_priority_rank, recency_source, plan_path, latest_in_project_age_days}, ...]` — projects with 4–13d recency. Renders as a Warm sub-band under "Needs Attention".
- `cold` — same shape as `warm[]` plus a `reason` field — projects with ≥14d recency. Renders as a Cold sub-band under "Needs Attention".
- `todoist` — overdue + today tasks
- `workitems` — external work-item integration (inert stub — connect Linear via MCP)
- `evening` — last night's reflection content
- `meetings_today` — today's `type: meeting` notes found by local frontmatter reads, including `is_prep`, `start`, `end`, `tags`, `area`, and `project`
- `task_notes` — task-note frontmatter, including `path`, `status`, `priority`, `due_date`, `area`, `project`, `tags`, and `blocked_by`
- `areas` — ordered `[{slug, display, rank}, ...]` parsed from this vault's own `AGENTS.md` areas table (`| Area folder | \`area\` slug |`), in table row order. This is the single source of truth for area ordering and area-hub wikilink targets in the v3 cockpit render — never a hardcoded area list. An empty array means the table is missing/unparseable; the renderer degrades to a generic per-slug display and unranked (rank 99) ordering rather than crashing.
- `source_manifest` — what succeeded and what failed

If the script fails to execute, check that it has execute permission:
```bash
chmod +x ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/gather_morning_context.sh
```

## Step 2: Supplement with MCP Tools

The gather script can't call MCP tools. Fill in the gaps:

### Linear Issues (RS42)

```
mcp__linear__list_issues(assignee="me", state="In Progress")
```

Record failure and continue if unavailable. Add `- [ ] Linear in-progress — FAILED: {error}` to the execution report.

### Backup Search (only if recap window is unexpectedly empty)

If `recap_window.days` is empty AND `recap_window.beyond_lookback` is false, that's a surprise — the script found something to anchor the window on but no surfaceable content. Use QMD as a backup:

```
mcp__qmd__search(query="YESTERDAY_DATE", collection="vault")
```

Surface anything in `*/Dev Log/` or `*/Notes/` paths. Otherwise skip this step — `beyond_lookback: true` is a real signal, not a failure.

### Task Notes (all projects)

Task note discovery is handled by `gather_morning_context.sh` — read `task_notes` from the gather output. Each entry has `path`, `status`, `priority`, `due_date`, `area`, `project`, `blocked_by`. No skill-side bash loop is needed.

## Step 3: Ensure Files Exist

Check `files.journal_exists` and `files.daily_hub_exists` from the gather output.

**If journal doesn't exist**, create it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/ensure_journal.sh TARGET_DATE
```

**If daily hub doesn't exist**, create it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/ensure_daily_hub.sh TARGET_DATE
```

**If `files.journal_has_context` is true**: This is a re-run. Replace the existing context sections.

## Step 4: Interpret and Write

### 4-v3: Daily Cockpit Render (authoritative)

Use the deterministic renderer for the current `/start-day` cockpit shape. The legacy `Recent Accomplishments` instructions below (4-legacy) are retained as historical reference only; do **not** render the old `Recent Accomplishments` / `Last Night's Reflection` block for current runs.

Render from the gather JSON:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/gather_morning_context.sh TARGET_DATE > "$TMPDIR/start-day-context.json"
python3 ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/render_start_day.py "$TMPDIR/start-day-context.json" > "$TMPDIR/start-day-cockpit.md"
```

The rendered cockpit block has this section contract:

```markdown
### Overall Read
### Movement From Yesterday +/- 1
---
### Control Queue
### Threads To Keep Visible
#### At Risk
```

Optional model synthesis is allowed only inside short prose sentences:
- `Recent trend`
- `Key insight for today`
- parent-bullet summaries in `Movement`

Do not change the section order, remove source warnings, invent meetings, or invent tasks. Meeting Prep must come from `meetings_today`; Review/Decide/Dispatch candidates must come from `task_notes`, `meetings_today`, or `source_manifest`. Area order and area-hub wikilinks come from `areas` (see Step 1) — never hardcode an area list or wikilink target.

Patch the rendered block into the morning journal by replacing the existing cockpit region from `### Overall Read` through `#### At Risk`. If the journal still has the legacy `## Recent Accomplishments` scaffold, replace that legacy block with the v3 cockpit block.

`/start-day` still does **not** write the daily hub. `/process-journal` owns the daily hub after the morning entry exists.

### 4-legacy: Historical Render Notes (do not use for current v3 runs)

Read `references/context-format.md` for exact formatting rules.

`/start-day` writes **one atomic patch** into the morning journal entry — the entire `## Recent Accomplishments` block (containing the three operational subsections + the `### Last Night's Reflection` subsection) is replaced in a single MCP call. All task visibility comes from the `## Tasks Overview` Bases queries the template already provides; this skill does not write task lists.

> **Why one atomic patch.** Earlier iterations made two patch calls (one for Recent Accomplishments, a separate one for Last Night's Reflection). On re-runs after the first section had reflowed text, the second patch sometimes failed to find its H3 target and appended a duplicate H1 at the bottom of the file. Folding Last Night's Reflection into the Recent Accomplishments payload eliminates that drift. See Start-Day Iteration Findings 5-15 §5.

### 4a: Recent Accomplishments — Atomic Render

Replace the placeholder in `## Recent Accomplishments` with a single payload containing the three operational subsections **and** the Last Night's Reflection H3.

**Tone**: Direct, factual, no celebration language. "You worked on X" not "Great work on X!". Match the chief-of-staff voice — concise, evidence-grounded, no padding.

**Always render the window header line first** (single-day or multi-day):

```
> **Recap Window**: M/D → M/D · N day(s) had no captured work (M/D, M/D)
```

If `recap_window.beyond_lookback == true`, render the escape-hatch and skip the three sections:

```
> No captured work in the last 7 days. Run `/start-day --since YYYY-MM-DD` to view earlier work.
```

Otherwise render three subsections in order. Omit any subsection that would be empty.

**Ordering rule — applies to all three subsections:**

Sort entries by `area_priority_rank` ascending (primary key), then by the per-subsection secondary key below. `area_priority_rank` is emitted by the gather script on every `active_projects[]`, `hot[]`, `warm[]`, and `cold[]` entry (1={workarea-slug}, 2=rs42, 3={sidearea-slug}, 4=personal, 5=personal-finance/finance, 6=health, 7=career, 99=unknown). For entries derived from commits or devlogs (which carry an `area` field, not a direct rank), resolve the rank via the same mapping or by looking up the project in `active_projects[]`.

Per-subsection secondary keys:
- **What Moved Forward**: within an area, area-level entries (bare `- **[[Area]]** *(area-level)*`) before project entries; project entries in any stable order (alpha or evidence-volume).
- **What Changed Structurally**: within an area, no specific secondary order (typically one bullet per area).
- **Needs Attention**: within each band, sort by `area_priority_rank` ascending; secondary sort is `days_silent` ascending in Warm (freshest first), `days_silent` descending in Cold (longest-silent first).

**Area priority outranks the secondary key.** Example: a 38-days-silent {SideArea} project sorts *below* a 34-days-silent {SideArea2} project, because {SideArea2} (rank 2) outranks {SideArea} (rank 3). See spec delta 5 worked example in `Start-Day Morning Journal Render — Target Shape Spec from 5-13 Iteration.md §5`.

### What Moved Forward

Group `commits[]` (kind in `docs|feat|fix`) and `recap_window.days[].devlogs[]` by project. For each project with evidence, write a parent bullet with no inline body, then one tab-indented sub-bullet per distinct work item (commit cluster or devlog session):

```
- **[[Area]] / [[Project Hub]]**
	- Work item one — concise factual description derived from commit subjects + devlog session_topics + (optionally) note titles. No celebration words.
	- Work item two — …
```

Synthesis rules:
1. Drop the `docs:` / `feat:` / `fix:` prefix when reading commit subjects.
2. The parent bullet is bare — no dash-separated summary inline. All content goes in sub-bullets.
3. Each distinct commit cluster or devlog session becomes exactly one sub-bullet. Do not merge all sub-bullets into a single run-on sentence.
   - *A commit cluster is two or more commits from the same project that share a theme or touch the same subsystem — render them as one sub-bullet. Commits in the same project that address genuinely distinct pieces of work each get their own sub-bullet.*
4. Use the project hub wikilink as the anchor (the hub_path's filename without extension).
5. For area-level work (no project, e.g. notes in `6. Main Notes/` with only `area:` set), use a bare parent `- **[[Area]]** *(area-level)*` with sub-bullets underneath — same nested shape.

### What Changed Structurally

Filter `commits[]` to those where at least one file in `files[]` matches a structural-change pattern:

- `2. Projects/*/{Project}/{Project}.md` (project hub edits)
- `3. Areas/*/Goals/*.md` (goal hubs)
- `Personal/*/*.md` where filename equals folder name (personal project hubs)
- New project scaffolds: any commit where files include a previously-non-existent `{Project}/{Project}.md`
- `CLAUDE.md`, `AGENTS.md`, `system-settings/Templates/*` (vault config / templates)

Group by area. Write a bare parent bullet per area and structural changes as tab-indented sub-bullets underneath:

```
- **[[Area]]**
	- Structural change one — description.
	- Structural change two — description.
```

### Needs Attention

Render two H4 sub-bands. **Hot** (`hot[]`, 0–3d) is **not rendered** — projects that fresh don't need flagging; the band exists in the gather output for completeness and downstream tools.

**Subsection header:**

```
### Needs Attention
```

**Warm band — H4 (4–13 days):**

```
#### Warm — recently active, keep visible *(4–13 days)*
```

Each entry from `warm[]`, sorted by `area_priority_rank` ascending (primary), then `days_silent` ascending (freshest first within band):

When `recency_source == "in-project"`:
```
- **[[Area]] / [[Project Hub]]** — Nd since [[<last touched file or feature>]]. <Optional carry-forward context from prior journal>
```

When `recency_source == "plan"`:
```
- **[[Area]] / [[Project Hub]]** — Nd via [[<plan-name>]] (plan-driven activity; latest in-project file is Md old). <Optional carry-forward context>
```

The `<plan-name>` is the basename of `plan_path` without `.md` (e.g. `2026-05-14-vault-setup-kit-update-story`). The `Md old` value is `latest_in_project_age_days` from the entry — omit the parenthetical entirely if that field is null (no in-project file yet).

**Cold band — H4 (≥14 days):**

```
#### Cold — going stale, archive-sweep candidates *(14+ days)*
```

Each entry from `cold[]`, sorted by `area_priority_rank` ascending (primary), then `days_silent` descending (longest-silent first within band):

```
- **[[Area]] / [[Project Hub]]** — `status: active` but {reason}. Last touched {last_activity_date} ({days_silent} days ago). <Optional carry-forward context>
```

The `{reason}` comes from the gather output's `reason` field on cold entries (either "no devlog or knowledge note in this project folder" for never-touched, or "no devlog or knowledge note dated within 14 days" otherwise).

**When `recency_source == "none"`** (never-touched project; `last_activity_date == "never"`, `days_silent == 999`), omit the "Last touched … (… days ago)" tail entirely — the sentinels are not meaningful values. Render the bullet as:

```
- **[[Area]] / [[Project Hub]]** — `status: active` but {reason}. <Optional carry-forward context>
```

**Carry-forward context (optional, non-mechanical):**

For each entry rendered, check the prior morning journal (`5. Resources/Personal/Journal/Morning Entries/<yesterday>.md`)'s Needs Attention section. If the same `slug` appears there, copy any trailing prose annotation (e.g. "Load-bearing blocker for…", "{Contact} pricing follow-up still owed", "⚠ Hub `Current Status` empty — `/project-sync` overdue") onto today's entry. This is best-effort prose carry — if the annotation references a specific date or event that's stale (e.g. "today's `Teach sister` onboarding" the day after that event), drop or update it. Annotations are not derivable from gather data alone; absent a prior-journal source, omit them.

**Omission rule:**

If both `warm[]` and `cold[]` are empty, omit the entire `### Needs Attention` H3. If only one band has entries, omit the empty sub-band but keep the H3.
Hot-band population does not affect this rule — Hot is never rendered, so a non-empty `hot[]` with empty Warm/Cold still omits the H3.

**Wikilink resolution:**

All wikilinks in this section follow §4c rules (basename for areas, hub_path basename for projects, full-path form for basename collisions). Plan-file wikilinks use the plan's basename — plans live under `docs/superpowers/plans/` and basenames are date-prefixed and unique by convention; bare basename resolves.

### 4b: Last Night's Reflection (rendered inside the 4a payload)

Append the `### Last Night's Reflection` subsection as the **last** H3 inside the Recent Accomplishments payload. This is part of the same patch call as 4a — do not make a separate `patch_vault_file` call targeting `Last Night's Reflection`.

**Populated shape** (when `evening.found == true`):

```markdown
### Last Night's Reflection
> **Previous Evening**: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD|Last Night's Evening]]
> - **Key insight**: <one-sentence pull from evening.content>
```

**Empty-state shape** (when `evening.found == false`):

```markdown
### Last Night's Reflection
> **Previous Evening**: NO EVENING ENTRY
> - **Key insight**:
```

- `YYYY-MM-DD` is yesterday's date — `dates.yesterday` from the gather output.
- Source for the populated Key insight: `evening.content`.
- The empty-state sentinel `NO EVENING ENTRY` is in literal caps — easy to grep, impossible to skim past. The `Key insight:` line stays present with empty value so the slot is structurally identical to the populated shape. **Do not render** `> *No evening reflection from last night*` — that soft form is deprecated.
- **Only the Key insight is retained.** Drop Mood and Gratitude — both are one click away via the Previous Evening link.

### 4c: Link Resolver Rules — applies to every wikilink in the payload

Wikilink resolution is a frequent source of broken links. Follow these three rules before emitting any `[[...]]`. See Start-Day Iteration Findings 5-15 §4 for failure cases.

**Class A — Area wikilinks use basenames, not numeric-prefixed folders.**

Area dashboard files live at `3. Areas/{NumericFolder}/{AreaName}.md` (e.g. `3. Areas/1. {WorkArea}/{WorkArea}.md`). The basename is the area name, **not** the numeric-prefixed folder.

| Area | ❌ Wrong | ✅ Right |
|---|---|---|
| {WorkArea} | `[[1. {WorkArea}\|{WorkArea}]]` | `[[{WorkArea}]]` |
| {SideArea2} | `[[2. {SideArea2}\|{SideArea2}]]` | `[[{SideArea2}]]` |
| {SideArea} | `[[3. {SideArea}\|{SideArea}]]` | `[[{SideArea}]]` |
| Health & Fitness | `[[4. Health & Fitness\|Health]]` | `[[Health & Fitness\|Health]]` |
| Personal-Finance | `[[5. Personal-Finance\|Personal-Finance]]` | `[[Personal-Finance]]` |
| Personal | (root folder, no numeric prefix) | `[[Personal]]` |

**Rule:** Numeric folder prefixes are filesystem-only. They never appear in wikilinks.

**Class B — Basename collisions force a full-path alias.**

When two project hubs share a basename (e.g. `2. Projects/2. {SideArea2}/Finances/Finances.md` and `2. Projects/5. Personal-Finance/Finances/Finances.md`), a bare `[[Finances]]` is ambiguous. Detect collisions by scanning `active_projects[*].hub_path` basenames for duplicates; for any colliding entry, use the full path with an alias:

```markdown
[[2. Projects/2. {SideArea2}/Finances/Finances|{SideArea2} Finances]]
[[2. Projects/5. Personal-Finance/Finances/Finances|Personal-Finance Finances]]
```

**Class C — Project hub wikilinks come from `hub_path`, not synthesis.**

For every project, read the hub filename from `active_projects[i].hub_path` and use **that** basename as the wikilink target. Never synthesize from the project slug or display name — slugs may be hyphenated (`copilot-studio`) while the hub file may be `Copilot-Studio.md`, and the display name may have spaces that don't exist in the filename.

Procedure:
1. For each entry to render, find its `active_projects[i]` row by slug match on the file's `project:` frontmatter.
2. Take `hub_path` from that row, strip the `.md` extension, strip the directory prefix — the result is the wikilink target.
3. If two `hub_path` basenames collide (Class B), emit the full path form instead.

If no `active_projects[]` row exists for a slug (rare — usually a private project filtered out), skip the link rather than synthesizing one.

### 4d: Build the atomic payload and emit one patch

The full Recent Accomplishments payload, in order:

1. Window header line: `> **Recap Window**: M/D → M/D · N day(s) had no captured work (M/D, M/D)` (or the `beyond_lookback` escape-hatch line).
2. `### What Moved Forward` (omit if no entries).
3. `### What Changed Structurally` (omit if no entries).
4. `### Needs Attention` (omit if no entries).
5. `### Last Night's Reflection` (always rendered — populated or sentinel; see 4b).

Use MCP patch — **one call**:

```python
mcp__obsidian-mcp-tools__patch_vault_file(
    filename="5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md",
    operation="replace",
    targetType="heading",
    target="Recent Accomplishments",
    content="<window header + three H3 subsections + Last Night's Reflection H3>"
)
```

The patch replaces everything under `## Recent Accomplishments` up to the next `## ` boundary (the `---` divider before `## Tasks Overview`), so the entire block is rewritten atomically.

### 4e: Post-render link audit

After the patch lands, run the link audit script to verify every wikilink in the rendered journal resolves to exactly one vault file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/audit_journal_links.sh TARGET_DATE
```

The script parses every `[[...]]` in the rendered Recent Accomplishments block and reports:
- ✅ resolves to exactly one file
- ❌ broken — no file matches
- ❌ ambiguous — multiple files match

If any link fails, **do not report success** in Step 6. Surface the failed links in the execution report and re-render with the link resolver rules (4c) applied correctly.

### 4f: Daily hub

`/start-day` does NOT write to the daily hub. The daily hub's `**Today's priorities:**` placeholder (`- [ ] ...`) stays until `/process-journal` fills it after the morning meeting.

Do not touch the daily hub file in Step 4.

### 4g: Orphan Cluster Detection (Retroactive Devlog Proposal)

After the atomic patch in 4d lands, scan the recap window for **orphan clusters** — multiple orphan notes from the same date and same project that look like one uncaptured session. Propose a retroactive devlog interactively so tomorrow's recap stops flagging them.

**Cluster detection rules** (operate on `recap_window.days[].notes` where `orphan_candidate == true`):

1. Group orphan notes by `(date, project)` tuple.
2. For each group with **3+ orphan notes** → propose a retroactive devlog (high signal: this is almost certainly one session).
3. For groups with 1–2 orphan notes → leave the `[?]` flag, do NOT propose (insufficient signal).
4. Skip area-only notes entirely (they have no `project`, so `orphan_candidate` is always false — they never reach this step).
5. Skip the **target date** itself (today). The journal is being written *now* — those notes will be covered as the day's devlogs land. Only propose for past dates in the window.

**For each cluster (one batch of proposals, then per-cluster confirm):**

Synthesize the proposal from the note titles, project, and a quick read of each note (use `obsidian read path=...` if titles aren't enough — keep it under 30s of reading per cluster). The title should be **session-shaped** (verb-first or theme-first), not a list of every note. Examples:

- 6 notes about {Project} vocabulary, hierarchy, lane-based hub on 5/5 → `2026-05-05 - {Project} Vocabulary Lock — Four Layers, Lane-Based Render, Idea Ranch`
- 3 notes about Hermes pilot wiring on 5/4 → `2026-05-04 - Hermes Pilot B Prep — Skill Portability and Heartbeat Wiring`

Present each cluster like this and ask the user to confirm:

```
Detected orphan cluster: 6 notes from 2026-05-05 (project: {project-slug})

Notes:
  - [[Commitment Lifecycle and Daily Render — Vocabulary and Data Flow]]
  - [[Solo Founder Hierarchy — Four Layers Beats Six]]
  - [[Goal Initiative Project Task — Glossary for Solo Founder Operating System]]
  - [[Idea Ranch — AI-Shepherded Idea Pipeline]]
  - [[Initiative — Two Meanings in Current Vault and How to Resolve]]
  - [[{Project} Lane-Based Daily Hub Architecture — Process-Journal v2 Proposal]]

Proposed retroactive devlog:
  Title:   2026-05-05 - {Project} Vocabulary Lock — Four Layers, Lane-Based Render, Idea Ranch
  Project: {project-slug}
  Area:    rs42
  Tasks:   (none — design session)
  Body:    wikilinks to all 6 notes + 1-line brief per note
```

Use `AskUserQuestion` (or equivalent interactive prompt) with options:
- **Create** — write the devlog as proposed
- **Edit title** — let the user supply a different title, then create
- **Skip** — leave the cluster as orphans (the user already accepts this)

**On Create:**

1. Resolve the prior {project-slug} devlog (last devlog before the cluster date) and the next {project-slug} devlog (first devlog after the cluster date) for chain-linking. Prefer:
   ```bash
   obsidian search "type: devlog project: <slug>" --limit 50
   ```
   then sort by date and pick the immediate neighbors. QMD is a backup.

2. Write the devlog file at `2. Projects/{Area}/{Project}/Dev Log/{Title}.md` using the Devlog Template's frontmatter shape:
   ```yaml
   ---
   date: <cluster-date>
   type: devlog
   status: capture
   area: <area>
   project: <slug>
   session_topic: <verb-first description derived from title>
   tasks: []                # design session — no task link
   tags: [devlog]
   ---
   ```

3. Body content (concise — this is a retroactive reconstruction, not a fresh log):
   ```markdown
   # <Title>

   > **Project**: [[Project Hub]]
   > **Previous <project> devlog**: [[<prior devlog title>]]
   > **Next <project> devlog**: [[<next devlog title>]]
   > **Note**: Retroactively reconstructed by /start-day on <today> from an orphan cluster — the session happened but no devlog was written at the time.

   ## Notes produced this session

   - [[<note 1 title>]] — <1-line brief from note's first paragraph or its own callout>
   - [[<note 2 title>]] — <1-line brief>
   - ...

   ## Why retroactive

   These N notes share `date: <cluster-date>` and `project: <slug>` with no covering devlog. They cross-link and read as one design session. This devlog closes the orphan loop so tomorrow's recap groups them under their session intent.
   ```

4. Update the **next** devlog's `Previous:` link if it currently points to the prior devlog (now there's a new one in between). Same for the prior's `Next:` link if it pointed forward to the next. Use `obsidian property:set` or a small inline edit.

5. Confirm to the user: `Created [[<Title>]] — N orphans now covered.`

**On Edit title:** prompt for new title (single line), then proceed with steps 1–5 using the new title.

**On Skip:** move on to the next cluster.

**After all clusters processed:** report a one-liner summary in Step 6's execution report (e.g., `- Orphan clusters: 2 detected, 1 created, 1 skipped`).

## Step 5: Linear → Todoist Sync

For each Linear issue at the **task level** (not user stories), check if a Todoist mirror exists:

```bash
td task list --filter "search:RS4-xxx" --json
```

If no mirror exists, propose creation (batch — show all proposed tasks, then create):

```bash
td task add "Verb-first description (Linear RS4-xxx)" --project "{SideArea2}" --labels "@{sidearea2-slug}" --priority p2
```

**Naming**: Use the Linear title if verb-first and specific. Rewrite vague titles.
**Completion**: Todoist leads, external systems follow. If Linear shows Done but the Todoist mirror is open, flag it: `*(Linear RS4-xxx, resolved upstream — close?)*`

## Step 5b: Commit the Daily Scaffold

Snapshot the day's starting state in the vault git repo so the morning-entry recording that follows shows up as a distinct modification in git history (`/vault-commit`'s nightly pass would otherwise fold scaffold and morning entry into one commit):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/start-day/scripts/commit_daily_scaffold.sh TARGET_DATE
```

The script commits **only** the daily hub (`1. Daily/TARGET_DATE.md`) and the morning journal entry (`5. Resources/Personal/Journal/Morning Entries/TARGET_DATE.md`) with the message `chore: start-day scaffold for TARGET_DATE`. Everything else dirty in the vault (private stamps, orphan-cluster devlogs from 4g, unrelated edits) is left for `/vault-commit`.

Parse the JSON output:
- `{committed: true, sha, ...}` — report the commit in Step 6's execution report.
- `{committed: false, reason: "no_changes"}` — re-run with nothing new; report as skipped, not a failure.
- `{committed: false, error: "..."}` — the commit failed. **Warn, don't abort**: continue to Step 6 and surface the error in the Warnings section. The journal page is already prepped; a missed snapshot must not block the morning meeting.

## Step 6: Report Results

Merge the gather script's `source_manifest` with MCP tool results into a unified execution report (per `vault-config/references/source-manifest.md`):

```markdown
Morning prep complete for YYYY-MM-DD.

**Yesterday**: N devlog sessions
**Carry-forward**: N tasks (M overdue)

Journal page prepped → [[5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD]]
Ready to record your morning journal.

---
### Execution Report
#### Sources
- [x] Obsidian CLI — journal read, daily hub read, N devlogs found
- [x] Todoist overdue/today — N items
- [ ] GWS Calendar — FAILED: auth token expired
- [x] Linear in-progress — N items
- [x] QMD Search — backup search, N results
- [x] Evening reflection — found
- [x] Scaffold commit — abc1234 `chore: start-day scaffold for YYYY-MM-DD`

#### Warnings
- GWS integration unavailable. Run `gws auth login` to refresh.
- N devlogs found with no task linked.

#### Fix
- GWS: Run `gws auth login` to refresh OAuth token
```

Only include Warnings and Fix sections if there are actual issues. Script-tracked sources use `source_manifest` values; MCP-tracked sources (Linear, QMD) use your own tracking from Step 2.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Single-day window (yesterday only) | Render window header + three-section brief (What Moved Forward / Changed Structurally / Needs Attention) — omit any empty subsection |
| Multi-day window with gaps (e.g. Mon after long weekend) | Render window header summarizing gap days, then the three-section brief synthesized across the whole window — no per-day subsections |
| 4-day offline (3-day tier finds nothing, 5-day finds work) | Tiered lookback handles automatically — window extends to 5 days back |
| Full week off (5-day finds nothing, 7-day catches it) | Tiered lookback handles automatically — window extends to 7 days back |
| Beyond 7 days idle (`beyond_lookback: true`) | Render escape-hatch message with `--since` invocation hint; skip the three-section brief |
| Day in window has only journal/daily/private files | Day appears in `days_empty`, not rendered as a section |
| Knowledge note exists but no covering devlog (orphan) | Appears as a `- [?]` sub-bullet under its project's parent bullet in What Moved Forward, with the `*(orphan note — no devlog covered this)*` suffix |
| Private project files | Silently excluded by gather script + per-file `private: true` stamp written to file frontmatter (one-way) |
| No Todoist tasks | "No overdue tasks" |
| Linear unavailable | Continue — note in source manifest |
| Journal already has context | Replace existing context (re-run safe) |
| Re-run with no scaffold changes since last commit | Step 5b skips with `reason: no_changes` — no duplicate commit |
| Re-run that changed the rendered context | Step 5b commits a fresh snapshot (same message) — legitimate, not a duplicate |
| Scaffold commit fails (merge in progress, locked index) | Warn in execution report, do not abort — journal page is already prepped |

## What This Skill Does NOT Do

- Extract priorities from journal transcript (that's `/process-journal`)
- Create Todoist tasks from journal content (that's `/process-journal`)
- Process voice transcripts
- Complete Linear items (reads state, mirrors to Todoist)
- Does not write task lists to the journal or daily hub (Bases queries in the template render tasks from `type: task` frontmatter)
- Does not create task notes (that's `/process-journal`)
- Does not commit anything beyond the day's scaffold (hub + morning journal) — `/vault-commit` owns all other commits
