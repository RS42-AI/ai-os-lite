---
date: 2026-05-09
type: task
status: todo
area: personal
project: vault-setup
priority: p2
due_date: ""
scheduled_date: ""
done_date: ""
blocked_by: []
blocked_reason: ""
unlocks:
  - "[[Set up my first goal]]"
external_id: ""
tags:
  - task
  - onboarding
---

# Add my first project

## Why

The fastest way to learn the hub-and-spoke architecture is to use it. Choose a real or clearly fictional example — a trip, a course, a side project — and practice with a project hub for it. This manual exercise is optional; `setup-context` offers a guided conversation from an outcome instead. By the end, you'll know how `type`, `area`, and `project` route content, and your area dashboard will start auto-populating.

## Steps

### 1. Pick a project

Choose something concrete that has more than one task and will run for at least a few weeks. Examples that work well as a first project:

- A trip you're planning
- A learning goal (e.g. learn Spanish, finish a course)
- A side project (e.g. build a website, write a book)
- A life project (e.g. find a new apartment, train for a 5K)

Avoid: anything that fits in one sitting (just make a task instead) or anything purely exploratory with no defined outcome.

### 2. Decide which area it belongs to

Areas are ongoing responsibilities. Read `AGENTS.md` at the vault root for your configured list; the personal starter contains `personal`. Other areas are choices to discuss, not preconfigured values. Adding one requires an exact instruction-change preview and your separate decision.

The current starter structure uses `Personal/2. Projects/{Project-Name}/` for personal projects and `2. Projects/{Area}/{Project-Name}/` for work or business projects. The carried instruction template still differs in places: if its routing conflicts, resolve that wording with a human before creating the project. Do not silently choose between contradictory rules.

### 3. Create the project folder structure

```
{Area-Folder}/{Project-Name}/
├── {Project-Name}.md          ← project hub
├── Notes/                     ← knowledge notes for this project
├── Tasks/                     ← actionable work items
├── Resources/                 ← reference material
├── Artifacts/                 ← working documents and other outputs
├── Specs/                     ← project design specifications
└── Dev Log/                   ← session-by-session work logs
```

### 4. Create the project hub

Open the `{Project-Name}.md` file at the project root. Use the `Project Hub Template` (in `system-settings/Templates/`) as a starting point. The minimum frontmatter:

```yaml
---
date: <today's date>
type: project
status: draft
area: <your area>
project: <your-project-slug>
goal:
---
```

Use lowercase words separated by hyphens for the slug, such as `example-project` or `summer-trip`.

### 5. Add one task and one devlog

If you choose to complete this manual exercise:

- Create one task in `{Project-Name}/Tasks/` — pick the very next thing to do
- Create one devlog in `{Project-Name}/Dev Log/` — capture today's session, even if it was just "set up the project"

The notes and their properties provide context directly to your assistant. If you use Obsidian, the hub's dashboard views can display them automatically.

## Done when

- [ ] Project folder exists at the right path for its area
- [ ] All six project containers exist, even when some are empty
- [ ] Project hub `.md` file has correct frontmatter
- [ ] At least one task exists in `Tasks/`
- [ ] At least one devlog exists in `Dev Log/`
- [ ] The task and devlog can be found from their project context; optionally check the dashboard views in Obsidian

## See also

- `AGENTS.md` (vault root) — Decision Tree and frontmatter taxonomy
- [[AI Workstation Organization - Filesystem and Vault Mapping Architecture]]
- [[Vault-Setup]] — back to the orientation hub
