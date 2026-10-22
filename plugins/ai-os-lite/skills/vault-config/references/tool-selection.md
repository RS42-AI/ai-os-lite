# Tool Selection Matrix

> Shared reference for all AI-OS Lite skills.
> Every SKILL.md must include a hard gate referencing this file.

## Rules

1. **CLI first** for all deterministic operations (reads, writes, property manipulation, graph traversal)
2. **MCP only** when CLI can't do it (semantic search, section-level patching)
3. **Every skill** references this matrix via hard gate at top of SKILL.md
4. **Source tracking** logs which tools were actually called

## Matrix

| Operation | Tool | Notes |
|-----------|------|-------|
| Read file at known path | `obsidian read` (CLI) | Local, fast, deterministic |
| Get outgoing links | `obsidian links` (CLI) | Structural graph, instant |
| Get backlinks | `obsidian backlinks` (CLI) | Structural graph, instant |
| List files in folder | `obsidian files` (CLI) | Deterministic enumeration |
| Read frontmatter property | `obsidian property:read` (CLI) | Requires `Bash(obsidian property:read:*)` in allowed-tools |
| Set frontmatter property | `obsidian property:set` (CLI) | Requires `Bash(obsidian property:set:*)` in allowed-tools |
| Full-text search | `obsidian search` (CLI) | Fast keyword matching |
| Append content to file | `obsidian append` (CLI) | Simple, deterministic |
| Create new file | `obsidian create` (CLI) | Deterministic template rendering |
| Replace content under heading | `patch_vault_file` (MCP) | Section-level replacement. Verify heading level matches target — known to create duplicate headings on level mismatch |
| Create file with complex content | `create_vault_file` (MCP) | When CLI create is insufficient |
| Keyword search across vault | `qmd search` | Fast exact matching (~30ms) |
| Meaning-based search | `qmd vector_search` | Related concepts (~2s) |
| Broad exploration | `qmd deep_search` | Multi-strategy discovery (~10s) |
| Semantic + folder scoping | `search_vault_smart` (MCP) | Targeted semantic search |
| Todoist task operations | `td task` (CLI) | Direct API, scriptable |
| Linear issues | `mcp__linear__*` (MCP) | No CLI available |
| GWS Calendar | `gws calendar` (CLI) | Direct API |

## DO NOT Use

| Tool | Use Instead |
|------|-------------|
| `mcp__obsidian-mcp-tools__get_vault_file` | `obsidian read` — faster, no Docker dependency |
| `mcp__MCP_DOCKER__obsidian_*` | Obsidian CLI — legacy Docker tools |
| Todoist MCP | `td` CLI |

## Hard Gate Template

Every SKILL.md must include at the top of its Workflow section:

```
## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.
```
