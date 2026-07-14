# AI-OS Lite

**An AI operating system for focused human-agent work** — a plugin for Claude Code and Codex that turns an [Obsidian](https://obsidian.md) vault into an AI-operated daily workflow: executive Morning Briefs, optional free-form input, task orchestration, evening preparation, and project status — all grounded in your own notes.

AI-OS Lite reads and writes your vault, syncs work items to [Todoist](https://todoist.com) and [Linear](https://linear.app), and keeps your daily/project hubs current. It's the engine behind a frontmatter-routed, AI-navigable knowledge system.

> Built by [RandomStateLabs](https://github.com/RandomStateLabs). AI-OS Lite is the open, public edition of the AI-OS system.

## What it does

Eight skills, invoked by natural language, Claude Code slash commands, or Codex `$skill-name` references:

| Skill | What it does |
|-------|-------------|
| `start-day` | Prepares an executive Morning Brief from recent work, current tasks, meetings, risks, and open decisions |
| `process-morning` | Processes optional Morning Brief input into a private summary, committed daily plan, and approved task actions |
| `prep-evening` | Prepares an optional Evening Entry with accomplishments, tomorrow preview, wind-down, and Still Open work |
| `process-evening` | Processes optional free-form evening input; gratitude and personal habits are never required |
| `project-sync` | Refreshes a project hub's status from recent devlogs, notes, and Linear |
| `vault-commit` | Groups uncommitted vault changes into clean semantic git commits |
| `vault-audit` | Deterministic conformance audit of your vault's structure against its own `AGENTS.md` contract |
| `vault-config` | Shared operational config — tool patterns, integrations, search strategy (not user-invoked) |

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) or [Codex](https://developers.openai.com/codex/)
- An Obsidian vault following the AI-OS frontmatter conventions (see `AGENTS.md` in your vault — the plugin reads your vault's structure, taxonomy, and project identity from there)
- Optional integrations: [Todoist CLI](https://github.com/sachaos/todoist) (`td`), [Linear MCP](https://linear.app/docs/mcp), Obsidian local REST API

## Install

### Claude Code

```bash
# Add this marketplace
claude plugin marketplace add RS42-AI/ai-os-lite

# Install the plugin
claude plugin install ai-os-lite@ai-os-lite-marketplace
```

### Codex

```bash
# Add the public AI-OS Lite marketplace
codex plugin marketplace add RS42-AI/ai-os-lite

# Install the plugin for this Codex user
codex plugin add ai-os-lite@ai-os-lite-marketplace
```

Start a new Codex task after installation so the eight skills are loaded. Open your generated vault as the Codex workspace, then invoke a skill naturally or explicitly—for example, `Run $start-day for today.`

The skills are **manual by default**. Run `/start-day` when you want the Morning Brief prepared. The same commands are safe to invoke from an external scheduler, but AI-OS Lite does not install or configure that scheduler for you.

Then configure your vault path and conventions in your vault's `AGENTS.md`. The plugin substitutes your real areas, projects, contacts, and work-item prefixes from there at runtime — the skill examples ship with generic `{WorkArea}` / `{Project}` / `{Contact}` placeholders that resolve to *your* data. Plugin installation is user-level; each person still opens and operates only their own vault instance.

## Configuration

AI-OS Lite is **per-user generic by design**. It contains no hardcoded names, employers, projects, gratitude routines, or lifestyle habits. Examples use `{Placeholder}` tokens that the model fills from your `AGENTS.md` at output time:

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
