#!/bin/bash
# ensure_daily_hub.sh — Creates the daily hub note if it doesn't exist.
# Deterministic template rendering. No LLM judgment needed.
# Usage: ensure_daily_hub.sh YYYY-MM-DD [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Outputs JSON: {"created": true|false, "path": "...", "error": "..."}

set -uo pipefail

VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"
TARGET_DATE="${1:?Usage: ensure_daily_hub.sh YYYY-MM-DD [VAULT_PATH]}"

HUB_PATH="$VAULT/1. Daily/${TARGET_DATE}.md"

# Already exists with content — skip. 0-byte or <100-byte files are treated as non-existent.
if [[ -f "$HUB_PATH" ]] && [[ $(wc -c < "$HUB_PATH") -gt 100 ]]; then
  jq -n --arg path "1. Daily/${TARGET_DATE}.md" \
    '{created: false, path: $path, error: null}'
  exit 0
fi

# ── Platform Detection (BSD vs GNU date) ─────────────────────────────
if date -j -f "%Y-%m-%d" "2000-01-01" +%s &>/dev/null; then
  DATE_FLAVOR="bsd"
else
  DATE_FLAVOR="gnu"
fi

# Compute display name: "Saturday, March 21"
if [[ "$DATE_FLAVOR" == "bsd" ]]; then
  DISPLAY_DATE=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%A, %B %-d" 2>/dev/null)
  PREV_DATE=$(date -j -v-1d -f "%Y-%m-%d" "$TARGET_DATE" +%Y-%m-%d 2>/dev/null)
  NEXT_DATE=$(date -j -v+1d -f "%Y-%m-%d" "$TARGET_DATE" +%Y-%m-%d 2>/dev/null)
else
  DISPLAY_DATE=$(date -d "$TARGET_DATE" "+%A, %B %-d" 2>/dev/null)
  PREV_DATE=$(date -d "$TARGET_DATE -1 days" +%Y-%m-%d 2>/dev/null)
  NEXT_DATE=$(date -d "$TARGET_DATE +1 days" +%Y-%m-%d 2>/dev/null)
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$HUB_PATH")"

# SYNC: Template content below must match system-settings/Templates/Daily Note Hub Template.md
# If the Obsidian template changes, update the heredoc below to match.
cat > "$HUB_PATH" << TEMPLATE
---
date: ${TARGET_DATE}
type: daily
tags:
  - daily
---

# ${DISPLAY_DATE}

> [[1. Daily/${PREV_DATE}|← Yesterday]] | [[1. Daily/${NEXT_DATE}|Tomorrow →]]

---
## Morning Journal

> [[5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}|Open Morning Entry]]


**Today's priorities:**
- [ ] ...

---

## Active Work

\`\`\`base
filters:
  and:
    - type == "task"
    - status == "active"
views:
  - type: table
    name: Active Work
    order:
      - file.name
      - project
      - priority
    sort:
      - property: priority
        direction: ASC
    columnSize:
      file.name: 350
      note.project: 130
      note.priority: 80
\`\`\`

---

## Today's Meetings

\`\`\`base
filters:
  and:
    - type == "meeting"
    - date == "${TARGET_DATE}"
views:
  - type: table
    name: Meetings
    order:
      - file.name
    sort:
      - property: file.name
        direction: ASC
    columnSize:
      file.name: 500
\`\`\`

---
## Today's Dev Sessions

\`\`\`base
filters:
  and:
    - type == "devlog"
    - date == "${TARGET_DATE}"
views:
  - type: table
    name: Dev Sessions
    order:
      - file.name
      - project
      - session_topic
    sort:
      - property: file.name
        direction: ASC
    columnSize:
      file.name: 400
      note.project: 150
      note.session_topic: 250
\`\`\`

---
## Notes Created Today

\`\`\`base
filters:
  and:
    - date == "${TARGET_DATE}"
    - type != "devlog"
    - type != "meeting"
    - type != "daily"
    - type != "journal"
    - type != "task"
    - area != "personal"
    - area != "health"
views:
  - type: table
    name: Notes
    order:
      - file.name
      - area
      - project
    sort:
      - property: file.name
        direction: ASC
    columnSize:
      file.name: 400
      note.area: 120
      note.project: 120
\`\`\`

---
## Evening Reflection

> [[5. Resources/Personal/Journal/Evening Entries/${TARGET_DATE}|Open Evening Entry]]
TEMPLATE

jq -n --arg path "1. Daily/${TARGET_DATE}.md" \
  '{created: true, path: $path, error: null}'
