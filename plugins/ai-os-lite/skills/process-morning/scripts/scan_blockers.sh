#!/usr/bin/env bash
# Scan plans + devlogs + transcript for possible blockers of a given priority.
# Emits a JSON array of {description, source_path, source_section, snippet}.
#
# Usage:
#   scan_blockers.sh "Priority text" "project-slug" "/path/to/transcript.md"
#
# Returns exit 0 with "[]" when no hits — never exits non-zero on empty results.
# Exits non-zero only on argument errors.
#
# Fixes over plan stub:
#   - Removed undefined DATE_FLAVOR variable; BSD/GNU date fallback chain instead.
#   - Replaced `xargs dirname` with a while-read loop — xargs collapses
#     space-containing paths (e.g. "My Project/Dev Log" → broken basename).
#   - Used process substitution + -print0/-d '' throughout to handle paths with
#     spaces correctly.
#   - Added `|| true` after every fm_value / grep call that appears in a command
#     substitution: with set -euo pipefail, a grep that finds no match exits 1
#     and kills the script even inside $(...). The || true guards are intentional
#     and load-bearing — do not remove them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ $# -lt 3 ]]; then
  echo "Usage: scan_blockers.sh <priority-text> <project-slug> <transcript-path>" >&2
  exit 1
fi

priority="$1"
project_slug="$2"
transcript_path="$3"

results="[]"

# ---------------------------------------------------------------------------
# Source 1: docs/superpowers/plans/*.md
#   Match on: frontmatter project: == slug  OR  basename contains slug.
#   Emit: unchecked task lines (up to 5) + "Handoff Notes / Out of Scope" section.
# ---------------------------------------------------------------------------
plans_dir="$VAULT/docs/superpowers/plans"
if [[ -d "$plans_dir" ]]; then
  while IFS= read -r -d '' plan; do
    [[ -z "$plan" ]] && continue
    # fm_value uses grep in a pipeline; || true prevents set -e from bailing on no match
    p_slug=$(fm_value "$plan" "project") || true
    base=$(basename "$plan" .md)
    # Match if frontmatter project: matches, or basename contains the slug
    if [[ "$p_slug" == "$project_slug" ]] || [[ "$base" == *"$project_slug"* ]]; then

      # Unchecked tasks (up to 5). grep exits 1 on no match — the while loop
      # drains an empty process substitution cleanly without triggering set -e.
      while IFS= read -r unchecked; do
        [[ -z "$unchecked" ]] && continue
        desc=$(echo "$unchecked" | sed 's/^[[:space:]]*//' | sed 's/^- \[ \] //')
        results=$(printf '%s' "$results" | jq \
          --arg d "$desc" \
          --arg s "${plan#"$VAULT/"}" \
          --arg sec "unchecked task" \
          --arg sn "$unchecked" \
          '. + [{description: $d, source_path: $s, source_section: $sec, snippet: $sn}]')
      done < <(grep -E '^[[:space:]]*- \[ \] ' "$plan" 2>/dev/null || true)

      # Handoff Notes / Out of Scope section (up to 3 non-blank lines)
      handoff=$(awk '/^## Out of Scope|^## Handoff Notes/{p=1;next} /^## /{p=0} p && NF' \
        "$plan" 2>/dev/null | head -3) || true
      if [[ -n "$handoff" ]]; then
        results=$(printf '%s' "$results" | jq \
          --arg d "Plan has handoff/out-of-scope notes" \
          --arg s "${plan#"$VAULT/"}" \
          --arg sec "Handoff Notes / Out of Scope" \
          --arg sn "$handoff" \
          '. + [{description: $d, source_path: $s, source_section: $sec, snippet: $sn}]')
      fi
    fi
  done < <(find "$plans_dir" -maxdepth 1 -type f -name '*.md' -print0)
fi

# ---------------------------------------------------------------------------
# Source 2: Project Dev Log entries from the last 14 days.
#   Slug-match: convert project folder basename to slug via
#   tr 'A-Z ' 'a-z-'  (handles "My Project" → "my-project",
#                               "Multi-Word-Name" → "multi-word-name").
#   Look for: "where we left off", "pending", "blocked", "depends on",
#             "next session", "TODO".
# ---------------------------------------------------------------------------
while IFS= read -r -d '' devlog_dir; do
  project_dir=$(dirname "$devlog_dir")
  dir_slug=$(basename "$project_dir" | tr 'A-Z ' 'a-z-')
  [[ "$dir_slug" != "$project_slug" ]] && continue

  while IFS= read -r -d '' devlog; do
    [[ -z "$devlog" ]] && continue
    dl_date=$(fm_value "$devlog" "date") || true
    [[ -z "$dl_date" ]] && continue

    # BSD date: date -j -f "%Y-%m-%d" <date> +%s
    # GNU date: date -d <date> +%s
    d_epoch=$(date -j -f "%Y-%m-%d" "$dl_date" +%s 2>/dev/null \
              || date -d "$dl_date" +%s 2>/dev/null \
              || echo 0)
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - d_epoch) / 86400 ))
    # (( expr )) exits 1 when false — safe inside && because && suppresses set -e
    (( age_days > 14 )) && continue

    snippet=$(grep -iE \
      'where we left off|pending|blocked|depends on|next session|TODO' \
      "$devlog" 2>/dev/null | head -2) || true
    if [[ -n "$snippet" ]]; then
      results=$(printf '%s' "$results" | jq \
        --arg d "Recent devlog mentions pending/blocked work" \
        --arg s "${devlog#"$VAULT/"}" \
        --arg sec "recent devlog ($age_days d old)" \
        --arg sn "$snippet" \
        '. + [{description: $d, source_path: $s, source_section: $sec, snippet: $sn}]')
    fi
  done < <(find "$devlog_dir" -maxdepth 1 -type f -name '*.md' -print0)
done < <(find \
  "$VAULT/2. Projects" \
  "$VAULT/Personal" \
  -type d -name 'Dev Log' -print0 2>/dev/null)

# ---------------------------------------------------------------------------
# Source 3: Morning transcript — explicit dependency language.
#   Scans the ## Morning section (if present), or the full file.
# ---------------------------------------------------------------------------
if [[ -f "$transcript_path" ]]; then
  # Try to scope to ## Morning section first; fall back to full file
  morning_block=$(awk '/^## Morning$/{p=1;next} /^## /{p=0} p' "$transcript_path" 2>/dev/null) || true
  if [[ -n "$morning_block" ]]; then
    search_target="$morning_block"
  else
    search_target=$(cat "$transcript_path")
  fi

  snippet=$(printf '%s' "$search_target" | \
    grep -iE "can't .* until|have to do .* first|need to .* before|blocked by|depends on" \
    2>/dev/null | head -2) || true
  if [[ -n "$snippet" ]]; then
    results=$(printf '%s' "$results" | jq \
      --arg d "Transcript explicit dependency language" \
      --arg s "${transcript_path#"$VAULT/"}" \
      --arg sec "## Morning transcript" \
      --arg sn "$snippet" \
      '. + [{description: $d, source_path: $s, source_section: $sec, snippet: $sn}]')
  fi
fi

printf '%s\n' "$results"
