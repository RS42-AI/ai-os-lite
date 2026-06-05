#!/usr/bin/env bash
# Resolve a task-note wikilink to a path under */Tasks/ and read its status,
# priority, due_date, and blocked_by frontmatter. Used by carry-forward
# reconciliation to classify prior-hub bullets.
# Usage: read_task_status.sh "Wikilink Target Without Brackets"
set -euo pipefail
source "$(dirname "$0")/lib.sh"

target="${1:?Usage: read_task_status.sh \"Wikilink Target Without Brackets\"}"

# Find match_task_note.sh — it path-suffix matches a wikilink target to a
# */Tasks/*.md file. Resolve relative to this script's own location first (works
# under any install path/name), then fall back to generic plugin-cache globs.
match_script=""
for candidate in \
  "$(dirname "$0")/../../start-day/scripts/match_task_note.sh" \
  "$HOME/.claude/plugins/cache"/*/*/*/skills/start-day/scripts/match_task_note.sh \
  "$HOME/.claude/plugins/cache"/*/*/skills/start-day/scripts/match_task_note.sh ; do
  if [[ -x "$candidate" ]]; then match_script="$candidate"; break; fi
done

if [[ -z "$match_script" ]]; then
  jq -n --arg t "$target" \
    '{target: $t, path: null, status: null, priority: null,
      due_date: null, blocked_by: null, found: false,
      error: "match_task_note.sh not found"}'
  exit 0
fi

paths=$(bash "$match_script" "$target" 2>/dev/null || true)
if [[ -z "$paths" ]]; then
  jq -n --arg t "$target" \
    '{target: $t, path: null, status: null, priority: null,
      due_date: null, blocked_by: null, found: false}'
  exit 0
fi

# Take the first match (vault-relative path)
path=$(echo "$paths" | head -1)
abs="$VAULT/$path"

jq -n \
  --arg target   "$target" \
  --arg path     "$path" \
  --arg status   "$(fm_value "$abs" status)" \
  --arg priority "$(fm_value "$abs" priority)" \
  --arg due      "$(fm_value "$abs" due_date)" \
  --arg blocked  "$(fm_value "$abs" blocked_by)" \
  '{target: $target, path: $path, status: $status, priority: $priority,
    due_date: $due, blocked_by: $blocked, found: true}'
