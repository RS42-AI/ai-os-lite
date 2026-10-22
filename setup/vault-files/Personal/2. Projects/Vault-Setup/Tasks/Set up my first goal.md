---
date: 2026-05-09
type: task
status: todo
area: personal
project: vault-setup
priority: p3
due_date: ""
scheduled_date: ""
done_date: ""
blocked_by:
  - "[[Add my first project]]"
blocked_reason: "For this optional manual exercise, choose a real or fictional project first"
unlocks:
  - "[[Set up my AGENTS.md]]"
external_id: ""
tags:
  - task
  - onboarding
---

# Set up my first goal

## Why

A project without a goal is just a list of activity. Goals give projects a *reason* — an outcome you're trying to reach by a specific date — and let the system surface what actually matters when you're triaging tasks.

This optional exercise uses an objective and measurable signals of progress. The starter template includes three Key Result slots. Fill only measures you actually choose; do not invent commitments to complete a template. If your instruction rules require more than you have chosen, keep the goal as a conversational proposal until you resolve that rule.

## Steps

### 1. Pick the area and the time horizon

Business-area goals live at `3. Areas/{Area}/Goals/{Goal Name}.md`; personal goals live at `Personal/1. Goals/{Goal Name}.md`. Two common horizons:

- **Quarterly** — `2026-Q2.md`, `2026-Q3.md`, etc. — what you want to accomplish in the next 90 days. Best for active work areas.
- **Annual** — `2026-Annual.md` — bigger-picture outcomes for the year. Best for life areas (health, finances, career).

If the shipped instructions conflict with these goal destinations or the template, pause saving for a human instruction decision. For this manual exercise, pick the area where your chosen project lives. If it's a personal-life project, use `Personal/1. Goals/`. If it's a work project, use the matching work area under `3. Areas/{Area}/Goals/`.

### 2. Create the goals file

If the file doesn't exist yet (for example, `Personal/1. Goals/Improve My Health.md`), create it. Use the `Goal Hub Template` from `system-settings/Templates/`. The minimum frontmatter:

```yaml
---
date: <today's date>
type: goal
status: active
area: <your area>
period: quarterly
horizon: 2026-Q2
tags:
  - goal
---
```

### 3. Write the Objective

One sentence. Aspirational but bounded by the horizon. It should answer: *what does success look like at the end of this quarter / year?*

Examples (these are illustrative — yours will be specific to you):

- *"Have a working rhythm of three workouts per week and feel physically stronger than I did at the start of the quarter."*
- *"Move from job-searching to a signed offer in a role I'm excited about."*
- *"Complete the first phase of the home-buying process — pre-approved, agent chosen, two offers made."*

### 4. Choose useful measures

Use a measurable signal that shows whether the objective happened. A number or a clear yes/no outcome can help.

Bad: *"Make progress on home buying"*
Good: *"Submit at least 2 offers by end of Q2"*

Choose measures that fit the outcome. A fictional example is allowed and should remain clearly labeled as an example. No personal goal is required to finish installing the workspace.

### 5. Link the goal from your project hub

Open your project hub and update the frontmatter:

```yaml
status: active
goal: "[[Improve My Health]]"
```

This wikilink lets the area dashboard show your project as "linked to this goal" automatically.

A draft project may keep `goal:` empty while you define it. Changing the project to `active` requires this resolving goal link.

## Done when

- [ ] Goal file exists under `Personal/1. Goals/` or `3. Areas/{Area}/Goals/`
- [ ] Frontmatter has `type: goal`, `area`, `period`, `horizon`
- [ ] Objective is one clear sentence
- [ ] Chosen measures are useful and agree with the applicable instructions; unresolved choices remain proposals
- [ ] Your project hub is `active` and its `goal:` frontmatter resolves to the goal file

## See also

- `AGENTS.md` (vault root) — Goal frontmatter spec (field shapes live in `system-settings/Templates/`)
- [[Add my first project]] — the project this goal anchors to
- [[Vault-Setup]] — back to the orientation hub
