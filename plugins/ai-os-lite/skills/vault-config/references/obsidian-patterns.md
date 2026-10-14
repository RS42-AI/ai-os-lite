# Obsidian Tool Patterns

## Tool Strategy

| Purpose | Tool | Why |
|---------|------|-----|
| File CRUD (read, write, create, append) | **Obsidian CLI** (`obsidian`) | Local, fast, no Docker dependency |
| Semantic search | **obsidian-mcp-tools** `search_vault_smart` | Meaning-based with folder filtering |
| Deep/broad search | **QMD** (`mcp__qmd__*`) | Keyword, vector, and deep search across collections |
| Frontmatter operations | **Obsidian CLI** `property:set/read` | Direct property manipulation |

Do NOT use `mcp__MCP_DOCKER__obsidian_*` tools — prefer the Obsidian CLI for all file operations.

## Obsidian CLI Patterns

### Read File
```bash
obsidian read path="1. Daily/2026-03-09.md"
# or by name (wikilink-style resolution)
obsidian read file="{Project2}"
```

### Read Multiple Files
```bash
# Read files sequentially — CLI doesn't have batch read
obsidian read path="1. Daily/2026-03-09.md"
obsidian read path="5. Resources/Personal/Journal/Morning Entries/2026-03-09.md"
```

### List Files in Directory
```bash
obsidian files folder="5. Resources/Personal/Journal/Morning Entries"
obsidian files folder="2. Projects/{WorkArea}/{Project2}/Dev Log"
```

### List Folders
```bash
obsidian folders folder="2. Projects/{WorkArea}"
obsidian folders folder="2. Projects/{SideArea2}"
```

### Search Text
```bash
obsidian search query="{Project2}" limit=10
obsidian search query="{Project2}" path="2. Projects/{WorkArea}" limit=10
# With context:
obsidian search:context query="{Project2}" limit=10
```

### Create File
```bash
obsidian create path="6. Main Notes/New Note.md" content="---\ndate: 2026-03-09\ntype: note\n---\n\n# New Note\n\nContent here."
# With template:
obsidian create path="2. Projects/{WorkArea}/{Project}/Dev Log/2026-03-09 - Session.md" template="Devlog Template"
```

### Append Content
```bash
obsidian append path="5. Resources/Personal/Journal/Morning Entries/2026-03-09.md" content="\n\n### Gratitude\n1. Item one\n2. Item two\n3. Item three"
```

### Prepend Content
```bash
obsidian prepend path="6. Main Notes/Some Note.md" content="Updated intro paragraph."
```

### Property Operations
```bash
# Read a property
obsidian property:read name="type" path="6. Main Notes/Some Note.md"
# Set a property
obsidian property:set name="status" value="complete" path="6. Main Notes/Some Note.md"
# Remove a property
obsidian property:remove name="old_field" path="6. Main Notes/Some Note.md"
```

### File Info & Links
```bash
obsidian file path="2. Projects/{WorkArea}/{Project}/{Project}.md"
obsidian backlinks path="2. Projects/{WorkArea}/{Project}/{Project}.md"
obsidian links path="2. Projects/{WorkArea}/{Project}/{Project}.md"
```

### Vault Structure
```bash
obsidian vault              # vault name, path, file/folder counts
obsidian folders            # all top-level folders
obsidian tags counts sort=count  # all tags with counts
```

## Semantic Search Patterns

### Smart Semantic Search (obsidian-mcp-tools)
```python
mcp__obsidian-mcp-tools__search_vault_smart(
    query="journal processing automation",
    filter={"limit": 10}
)
# Meaning-based — finds related concepts even with different vocabulary
# Supports folder filtering
```

## QMD Search Patterns

### Keyword Search (~30ms)
```python
mcp__qmd__search(query="{Project2}", collection="vault")
```

### Vector Search (~2s)
```python
mcp__qmd__vector_search(query="journal processing", collection="vault", minScore=0.5)
```

### Deep Search (~10s)
```python
mcp__qmd__deep_search(query="how does vault organization work", collection="vault")
# Auto-expands query, searches keyword + meaning, reranks
```

### Get Document
```python
mcp__qmd__get(path="2. Projects/{WorkArea}/{Project}/{Project}.md", collection="vault")
```

### Get Multiple Documents
```python
mcp__qmd__multi_get(paths="journals/2025-05*.md", collection="vault")
```

## Search Strategy Decision Tree

| Question Type | Strategy |
|---------------|----------|
| "How does X work?" | `search_vault_smart` or `qmd__vector_search` → exclude Dev Log folders |
| "Where did we leave off?" | `obsidian search` in project's Dev Log folder |
| "What did I work on yesterday?" | `obsidian read path="1. Daily/YYYY-MM-DD.md"` |
| "Project X status" | `obsidian read` project hub at known path |
| "Find notes about X" | `obsidian search` first, `search_vault_smart` if insufficient |
| "List journal entries" | `obsidian files folder="5. Resources/Personal/Journal/Morning Entries"` |
| "Broad exploration" | `qmd__deep_search` for comprehensive results |

## Key Vault Paths

| Content | Path Pattern |
|---------|-------------|
| Daily hub | `1. Daily/YYYY-MM-DD.md` |
| Journal entry | `5. Resources/Personal/Journal/Morning Entries/YYYY-MM-DD.md` |
| Project hub | `2. Projects/{Area}/{Project}/{Project}.md` |
| Project devlogs | `2. Projects/{Area}/{Project}/Dev Log/` |
| Project notes | `2. Projects/{Area}/{Project}/Notes/` |
| Area dashboard | `3. Areas/{Area Name}.md` |
| Contacts | `4. Contacts/People/` |
| Meetings | `4. Contacts/Meetings/` |

## Important Notes

- Obsidian CLI resolves `file=` by name (like wikilinks) — use `path=` for exact paths
- Quote values with spaces: `path="2. Projects/{WorkArea}/{Project}/{Project}.md"`
- Use `\n` for newline in content values
- CLI requires Obsidian app to be running
- `search_vault_smart` still requires the obsidian-mcp-tools MCP server
