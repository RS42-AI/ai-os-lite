# AI-OS Lite

**An AI Personal Operating System** — a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that turns an [Obsidian](https://obsidian.md) vault into an AI-operated daily workflow: morning briefings, voice-journal processing, evening reflection, task orchestration, and project status — all driven by your own notes.

AI-OS Lite reads and writes your vault, syncs work items to [Todoist](https://todoist.com) and [Linear](https://linear.app), and keeps your daily/project hubs current. It's the engine behind a frontmatter-routed, AI-navigable knowledge system.

> Built by [RandomStateLabs](https://github.com/RandomStateLabs). AI-OS Lite is the open, public edition of the AI-OS system.

## What it does

Seven skills, invoked by natural language or slash commands:

| Skill | What it does |
|-------|-------------|
| `start-day` | Morning prep — writes a "Yesterday" recap + today's context to your journal before you record |
| `process-journal` | Processes a morning journal entry — extracts summary, mood, priorities, people; pushes priorities to Todoist |
| `prep-evening` | Evening prep — writes the day's accomplishments and a wind-down prompt |
| `process-evening` | Processes an evening entry — mood, habits, gratitude, tomorrow's tasks, pattern detection |
| `project-sync` | Refreshes a project hub's status from recent devlogs, notes, and Linear |
| `vault-commit` | Groups uncommitted vault changes into clean semantic git commits |
| `vault-config` | Shared operational config — tool patterns, integrations, search strategy (not user-invoked) |

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code)
- An Obsidian vault following the AI-OS frontmatter conventions (see `AGENTS.md` in your vault — the plugin reads your vault's structure, taxonomy, and project identity from there)
- Optional integrations: [Todoist CLI](https://github.com/sachaos/todoist) (`td`), [Linear MCP](https://linear.app/docs/mcp), Obsidian local REST API

## Install

```bash
# Add this marketplace
claude plugin marketplace add RandomStateLabs/ai-os-lite

# Install the plugin
claude plugin install ai-os-lite@ai-os-lite-marketplace
```

Then configure your vault path and conventions in your vault's `AGENTS.md`. The plugin substitutes your real areas, projects, contacts, and work-item prefixes from there at runtime — the skill examples ship with generic `{WorkArea}` / `{Project}` / `{Contact}` placeholders that resolve to *your* data.

## Configuration

AI-OS Lite is **per-user generic by design**. It contains no hardcoded names, employers, or projects — every example uses a `{Placeholder}` token that the model fills from your `AGENTS.md` at output time:

- `{WorkArea}` / `{SideArea}` → your areas
- `{Project}` → your projects (read from your vault filesystem)
- `{Contact}` → people in your `4. Contacts/People/`
- `{TICKET}` → your Linear team prefix

If a placeholder can't be resolved (no work area, no projects, no Linear team), the relevant example is simply omitted. Nothing breaks.

## Licensing

**AI-OS Lite is licensed under the [GNU AGPL v3.0](./LICENSE).**

In plain terms:

- ✅ **Free to use** for personal and internal use — install it, run it on your own vault, modify it for yourself, no obligations.
- ✅ **Free to study and modify** — the source is open.
- ⚠️ **If you modify AI-OS Lite and offer the modified version to others as a network service**, AGPL requires you to make your modified source available to those users under the same license. (Normal personal use never triggers this.)
- ❌ **You may not** take this code, fold it into a closed/proprietary product, and distribute or host it for others without complying with the AGPL — or obtaining a separate commercial license.

### Commercial licensing

Want to use AI-OS Lite in a way the AGPL doesn't permit — embedding it in a proprietary product, offering it as a hosted commercial service without open-sourcing your changes, or any other commercial arrangement? **A commercial license is available.**

Contact **RandomStateLabs** → [github.com/RandomStateLabs](https://github.com/RandomStateLabs) to discuss terms.

> Copyright © 2026 Yandi Farinango / RandomStateLabs. "RandomStateLabs", "AI-OS", and "AI-OS Lite" are names of the project authors; AGPL §7 does not grant trademark rights to use them to endorse or promote derived works.

### Contributing

Contributions are welcome. Because AI-OS Lite is offered under AGPL **and** a separate commercial license, contributors will be asked to agree to a Contributor License Agreement (CLA) granting RandomStateLabs the right to license contributions under both — this is what keeps the dual-licensing model legally sound. (CLA process to be published alongside the first external contribution.)
