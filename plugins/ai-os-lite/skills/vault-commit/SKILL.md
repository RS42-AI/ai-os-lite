---
name: vault-commit
description: Nightly vault cleanup that groups uncommitted files into semantic git commits by date, area, and project. Use when the user says "commit vault", "vault commit", "clean up commits", or "/vault-commit".
user-invocable: true
allowed-tools:
  # Gather script (deterministic git status + frontmatter collection)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/vault-commit/scripts/*.sh:*)
  - Bash(chmod:*)
  # Git operations (read-only in gather, write in commit step)
  - Bash(git status:*)
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git log:*)
  - Bash(git diff:*)
---

# Vault Commit

Groups uncommitted vault files into semantic git commits organized by date, area, and project. Produces a clean git history where each commit tells a story.

## Key Principles

1. **Never `git add -A`** — always stage specific files by name.
2. **Group semantically, not alphabetically** — date first, then project/area, then cross-cutting.
3. **Target 3-12 commits** — one per file is too granular, one giant commit loses context.
4. **Commit messages follow vault conventions** — `docs:` for content, `chore:` for config. NEVER mention AI generation or co-authoring.
5. **No silent failures** — track every operation in the execution report. See `vault-config/references/source-manifest.md`.
6. **Don't push** — only local commits. Never push to remote unless the user explicitly asks.
7. **Batch approval** — show all proposed commits to the user before executing any of them.

## Sources

Track all source calls per `vault-config/references/source-manifest.md`. The gather script tracks git and frontmatter reads automatically via `source_manifest`.

| Source | Used For | Criticality |
|--------|---------|-------------|
| Git CLI | Status, staging, committing | REQUIRED |
| Filesystem | Frontmatter reading for grouping | HIGH |

## Invocation

```
/vault-commit              → commit all uncommitted vault files
```

---

## Tool Rules
> Reference: vault-config/references/tool-selection.md
> CLI for reads, writes, graph traversal, and property operations.
> MCP only for semantic search and section-level patching.
> DO NOT use mcp__obsidian-mcp-tools__get_vault_file for reads.

## Step 1: Run the Gather Script

Collect all git status data and file metadata:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vault-commit/scripts/gather_git_context.sh
```

If the script fails to execute:
```bash
chmod +x ${CLAUDE_PLUGIN_ROOT}/skills/vault-commit/scripts/gather_git_context.sh
```

Parse the JSON output. It contains:
- `total_files` — count of changed files. **If 0, output "Nothing to commit — vault is clean" and STOP.**
- `files[]` — array of changed files with resolved metadata (date, type, area, project)
- `recent_commits` — last 10 commit messages for style matching
- `source_manifest` — what succeeded/failed in data collection

## Step 2: Group Files Into Semantic Commits

Using the file metadata from Step 1, group files into commit batches. Apply these rules in order:

### Grouping Priority (three-level sort)

1. **Primary: Date** — all files from the same work date go together
2. **Secondary: Project/Area** — within a date, group by project. If multiple projects in the same area, combine into one area-level commit unless the work is substantial enough for each
3. **Tertiary: Cross-cutting files separate** — daily hubs, journals, and career prep get their own commits

### Grouping Rules

| Rule | Example |
|---|---|
| Same date + same project = one commit | Mar 17 {Project} devlog + {Project} knowledge notes + {Project} hub update |
| Same date + same area + multiple projects = one commit | Mar 18 {WorkArea}: {Project} devlog + {Project2} devlog + {Project3} devlog |
| Same date + different area = separate commits | Mar 18 {WorkArea} work vs. Mar 18 {Project} work |
| New project scaffold = standalone commit | New project hub + notes + devlogs (even if spanning 2 dates) |
| Daily hubs + journals + career prep = bundled together | Mar 18 daily hub + morning journal + interview prep |
| System/config files = final catchall commit | `.obsidian/` settings + `.claude/` config + Granola sync state |
| Images/Excalidraw = with their project | project-setup.excalidraw goes with {Project} commit |

### Edge Cases

| Situation | Resolution |
|---|---|
| Files spanning two dates for same project | Group by project coherence, not by date |
| Meeting notes alongside devlogs | Same project → same commit. General meeting → area-level commit |
| Backfilled content (old dates committed now) | Group with its project; note the backfill in the message |
| Memory files (`.claude/projects/.../memory/`) | Include in the final chore: commit |
| No frontmatter and no path inference | Group into a "misc" commit at the end |
| Deleted files (git status `D`) | Group with the project/area they belonged to |

### Commit Ordering

Order commits chronologically, oldest first:
1. Oldest date, project-specific work
2. Oldest date, cross-cutting (daily/journal)
3. Next date, project-specific work
4. Next date, cross-cutting
5. New project scaffolds (standalone)
6. Current date project work
7. **Final: system/config catchall** (`chore:` prefix)

## Step 3: Compose Commit Messages

**Format**: `{prefix}: {action} {date/scope} — {key items summary}`

**Prefix rules:**
- `docs:` — vault content (devlogs, knowledge notes, meeting notes, journals, daily hubs)
- `chore:` — system files (Obsidian config, Claude config, plugin state, Granola sync)
- `feat:` — reserved for actual code changes (skills, tools, automation). Rarely used in the vault.
- `fix:` — frontmatter corrections or structural fixes

**Message body** (multi-line): 2-4 lines summarizing the key content. Focus on **what was accomplished or discovered**, not just file names.

**Match the style** of `recent_commits` from the gather script output.

**Examples from previous sessions:**
```
docs: add Mar 17 {Project} devlog, knowledge notes, and hub updates
docs: add Mar 18 {WorkArea} work — {Project} architecture pivot, {Project2} meeting, {Project3} outreach
docs: add Mar 18 daily hub, morning journal, and career prep
chore: update daily hubs, journal entries, config, and Granola sync state
```

## Step 4: Present Batch for Approval

Before executing any commits, show the user the full plan:

```markdown
### Proposed Commits

