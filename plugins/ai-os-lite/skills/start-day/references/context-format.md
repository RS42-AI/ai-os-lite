# Context Format Rules

Format rules for the morning context written to the journal page.
Read this file when interpreting gathered data from `gather_morning_context.sh`.

## Journal Page Context

`/start-day` writes **only two sections** into the Morning Brief, replacing placeholders via MCP `patch_vault_file` with `operation="replace"`, `targetType="heading"`.

### Recent Accomplishments

Target heading: `Recent Accomplishments` (H2, with three H3 subsections — `What Moved Forward`, `What Changed Structurally`, `Needs Attention`).

Render: the three-section operational brief — **not** a flat bullet list. See **Three-Section Brief Format** below for routing, ordering, and prose rules. SKILL.md Step 4a is the source of truth for the exact render mechanics; this file documents the routing logic and conventions for reference.

### Last Night's Reflection

Target heading: `Last Night's Reflection` (H3 — structurally a subsection under `## Recent Accomplishments`; the patch-target text is still `Last Night's Reflection`).

A single blockquote containing the Previous Evening link and one Key insight line — nothing else.

**Populated shape** (when `evening.found == true`):

```markdown
> **Previous Evening**: [[5. Resources/Personal/Journal/Evening Entries/YYYY-MM-DD|Last Night's Evening]]
> - **Key insight**: Traced workplace anxiety to early career layoffs
```

**Empty-state shape** (when `evening.found == false`):

```markdown
> **Previous Evening**: NO EVENING ENTRY
> - **Key insight**:
```

