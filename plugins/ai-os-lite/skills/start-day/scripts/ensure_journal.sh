#!/bin/bash
# ensure_journal.sh — Creates the morning journal entry if it doesn't exist.
# Deterministic template rendering. No LLM judgment needed.
# Usage: ensure_journal.sh YYYY-MM-DD [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Outputs JSON: {"created": true|false, "path": "...", "error": "..."}

set -uo pipefail

VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"
TARGET_DATE="${1:?Usage: ensure_journal.sh YYYY-MM-DD [VAULT_PATH]}"

JOURNAL_PATH="$VAULT/5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md"

# Already exists — skip
if [[ -f "$JOURNAL_PATH" ]]; then
  jq -n --arg path "5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md" \
    '{created: false, path: $path, error: null}'
  exit 0
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$JOURNAL_PATH")"

# SYNC: Template content below must match system-settings/Templates/Journal Entry Template.md
# If the Obsidian template changes, update the heredoc below to match.
cat > "$JOURNAL_PATH" << TEMPLATE
---
date: ${TARGET_DATE}
type: journal
journal_type: morning
tags:
  - journal
habit_workout: false
habit_meditation: false
habit_gratitude: false
habit_vitamins: false
---

# [[1. Daily/${TARGET_DATE}|${TARGET_DATE}]]

## Recent Accomplishments
*(filled by /start-day)*

### Last Night's Reflection
*(filled by /start-day)*

---

## Tasks Overview

#### To Do

\`\`\`base
filters:
  and:
    - type == "task"
    - status == "todo"
views:
  - type: table
    name: To Do
    order:
      - priority
      - area
      - project
      - file.name
      - due_date
    sort:
      - property: priority
        direction: ASC
      - property: area
        direction: ASC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.priority: 60
      note.area: 100
      note.project: 120
      file.name: 300
      note.due_date: 100
\`\`\`

#### On Hold / Blocked

\`\`\`base
filters:
  and:
    - type == "task"
    - status == "on-hold"
views:
  - type: table
    name: On Hold
    order:
      - priority
      - area
      - project
      - file.name
      - blocked_by
    sort:
      - property: priority
        direction: ASC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.priority: 60
      note.area: 100
      note.project: 120
      file.name: 300
      note.blocked_by: 200
\`\`\`

#### Recently Completed

\`\`\`base
filters:
  and:
    - type == "task"
    - status == "done"
views:
  - type: table
    name: Completed
    order:
      - done_date
      - area
      - project
      - file.name
    sort:
      - property: done_date
        direction: DESC
    filter: path != "system-settings/Templates/Task Note Template"
    columnSize:
      note.done_date: 100
      note.area: 100
      note.project: 120
      file.name: 300
\`\`\`

---

## Morning


### AI Summary
*(filled by /process-journal)*
TEMPLATE

jq -n --arg path "5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md" \
  '{created: true, path: $path, error: null}'