**Commit 1** — `docs: add Mar 21 {Project} devlogs and knowledge notes`
Files (N):
- 2. Projects/{WorkArea}/{Project}/Dev Log/2026-03-21 - ...
- 2. Projects/{WorkArea}/{Project}/Notes/...

**Commit 2** — `chore: update Obsidian config and Granola sync`
Files (N):
- .obsidian/plugins/granola-sync/data.json
- .claude/settings.local.json

---
Proceed with all N commits? (or specify which to skip/modify)
```

Wait for user confirmation. If running as a scheduled task (nightly cron), proceed without confirmation.

## Step 5: Execute Commits

For each approved commit group, in order:

1. Stage the specific files:
   ```bash
   git add "file1.md" "file2.md" ...
   ```

2. Commit with the semantic message (use HEREDOC for multi-line):
   ```bash
   git commit -m "$(cat <<'EOF'
   docs: add Mar 21 {Project} devlogs and knowledge notes

   Project-sync migration, gather script build, template coverage gap discovery.
   EOF
   )"
   ```

3. Verify with `git status` that remaining files are as expected.

4. Track success/failure for each commit in the execution report.

**If a commit fails**: Log the error, skip that group, continue with the next. Do NOT abort the entire run.

## Step 6: Report Results

Output the execution report:

```markdown
---
### Execution Report

#### Commits
- [x] Commit 1 — `docs: add Mar 21 ...` (N files)
- [x] Commit 2 — `chore: update config ...` (N files)
- [ ] Commit 3 — FAILED: {error}

#### Sources
- [x] Git status — N changed files detected
- [x] Frontmatter reads — N read, N skipped, N failed

#### Summary
N files committed across N commits. N files remaining uncommitted.
```

If running as a scheduled cron, also note: "Run at {time}. Next scheduled run: {tomorrow at 11 PM}."

---

## What This Skill Does NOT Do

- **Does NOT push to remote** — local commits only
- **Does NOT modify file content** — only stages and commits existing changes
- **Does NOT fix frontmatter** — leave that to a separate maintenance skill
- **Does NOT create branches** — commits directly to the current branch
- **Does NOT run `git add -A`** — always stages specific files
