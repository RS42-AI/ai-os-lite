# Search and Discovery Pattern

> Standardized strategy for how skills gather context from the vault.
> Skills MUST declare which search strategy they use in their SKILL.md.

## Two-Layer Strategy

### Layer 1 — Structural (Obsidian CLI)

Uses the vault's explicit link graph for deterministic traversal:

- `obsidian links "Note Name"` — all outgoing wikilinks FROM a note
- `obsidian backlinks "Note Name"` — all notes linking TO a note
- `obsidian read path="..."` — read connected notes
- `obsidian files folder="..."` — enumerate folder contents
- `obsidian property:read` — read frontmatter for routing

Strategy: BFS with depth limit (default 2 hops) and context budget (max 15 notes):
- Hop 0: Read the target note
- Hop 1: Read outgoing links filtered by relevance (matching `project:` frontmatter, skip `status: archived`)
- Hop 2: For high-relevance hop-1 notes, read THEIR outgoing links
- Stop at 2 hops OR 15 notes read, whichever comes first

### Layer 2 — Semantic (QMD + MCP)

Finds related content that isn't explicitly linked:

- `qmd search` — exact keyword matches (~30ms)
- `qmd vector_search` — meaning-based discovery (~2s)
- `qmd deep_search` — broad multi-strategy exploration (~10s)
- `search_vault_smart` — semantic search with folder scoping

Strategy: Use AFTER structural search to find notes related by meaning but not by wikilink.

## When to Use Which

| Situation | Strategy |
|-----------|----------|
| Gather context for project X | Hub → Layer 1 (links/backlinks) → Layer 2 (semantic for gaps) |
| How does X work? | Layer 2 first (semantic) → Layer 1 (follow links from best hits) |
| Where did we leave off? | Direct read (known path) → Layer 1 (devlog chain links) |
| Find everything related to X | Both layers in parallel, deduplicate |

This table defines which search STRATEGY to apply. For the specific tool to use within each layer, see `tool-selection.md`.

## Source Tracking

Every search operation must be logged in the execution report (per `source-manifest.md`):

```
#### Search & Discovery
- [x] obsidian links "{Project}" → 12 outgoing connections
- [x] obsidian backlinks "{Project}" → 8 incoming references
- [x] obsidian read → 6 connected notes read
- [x] qmd vector_search "{project} daily lifecycle" → 4 semantic hits
```

Full trail of what was called, what returned results, what failed. If something got missed, you can trace why.