Rules:
- `YYYY-MM-DD` is yesterday's date — from `dates.yesterday` in the gather output.
- The Key insight is one sentence distilled from `evening.content` (last night's Evening Entry AI Summary when available).
- **Only the Key insight is retained.** Personal reflection details remain one click away via the Previous Evening link and are not copied into the Morning Brief.
- The empty-state sentinel `NO EVENING ENTRY` is in literal caps — easy to grep, impossible to skim past. The `Key insight:` line stays present with empty value so the slot is structurally identical to the populated shape.

### Task Visibility (NOT written by /start-day)

Tasks are rendered by the `## Tasks Overview` section's Bases queries in the template (To Do / On Hold / Recently Completed). The skill does NOT write any task lists. Task discovery in `gather_morning_context.sh` is used for the AI's contextual awareness only (e.g., warning about WIP counts), not for rendering.

## Daily Hub Sections

`/start-day` does not write to the daily hub. The `## Morning Brief` placeholder remains until `/process-morning` fills it after optional human input.

## Area-to-Wikilink Mapping

Resolve the frontmatter `area:` slug to the area dashboard basename. The dashboard file lives at `3. Areas/{NumericFolder}/{Basename}.md` (or `Personal/Personal.md` for the personal area) — link by **basename**, never by the numeric-prefixed folder. See SKILL.md §4c Class A.

| Frontmatter `area:` | Wikilink |
|----------------------|----------|
| `{workarea-slug}` | `[[{WorkArea}]]` |
| `{sidearea2-slug}` | `[[{SideArea2}]]` |
| `{sidearea-slug}` | `[[{SideArea}]]` |
| `health` | `[[Health & Fitness\|Health]]` |
| `personal-finance` | `[[Personal-Finance]]` |
| `personal` | `[[Personal]]` |
| `career` | `[[Career]]` |

## Project Hub Wikilinks — read `hub_path`, never synthesize

Do **not** maintain a hardcoded slug → wikilink mapping in this file (slugs and hub filenames drift; the mapping rots silently). Instead, every project hub wikilink is derived from `gather_morning_context.sh` output:

1. Find the file's `project:` slug.
2. Look up the matching row in `active_projects[]` (or `hot[]`/`warm[]`/`cold[]`) by slug.
3. Strip the directory prefix and `.md` extension from `hub_path` — the result is the wikilink target basename.
4. If two `hub_path` basenames collide across `active_projects[]`, render the full path form with an alias: `[[2. Projects/{Area}/{Project}/{Project}|{Disambiguated Name}]]`.

If a slug has no `active_projects[]` row, skip the link — almost always a private project filtered out of the gather output. See SKILL.md §4c Class B + Class C.

## Three-Section Brief Format

The render of `## Recent Accomplishments` is a three-section operational brief: `### What Moved Forward`, `### What Changed Structurally`, `### Needs Attention` (all H3). Omit any subsection that would be empty. SKILL.md Step 4a is the source of truth for the exact bullet templates; this section documents the routing logic and prose conventions.

### Section selection rules

Each piece of gathered evidence routes to exactly one section:

| Section | Evidence source | Inclusion rule |
|---|---|---|
| What Moved Forward | `commits[]` + `recap_window.days[].devlogs[]` | Commits where `kind ∈ {docs, feat, fix}`, plus all devlogs in the window, grouped by project. |
| What Changed Structurally | `commits[]` | Commits where any path in `files[]` matches a structural pattern: project hubs (`2. Projects/*/{Project}/{Project}.md`, `Personal/*/*.md` where filename = folder name), goal hubs (`3. Areas/*/Goals/*.md`), new project scaffolds, vault config (`CLAUDE.md`, `AGENTS.md`, `system-settings/Templates/*`). |
| Needs Attention | `warm[]` + `cold[]` (banded, H4 sub-sections) | Hot suppressed (0–3d); render Warm then Cold. See SKILL.md §4a. |

A commit can appear in both Moved Forward and Changed Structurally — the commit subject summarizes session work (Moved Forward) while the structural files it touched (Changed Structurally) are the scaffolding evidence.

### Bullet shape — nested project-then-items

Each project gets a **bare parent bullet** with no inline body, then **one tab-indented sub-bullet per distinct work item** (commit cluster or devlog session):

```markdown
- **[[Area]] / [[Project Hub]]**
	- Work item one — concise factual description from commit subjects + devlog session_topics.
	- Work item two — …
```

- The parent bullet is bare — all content goes in sub-bullets. Do not merge sub-bullets into a single run-on sentence.
- Area-level work (frontmatter has `area:` but no `project:`) uses a bare parent `- **[[Area]]** *(area-level)*` with sub-bullets underneath — same nested shape.
- `### What Changed Structurally` uses the same shape: a bare area parent, structural changes as sub-bullets.
- **Orphan notes** (a knowledge note with no covering devlog in its project on the same date) render as a `- [?]` **sub-bullet** under their project's parent bullet in What Moved Forward, with the `*(orphan note — no devlog covered this)*` suffix. They are never standalone top-level bullets.
- Notes from a project where a same-day devlog in the same project exists are NOT rendered separately — the devlog already represents that session.

### Ordering

Within every subsection, sort by `area_priority_rank` ascending (primary key — emitted by `gather_morning_context.sh` on `active_projects[]`, `hot[]`, `warm[]`, and `cold[]` entries; `1={workarea-slug}, 2=rs42, 3={sidearea-slug}, 4=personal, 5=personal-finance/finance, 6=health, 7=career, 99=unknown`). For commit/devlog-derived entries, resolve the rank from the entry's `area` via the same mapping. Per-subsection secondary key:
- **What Moved Forward**: within an area, area-level entries before project entries; project entries in any stable order.
- **What Changed Structurally**: within an area, no specific secondary order.
- **Needs Attention**: within each band, sort by `area_priority_rank` ascending; secondary sort is `days_silent` ascending in Warm (freshest first), `days_silent` descending in Cold (longest-silent first).

Area priority outranks the secondary key — a 38-days-silent {SideArea} project sorts below a 34-days-silent {SideArea2} project.

### Prose synthesis rules

- Drop conventional commit prefixes (`docs:`, `feat:`, `fix:`, `chore:`, `refactor:`) when reading commit subjects into prose.
- A *commit cluster* is two or more commits from the same project that share a theme or touch the same subsystem — render them as one sub-bullet. Commits in the same project addressing genuinely distinct work each get their own sub-bullet.
- Anchor each parent bullet with the project hub wikilink (resolved from the file's `project:` slug via the mapping above).
- Tone is direct and factual. No celebration language ("Great work", "Crushed it", "Excellent"). State what happened.

### Recency Bands

Active projects are banded by `days_silent` after the (C)+(D) recency rule from [[Project Last-Touch Computation — What Counts as Activity for Recency Bands]]:

| Band | Threshold | Render |
|------|-----------|--------|
| Hot  | 0–3 days  | Suppressed (data only) |
| Warm | 4–13 days | H4 sub-section of Needs Attention |
| Cold | ≥14 days  | H4 sub-section of Needs Attention |

Each band entry has the shape:

```json
{
  "slug": "{project-slug}",
  "area": "{sidearea2-slug}",
  "hub_path": "2. Projects/2. {SideArea2}/{Project}/{Project}.md",
  "last_activity_date": "2026-05-14",
  "days_silent": 2,
  "area_priority_rank": 2,
  "recency_source": "in-project" | "plan" | "none",
  "plan_path": "docs/superpowers/plans/<file>.md",  // when recency_source == "plan"
  "latest_in_project_age_days": 8                  // when recency_source == "plan" and an in-project file exists
}
```

Cold entries additionally carry a `reason` string for the render template.

**Rule C (in-project subtree):** Walk every `.md` under the project's folder (`2. Projects/<area>/<project>/**` or `Personal/<project>/**`) with a `date:` frontmatter; take the max date.

**Rule D (plan-file enrichment):** Walk `docs/superpowers/plans/*.md`; for each plan, resolve its target project via `project:` frontmatter (preferred) or filename-slug suffix match against active project slugs (fallback, longest-slug-first). Use the plan's `date:` or filename `YYYY-MM-DD-` prefix.

**Combine:** `last_activity_date = max(rule_C, rule_D)`. When rule D wins, set `recency_source: "plan"` and record `plan_path`; if an in-project file also exists, record its age in `latest_in_project_age_days` so the render can say "latest in-project file is Md old".

**When neither rule produces a date**, the project still emits in `cold[]` with `last_activity_date: "never"`, `days_silent: 999`, `recency_source: "none"`, and a "no devlog or knowledge note in this project folder" reason. **Consumer contract:** branch on `recency_source == "none"` before reading `last_activity_date` or `days_silent` — both are sentinels in that case.

### Worked example

One bullet from each section, with the evidence that produced it:

**What Moved Forward** — nested shape, project parent + work-item sub-bullets:
```markdown
- **[[{WorkArea}]] / [[{Project}]]**
	- Locked the wheel architecture: Areas → Goals → Projects → Tasks → Devlogs/Notes, with frontmatter as the API and Bases as the view layer.
	- Produced the audit-and-backfill plan and documented the `/start-day` orphan-render bug.
```
Evidence: multiple `docs:` commits touching `2. Projects/{WorkArea}/{Project}/Notes/*.md` + same-window devlogs in `2. Projects/{WorkArea}/{Project}/Dev Log/`. Two distinct work clusters → two sub-bullets; commit prefixes dropped.

**What Changed Structurally** — bare area parent + structural sub-bullets:
```markdown
- **[[{SideArea2}]]**
	- Added `2026-Q2` and `2026-Annual` goal hubs in `3. Areas/{SideArea2}/Goals/`. Goal layer of the wheel is now scaffolded.
```
Evidence: a commit with files matching `3. Areas/{SideArea2}/Goals/*.md`.

**Needs Attention**:
```markdown
- **[[{SideArea2}]] / [[{Project}]]** — `status: active` but no devlog or knowledge note dated within 14 days. Last touched 2026-04-12 (33 days ago).
```
Evidence: `cold[]` entry with `slug: {project-slug}`, `days_silent: 33`, `area_priority_rank: 2`, `reason: "no devlog or knowledge note dated within 14 days"`.
