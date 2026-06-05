# Source Manifest — Error Observability Pattern

Every skill in the AI-OS Lite plugin calls external sources. This reference defines how to **track**, **report**, and **recover** from source failures across all skills.

## Core Rule

**No silent failures.** If a source call fails, the skill:
1. Records the failure (source name, error type, fix command)
2. Continues with remaining sources
3. Reports all results in the Execution Report at the end

The skill still **does not block** on non-REQUIRED failures — it degrades gracefully, but the user always knows what's missing.

## Source Catalog

| Source | Tool Pattern | Auth Required | Common Failures | Fix Command |
|--------|-------------|---------------|-----------------|-------------|
| Obsidian CLI | `obsidian read/search/append/create/files` | None (local) | Vault not found, file missing | Check Obsidian is running |
| Obsidian MCP | `mcp__obsidian-mcp-tools__*` | MCP server running | Server down, Obsidian closed | Restart Obsidian or MCP server |
| Todoist CLI | `td task *` | API token | Auth expired, rate limit, network | `td auth login` |
| GWS Calendar | `gws calendar *` | OAuth token | Auth token expired | `gws auth login` |
| GWS Email | `gws gmail *` | OAuth token | Auth token expired, no @Action label | `gws auth login` |
| QMD Search | `mcp__qmd__*` | MCP server running | Server not running, index stale | Restart QMD MCP server |
| Linear MCP | `mcp__linear__*` | MCP server + API key | Server down, key expired | Check Linear MCP server |
| Obsidian CLI (graph) | `obsidian links`, `obsidian backlinks` | None (local) | Note not found, no links | Check note name spelling |

## Source Criticality

| Level | Meaning | Skill Behavior |
|-------|---------|---------------|
| **REQUIRED** | Skill cannot produce useful output without it | Abort skill, report why |
| **HIGH** | Skill output is significantly degraded without it | Continue but warn prominently |
| **MEDIUM** | Skill output is partially degraded | Continue, note in report |
| **LOW** | Nice-to-have context | Continue, note in report |

## Per-Skill Source Map

### /start-day

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read/write journal, daily hub, devlogs | REQUIRED |
| Obsidian MCP | Patch sections into journal + hub | REQUIRED |
| QMD Search | Devlog lookup (backup to glob) | MEDIUM |
| Todoist CLI | Today's tasks, carry-forward, Linear sync | HIGH |
| GWS Calendar | Today's calendar events | MEDIUM |
| Linear MCP | RS42 issues → Todoist sync | MEDIUM |

### /process-journal

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read journal transcript, write AI Summary | REQUIRED |
| Obsidian MCP | Patch sections, update frontmatter | REQUIRED |
| QMD Search | People lookup in vault contacts | LOW |
| Todoist CLI | Task creation, dedup check | HIGH |

### /prep-evening

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read/write evening entry, devlogs, daily hub | REQUIRED |
| Obsidian MCP | Patch sections into evening entry | REQUIRED |
| QMD Search | Devlog lookup (backup to glob) | MEDIUM |
| Todoist CLI | Completed tasks, remaining tasks | HIGH |
| GWS Calendar | Tomorrow preview | MEDIUM |
| Linear MCP | Cross-reference devlogs against RS42 issues | LOW |

### /process-evening

| Source | Used For | Criticality |
|--------|---------|-------------|
| Obsidian CLI | Read evening entry, write AI Summary | REQUIRED |
| Obsidian MCP | Patch sections, update frontmatter | REQUIRED |
| QMD Search | Pattern detection (decision loops), people lookup | MEDIUM |
| Todoist CLI | Task triage (close, defer, create) | HIGH |

## Tracking Instructions

As you execute each skill step, maintain a running source tracker:

1. **Before each source call**: Note which source you're about to call
2. **On success**: Record `[x]` with item count or brief result
3. **On failure**: Record `[ ]` with error type and fix command — **DO NOT stop the skill** (unless REQUIRED)
4. **On skip**: Record `[ ]` with reason (e.g., dependency on a failed source)

### Distinguishing Failed vs Empty vs Skipped

| Result | Format | Example |
|--------|--------|---------|
| Success with data | `- [x] Source — N items` | `- [x] Todoist overdue/today — 7 items` |
| Success, empty | `- [x] Source — 0 items` | `- [x] Linear in-progress — 0 items` |
| Failed | `- [ ] Source — FAILED: reason` | `- [ ] GWS Calendar — FAILED: auth token expired` |
| Skipped | `- [ ] Source — SKIPPED: reason` | `- [ ] GWS Email — SKIPPED: GWS auth unavailable` |

## Execution Report Format

Append this **after** the skill's normal summary output, separated by `---`:

```markdown
---
### Execution Report
#### Sources
- [x] Obsidian CLI — journal read, daily hub read, 3 devlogs found
- [x] Todoist overdue/today — 7 items
- [ ] GWS Calendar — FAILED: auth token expired
- [x] Linear in-progress — 2 items
- [ ] GWS Email @Action — SKIPPED: GWS unavailable

#### Search & Discovery
- [x] obsidian links "{Project}" → 12 outgoing connections
- [x] obsidian backlinks "{Project}" → 8 incoming references
- [x] obsidian read → 6 connected notes read
- [x] qmd vector_search "{project} daily lifecycle" → 4 semantic hits
- [ ] Linear in-progress → FAILED: auth expired

#### Warnings
- GWS integration unavailable. Run `gws auth login` to refresh.
- 2 devlogs found with no task linked.
```

### Warning Generation Rules

Generate a warning for:
1. **Any FAILED source** — include the fix command from the Source Catalog above
2. **REQUIRED source failures** — escalate: abort the skill and explain what's broken
3. **HIGH source failures** — note explicitly what's missing from the output (e.g., "Task data unavailable — today's tasks section is empty")
4. **Unlinked devlogs** — devlogs with empty or missing `tasks:` property
5. **Cross-source inconsistencies** — e.g., Linear shows an issue as Done but Todoist mirror is still open (informational, not an error)

### No Warnings Needed For

- Successful sources (they appear in the Sources list)
- Empty results on successful calls (that's valid data — "you have no Linear issues" is fine)
- LOW criticality skips (just note in Sources list, no warning)

## Recovery Guidance

When the execution report shows failures, the skill should end with a brief **actionable fix** section only if there are warnings:

```markdown
#### Fix
- GWS: Run `gws auth login` to refresh OAuth token
- Linear: Check the Linear MCP server is running
```

Keep fixes to one line per source. Don't explain what the source does — the user knows.
