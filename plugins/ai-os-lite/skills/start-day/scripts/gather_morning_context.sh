#!/bin/bash
# gather_morning_context.sh — Deterministic morning context gathering.
# Called by /start-day skill as Step 1. Outputs structured JSON to stdout.
# Usage: gather_morning_context.sh [YYYY-MM-DD] [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Uses: raw filesystem ops, obsidian CLI, td CLI
# Writes: per-file `private: true` stamp into frontmatter when project hub
#         marks the project private and the file lacks its own privacy flag.
#         Stamping is one-way (only ever writes true, never false).
# Does NOT: call MCP tools, make judgment calls

set -o pipefail

# Per-run cache directory (cleaned up at exit). Holds project-hub privacy lookups
# and hub-path resolutions so a single window doesn't re-read the same hub once
# per file. Keyed by sanitized slug.
CACHE_DIR=$(mktemp -d -t pos-gather.XXXXXX)
trap 'rm -rf "$CACHE_DIR"' EXIT

cache_get() {
  local namespace="$1" key="$2"
  local sanitized="${key//[^a-zA-Z0-9_-]/_}"
  local f="$CACHE_DIR/${namespace}.${sanitized}"
  [[ -f "$f" ]] && cat "$f"
}

cache_has() {
  local namespace="$1" key="$2"
  local sanitized="${key//[^a-zA-Z0-9_-]/_}"
  [[ -f "$CACHE_DIR/${namespace}.${sanitized}" ]]
}

cache_set() {
  local namespace="$1" key="$2" val="$3"
  local sanitized="${key//[^a-zA-Z0-9_-]/_}"
  printf '%s' "$val" > "$CACHE_DIR/${namespace}.${sanitized}"
}

# ── Vault Path Resolution ────────────────────────────────────────────
VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

if [[ ! -d "$VAULT" ]]; then
  echo '{"error": "Vault directory not found: '"$VAULT"'"}' >&2
  exit 1
fi

# The obsidian CLI only knows about the active Obsidian vault. When VAULT points
# at a fixture (or otherwise differs from the live vault), skip the CLI path and
# rely on the filesystem-based fallback for property writes.
LIVE_VAULT_DEFAULT="$HOME/Claude/ObsidianVault"
LIVE_VAULT="${PERSONAL_OS_VAULT:-$LIVE_VAULT_DEFAULT}"
USE_OBSIDIAN_CLI=false
if [[ "$VAULT" == "$LIVE_VAULT" ]]; then
  USE_OBSIDIAN_CLI=true
fi

# ── Platform Detection (BSD vs GNU date) ─────────────────────────────
if date -j -f "%Y-%m-%d" "2000-01-01" +%s &>/dev/null; then
  DATE_FLAVOR="bsd"
else
  DATE_FLAVOR="gnu"
fi

TARGET_DATE="${1:-$(date +%Y-%m-%d)}"

if [[ "$DATE_FLAVOR" == "bsd" ]]; then
  TARGET_DAY=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" +%A 2>/dev/null || date +%A)
else
  TARGET_DAY=$(date -d "$TARGET_DATE" +%A 2>/dev/null || date +%A)
fi

# ── Utilities ────────────────────────────────────────────────────────

date_add_days() {
  if [[ "$DATE_FLAVOR" == "bsd" ]]; then
    date -j -v"${2}d" -f "%Y-%m-%d" "$1" +%Y-%m-%d 2>/dev/null
  else
    date -d "$1 ${2} days" +%Y-%m-%d 2>/dev/null
  fi
}

day_of_week() {
  if [[ "$DATE_FLAVOR" == "bsd" ]]; then
    date -j -f "%Y-%m-%d" "$1" +%A 2>/dev/null || echo "Unknown"
  else
    date -d "$1" +%A 2>/dev/null || echo "Unknown"
  fi
}

# Area priority rank — lower sorts first. Drives /start-day's recap ordering
# (SKILL.md Step 4a). Ranks areas by the order they appear in AGENTS.md's
# canonical "areas" table, so the ordering reflects each user's configured
# area set rather than a hardcoded list. Unknown areas sort last (99).
area_rank() {
  local target="$1"
  if [[ -f "$VAULT/AGENTS.md" ]]; then
    local rank=1 slug
    while IFS= read -r slug; do
      [[ "$slug" == "$target" ]] && { echo "$rank" ; return ; }
      rank=$((rank + 1))
    done < <(awk -F'|' '
      ($2 ~ /Areas\// || $2 ~ /Personal\//) {
        s=$3; gsub(/[`[:space:]]/, "", s)
        if (s ~ /^[a-z0-9-]+$/) print s
      }' "$VAULT/AGENTS.md")
  fi
  echo 99
}

get_frontmatter() {
  awk '/^---$/{if(f){exit}f=1;next}f' "$1" 2>/dev/null
}

fm_value() {
  local file="$1" key="$2"
  get_frontmatter "$file" | grep "^${key}:" | head -1 | sed "s/^${key}: *//" | sed 's/^["'"'"']//;s/["'"'"']$//'
}

fm_list() {
  local file="$1" key="$2"
  get_frontmatter "$file" | \
    awk "/^${key}:/{p=1;next}/^[^ ]/{p=0}p" | \
    sed 's/^ *- *//' | sed 's/^["'"'"']//;s/["'"'"']$//'
}

content_preview() {
  local file="$1" lines="${2:-20}"
  awk '/^---$/{if(f){p=1;next}f=1;next}p' "$file" 2>/dev/null | head -"$lines"
}

# Search the vault for files whose frontmatter declares date: TARGET_DATE.
# Filesystem-based (works on fixture vaults too — Obsidian CLI only knows the
# live vault, so we use grep + frontmatter scan for portability).
# Returns a JSON array of relative paths.
search_by_date_property() {
  local target_date="$1"
  local matches=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local fm_date
    fm_date=$(fm_value "$file" "date")
    if [[ "$fm_date" == "$target_date" ]]; then
      matches+=("${file#$VAULT/}")
    fi
  done < <(grep -rl --include='*.md' "^date: *${target_date}" "$VAULT" 2>/dev/null)

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${matches[@]}" | jq -R . | jq -s .
  fi
}

# ── Recap Window Resolution ──────────────────────────────────────────
# Tiered lookback: probe widening windows until work is found.
# tiers = [3, 5, 7] days back to attempt.
# If no tier finds work, window collapses to today only and `beyond_lookback`
# is set so the renderer can show the --since escape hatch message.

LOOKBACK_TIERS=(3 5 7)

# Probe a date: return JSON array of surfaced file paths (after surface rules).
# Cached under namespace "surfaced.<date>" so gather_window_work can reuse the
# result without re-running grep + per-file frontmatter scans.
probe_date_surfaced() {
  local probe_date="$1"
  if cache_has surfaced "$probe_date"; then
    cache_get surfaced "$probe_date"
    return
  fi

  local results surfaced_arr="[]"
  results=$(search_by_date_property "$probe_date")

  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    local verdict
    verdict=$(apply_surface_rules "$rel_path")
    [[ "$verdict" != "surface" ]] && continue
    surfaced_arr=$(echo "$surfaced_arr" | jq --arg p "$rel_path" '. + [$p]')
  done < <(echo "$results" | jq -r '.[]?' 2>/dev/null)

  cache_set surfaced "$probe_date" "$surfaced_arr"
  echo "$surfaced_arr"
}

resolve_recap_window() {
  local window_start="$TARGET_DATE"
  local beyond=false

  for tier in "${LOOKBACK_TIERS[@]}"; do
    local i
    for ((i=0; i<=tier; i++)); do
      local probe_date
      probe_date=$(date_add_days "$TARGET_DATE" "-$i") || continue
      local count
      count=$(probe_date_surfaced "$probe_date" | jq 'length' 2>/dev/null || echo 0)
      if [[ "$count" -gt 0 ]]; then
        if [[ "$probe_date" < "$window_start" ]]; then
          window_start="$probe_date"
        fi
      fi
    done

    if [[ "$window_start" != "$TARGET_DATE" ]]; then
      break
    fi
  done

  if [[ "$window_start" == "$TARGET_DATE" ]]; then
    local today_count
    today_count=$(probe_date_surfaced "$TARGET_DATE" | jq 'length' 2>/dev/null || echo 0)
    if [[ "$today_count" -eq 0 ]]; then
      beyond=true
    fi
  fi

  jq -n \
    --arg from "$window_start" \
    --arg to "$TARGET_DATE" \
    --argjson beyond "$beyond" \
    '{from: $from, to: $to, beyond_lookback: $beyond}'
}

# ── Privacy Resolution (cached) ──────────────────────────────────────
# Project-level cascade: a project is private when its hub has private: true.
# Cache lookups by project slug to avoid re-reading hub files within a single run.
# Cache namespaces: "hubpath" → relative path of hub, "privacy" → "true"|"false".

resolve_project_hub() {
  local slug="$1"
  [[ -z "$slug" ]] && { echo ""; return; }

  if cache_has hubpath "$slug"; then
    cache_get hubpath "$slug"
    return
  fi

  local path=""
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    [[ "$candidate" == *"Templates"* ]] && continue
    local t fm_proj
    t=$(fm_value "$candidate" "type")
    fm_proj=$(fm_value "$candidate" "project")
    if [[ "$t" == "project" && "$fm_proj" == "$slug" ]]; then
      path="${candidate#$VAULT/}"
      break
    fi
  done < <(grep -rl --include='*.md' "^project: *${slug}\$" "$VAULT" 2>/dev/null)

  cache_set hubpath "$slug" "$path"
  echo "$path"
}

lookup_project_privacy() {
  local slug="$1"
  [[ -z "$slug" ]] && { echo "false"; return; }

  if cache_has privacy "$slug"; then
    cache_get privacy "$slug"
    return
  fi

  local hub_rel hub_full priv result
  hub_rel=$(resolve_project_hub "$slug")
  if [[ -z "$hub_rel" ]]; then
    result="false"
  else
    hub_full="$VAULT/$hub_rel"
    priv=$(fm_value "$hub_full" "private")
    if [[ "$priv" == "true" ]]; then
      result="true"
    else
      result="false"
    fi
  fi

  cache_set privacy "$slug" "$result"
  echo "$result"
}

# Stamp private: true into a file's frontmatter (one-way, idempotent).
# Skips if the file already has any `private:` value (so we never flip true→false
# even if the hub flips public — that's a deliberate design decision).
# Uses obsidian CLI when available (live vault); falls back to a frontmatter
# rewrite via awk for fixture vaults.
stamp_private_if_needed() {
  local rel_path="$1"
  local full="$VAULT/$rel_path"
  local existing
  existing=$(fm_value "$full" "private")
  [[ -n "$existing" ]] && return

  # Prefer obsidian CLI for the live vault (handles property formatting cleanly).
  # Redirect stdin to /dev/null so the CLI can't consume a parent while-read loop.
  # Verify by re-reading because the CLI returns exit 0 even on "file not found".
  if [[ "$USE_OBSIDIAN_CLI" == "true" ]]; then
    obsidian property:set name=private value=true path="$rel_path" </dev/null >/dev/null 2>&1 || true
    if [[ "$(fm_value "$full" "private")" == "true" ]]; then
      return
    fi
  fi

  # Fallback: insert `private: true` before the closing --- of the frontmatter.
  local tmp
  tmp=$(mktemp)
  awk 'BEGIN{seen=0; closed=0} \
       /^---$/ { \
         if (seen==0) { seen=1; print; next } \
         else if (closed==0) { print "private: true"; print; closed=1; next } \
       } \
       { print }' "$full" > "$tmp" && mv "$tmp" "$full"
}

# ── Surface Rules ────────────────────────────────────────────────────
# Decide whether a file from a date-property search should appear in the recap.
# Returns 0 (surface) or 1 (skip). Echoes a reason on skip for diagnostics.

SKIP_TYPES=("journal" "daily" "thought" "project" "task" "meeting" "idea" "goal")
SKIP_PATH_PREFIXES=(
  "1. Daily/"
  "5. Resources/Personal/Journal/"
  "4. Contacts/"
  "system-settings/"
  "Excalidraw/"
  "iPhone Notes/"
  "7. Dev Log/"
)

apply_surface_rules() {
  local rel_path="$1"
  local full="$VAULT/$rel_path"

  [[ -f "$full" ]] || { echo "missing"; return 1; }

  # Skip by path prefix
  for prefix in "${SKIP_PATH_PREFIXES[@]}"; do
    if [[ "$rel_path" == "$prefix"* ]]; then
      echo "skip-folder:$prefix"
      return 1
    fi
  done

  local file_type file_priv file_project file_area
  file_type=$(fm_value "$full" "type")
  file_priv=$(fm_value "$full" "private")
  file_project=$(fm_value "$full" "project")
  file_area=$(fm_value "$full" "area")

  # Skip by type
  for t in "${SKIP_TYPES[@]}"; do
    if [[ "$file_type" == "$t" ]]; then
      echo "skip-type:$t"
      return 1
    fi
  done

  # Privacy filter
  if [[ "$file_priv" == "true" ]]; then
    echo "skip-private:self"
    return 1
  fi

  if [[ -n "$file_project" && "$file_priv" != "false" ]]; then
    local hub_priv
    hub_priv=$(lookup_project_privacy "$file_project")
    if [[ "$hub_priv" == "true" ]]; then
      stamp_private_if_needed "$rel_path"
      echo "skip-private:cascade:$file_project"
      return 1
    fi
  fi

  # Must have a project or area to anchor in the recap
  if [[ -z "$file_project" && -z "$file_area" ]]; then
    echo "skip-unanchored"
    return 1
  fi

  echo "surface"
  return 0
}

# ── Window Work Gathering ────────────────────────────────────────────
# For each day in [from..to], query Obsidian for files stamped with that date,
# apply surface rules, and split into devlogs vs knowledge notes.
# Notes are flagged orphan_candidate when there is no devlog from the same day
# in the same project (hint that a session went uncaptured).

build_file_entry() {
  local rel_path="$1"
  local full="$VAULT/$rel_path"
  local topic area project preview tasks_raw tasks_json file_type title
  topic=$(fm_value "$full" "session_topic")
  area=$(fm_value "$full" "area")
  project=$(fm_value "$full" "project")
  file_type=$(fm_value "$full" "type")
  preview=$(content_preview "$full" 20 | head -c 500)
  title=$(basename "$rel_path" .md)

  tasks_raw=$(fm_list "$full" "tasks")
  if [[ -n "$tasks_raw" ]]; then
    tasks_json=$(echo "$tasks_raw" | jq -R . | jq -s .)
  else
    tasks_json="[]"
  fi

  jq -n \
    --arg path "$rel_path" \
    --arg title "$title" \
    --arg type "$file_type" \
    --arg session_topic "$topic" \
    --arg project "$project" \
    --arg area "$area" \
    --argjson tasks "$tasks_json" \
    --arg preview "$preview" \
    '{path: $path, title: $title, type: $type, session_topic: $session_topic, project: $project, area: $area, tasks: $tasks, preview: $preview}'
}

# Compute orphan_candidate flag: a knowledge note with no devlog in its project
# on the same date. Devlogs are taken from the same day's surfaced devlog list.
mark_orphans() {
  local notes_json="$1"
  local devlogs_json="$2"
  jq --argjson devlogs "$devlogs_json" '
    map(. + {
      orphan_candidate: (
        .type == "note" and
        (.project // "" | length > 0) and
        ([$devlogs[] | select(.project == .project)] | length == 0)
      )
    })
  ' <<< "$notes_json"
}

gather_window_work() {
  local window="$1"
  local from to beyond
  from=$(echo "$window" | jq -r '.from')
  to=$(echo "$window" | jq -r '.to')
  beyond=$(echo "$window" | jq -r '.beyond_lookback')

  if [[ "$beyond" == "true" ]]; then
    jq -n --argjson w "$window" '{recap_window: ($w + {days_empty: [], days: []})}'
    return
  fi

  local current="$from"
  local days_json="[]"
  local empty_days="[]"

  while [[ ! "$current" > "$to" ]]; do
    local day_name surfaced
    day_name=$(day_of_week "$current")
    surfaced=$(probe_date_surfaced "$current")

    local devlogs_arr="[]"
    local notes_arr="[]"

    while IFS= read -r rel_path; do
      [[ -z "$rel_path" ]] && continue
      local entry file_type
      entry=$(build_file_entry "$rel_path")
      file_type=$(echo "$entry" | jq -r '.type')

      if [[ "$file_type" == "devlog" ]]; then
        devlogs_arr=$(echo "$devlogs_arr" | jq --argjson e "$entry" '. + [$e]')
      else
        notes_arr=$(echo "$notes_arr" | jq --argjson e "$entry" '. + [$e]')
      fi
    done < <(echo "$surfaced" | jq -r '.[]?' 2>/dev/null)

    notes_arr=$(jq --argjson devlogs "$devlogs_arr" '
      map(
        . as $note |
        $note + {
          orphan_candidate: (
            ($note.type == "note") and
            (($note.project // "" | length) > 0) and
            (([$devlogs[] | select(.project == $note.project)] | length) == 0)
          )
        }
      )
    ' <<< "$notes_arr")

    local devlog_count notes_count
    devlog_count=$(echo "$devlogs_arr" | jq 'length')
    notes_count=$(echo "$notes_arr" | jq 'length')

    if [[ "$devlog_count" -eq 0 && "$notes_count" -eq 0 ]]; then
      # Today (= window `to`) being empty isn't a gap — it's just morning before
      # any work has been captured today. Only intermediate empty days count.
      if [[ "$current" != "$TARGET_DATE" ]]; then
        empty_days=$(echo "$empty_days" | jq --arg d "$current" '. + [$d]')
      fi
    else
      local day_obj
      day_obj=$(jq -n \
        --arg date "$current" \
        --arg day_name "$day_name" \
        --argjson devlogs "$devlogs_arr" \
        --argjson notes "$notes_arr" \
        '{date: $date, day_name: $day_name, devlogs: $devlogs, notes: $notes}')
      days_json=$(echo "$days_json" | jq --argjson d "$day_obj" '. + [$d]')
    fi

    current=$(date_add_days "$current" "+1")
    [[ -z "$current" ]] && break
  done

  jq -n \
    --argjson w "$window" \
    --argjson days_empty "$empty_days" \
    --argjson days "$days_json" \
    '{recap_window: ($w + {days_empty: $days_empty, days: $days})}'
}

# ── Recap Window + Window Work ───────────────────────────────────────

WINDOW=$(resolve_recap_window)
WINDOW_WORK=$(gather_window_work "$WINDOW")

# Yesterday for downstream consumers (legacy, used by ensure scripts and work-item sync)
YESTERDAY=$(date_add_days "$TARGET_DATE" "-1")
YESTERDAY_DAY=$(day_of_week "$YESTERDAY")

# ── File Existence Checks ────────────────────────────────────────────

JOURNAL_REL="5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md"
DAILY_HUB_REL="1. Daily/${TARGET_DATE}.md"
YESTERDAY_HUB_REL="1. Daily/${YESTERDAY}.md"

JOURNAL_EXISTS=false
JOURNAL_HAS_CONTEXT=false
DAILY_HUB_EXISTS=false

[[ -f "$VAULT/$JOURNAL_REL" ]] && JOURNAL_EXISTS=true
[[ -f "$VAULT/$DAILY_HUB_REL" ]] && DAILY_HUB_EXISTS=true

if [[ "$JOURNAL_EXISTS" == "true" ]]; then
  if grep -q "^## Recent Accomplishments" "$VAULT/$JOURNAL_REL" 2>/dev/null \
     && ! grep -qF '*(filled by /start-day)*' "$VAULT/$JOURNAL_REL" 2>/dev/null; then
    JOURNAL_HAS_CONTEXT=true
  fi
fi

# ── Todoist Tasks ─────────────────────────────────────────────────────

gather_todoist() {
  local raw
  raw=$(td task list --filter "overdue | today" --json --full 2>/dev/null) || {
    jq -n '{available: false, error: "td CLI failed or not authenticated", tasks: [], overdue_count: 0, today_count: 0}'
    return
  }

  echo "$raw" | jq empty 2>/dev/null || {
    jq -n '{available: false, error: "td returned invalid JSON", tasks: [], overdue_count: 0, today_count: 0}'
    return
  }

  local tasks_array
  tasks_array=$(echo "$raw" | jq 'if type == "array" then . elif .results then .results else [] end' 2>/dev/null || echo "[]")

  local overdue today_count total
  overdue=$(echo "$tasks_array" | jq "[.[] | select(.due.date != null and .due.date < \"$TARGET_DATE\")] | length" 2>/dev/null || echo 0)
  today_count=$(echo "$tasks_array" | jq "[.[] | select(.due.date != null and .due.date == \"$TARGET_DATE\")] | length" 2>/dev/null || echo 0)
  total=$(echo "$tasks_array" | jq 'length' 2>/dev/null || echo 0)

  jq -n \
    --argjson tasks "$tasks_array" \
    --argjson overdue "$overdue" \
    --argjson today "$today_count" \
    --argjson total "$total" \
    '{available: true, tasks: $tasks, overdue_count: $overdue, today_count: $today, total: $total}'
}

# ── Task Notes ───────────────────────────────────────────────────────

gather_task_notes() {
  local result="[]"
  local errors=()
  local count=0
  local todo_count=0
  local active_count=0
  local on_hold_count=0

  normalize_prop() {
    local v="$1"
    [[ "$v" == "(empty)" ]] && echo "" || echo "$v"
  }

  local files
  files=$(find "$VAULT" -path "*/Tasks/*.md" -not -path "*/Templates/*" 2>/dev/null)

  if [[ -z "$files" ]]; then
    jq -n '{available: true, tasks: [], count: 0, todo_count: 0, active_count: 0, on_hold_count: 0, errors: []}'
    return
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local rel_path="${file#$VAULT/}"
    local task_status
    local err_file
    err_file=$(mktemp)
    if ! task_status=$(obsidian property:read name=status path="$rel_path" 2>"$err_file"); then
      errors+=("$rel_path: $(cat "$err_file")")
      rm -f "$err_file"
      continue
    fi
    rm -f "$err_file"

    task_status=$(normalize_prop "$(echo "$task_status" | tr -d '"' | xargs)")

    if [[ "$task_status" == "todo" || "$task_status" == "active" || "$task_status" == "on-hold" ]]; then
      local priority due_date area project
      priority=$(normalize_prop "$(obsidian property:read name=priority path="$rel_path" 2>/dev/null | tr -d '"' | xargs)") || priority=""
      due_date=$(normalize_prop "$(obsidian property:read name=due_date path="$rel_path" 2>/dev/null | tr -d '"' | xargs)") || due_date=""
      area=$(normalize_prop "$(obsidian property:read name=area path="$rel_path" 2>/dev/null | tr -d '"' | xargs)") || area=""
      project=$(normalize_prop "$(obsidian property:read name=project path="$rel_path" 2>/dev/null | tr -d '"' | xargs)") || project=""

      result=$(echo "$result" | jq \
        --arg path "$rel_path" \
        --arg status "$task_status" \
        --arg priority "$priority" \
        --arg due_date "$due_date" \
        --arg area "$area" \
        --arg project "$project" \
        '. += [{path: $path, status: $status, priority: $priority, due_date: $due_date, area: $area, project: $project}]')

      count=$((count + 1))
      case "$task_status" in
        todo) todo_count=$((todo_count + 1));;
        active) active_count=$((active_count + 1));;
        on-hold) on_hold_count=$((on_hold_count + 1));;
      esac
    fi
  done <<< "$files"

  local errors_json="[]"
  if [[ ${#errors[@]} -gt 0 ]]; then
    errors_json=$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)
  fi

  jq -n \
    --argjson tasks "$result" \
    --argjson count "$count" \
    --argjson todo "$todo_count" \
    --argjson active "$active_count" \
    --argjson on_hold "$on_hold_count" \
    --argjson errors "$errors_json" \
    '{available: true, tasks: $tasks, count: $count, todo_count: $todo, active_count: $active, on_hold_count: $on_hold, errors: $errors}'
}

# ── Work-Item Integration (inert stub) ───────────────────────────────
# Not configured for this install. Emits valid empty JSON so downstream
# JSON assembly stays well-formed.

gather_workitems() { jq -n '{available: false, reason: "not configured for this install", work_items: []}'; }

# ── Evening Reflection ────────────────────────────────────────────────

gather_evening() {
  # Strict: an evening reflection is only "found" when an actual file exists at
  # 5. Resources/Personal/Journal/Evening Entries/{yesterday}.md. No morning-entry
  # fallback — if the evening didn't happen, that's signal, not something to paper
  # over. See Start-Day Iteration Findings 5-15 §2.
  local yesterday
  yesterday=$(date_add_days "$TARGET_DATE" "-1")
  local evening_file="$VAULT/5. Resources/Personal/Journal/Evening Entries/${yesterday}.md"

  if [[ -f "$evening_file" ]]; then
    local content
    content=$(cat "$evening_file" 2>/dev/null | head -80)
    jq -n --arg date "$yesterday" --arg content "$content" --arg source "evening_entries" \
      --arg path "5. Resources/Personal/Journal/Evening Entries/${yesterday}.md" \
      '{found: true, date: $date, source: $source, content: $content, path: $path, reason: null}'
    return
  fi

  jq -n --arg reason "no evening entry recorded" \
    '{found: false, date: null, source: null, content: null, path: null, reason: $reason}'
}

# ── Git Commit History (recap window) ────────────────────────────────
# Walk commits in [from..to] inclusive. Map each commit to projects/areas
# by inspecting touched files. Subject becomes the candidate theme bullet.

gather_commits() {
  local from="$1"
  local to="$2"

  # git log range: --since is inclusive, --until is exclusive of the next day
  local until_inclusive
  until_inclusive=$(date_add_days "$to" "+1")

  if ! git -C "$VAULT" rev-parse HEAD >/dev/null 2>&1; then
    jq -n '{available: false, error: "not a git repo or no commits", commits: []}'
    return
  fi

  local raw
  raw=$(git -C "$VAULT" log \
          --since="$from 00:00:00" \
          --until="$until_inclusive 00:00:00" \
          --pretty=format:'__COMMIT__%n%h%n%ai%n%s' \
          --name-only 2>/dev/null) || {
    jq -n '{available: false, error: "git log failed", commits: []}'
    return
  }

  local commits_arr="[]"
  local cur_sha="" cur_date="" cur_subject="" cur_files="[]"
  local in_files=false

  flush_commit() {
    [[ -z "$cur_sha" ]] && return

    # Derive projects + areas from file paths
    local projects_set="[]" areas_set="[]" kind
    kind=$(echo "$cur_subject" | sed -E 's/^([a-z]+)(\(.+\))?: .*/\1/' | head -c 16)
    [[ -z "$kind" || "$kind" == "$cur_subject" ]] && kind="other"

    # Parse projects from "2. Projects/{Area}/{Project}/..." and "Personal/{Project}/..."
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      local slug=""
      if [[ "$p" == "2. Projects/"*"/"* ]]; then
        slug=$(echo "$p" | awk -F/ '{print $3}' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      elif [[ "$p" == "Personal/"*"/"* && "$p" != "Personal/Thoughts"* ]]; then
        slug=$(echo "$p" | awk -F/ '{print $2}' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      fi
      [[ -n "$slug" ]] && projects_set=$(echo "$projects_set" | jq --arg s "$slug" '. + [$s] | unique')
    done < <(echo "$cur_files" | jq -r '.[]')

    # Areas: derive from "2. Projects/{Area}/" or "3. Areas/{Area}/"
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      local area_name=""
      if [[ "$p" == "2. Projects/"* ]]; then
        area_name=$(echo "$p" | awk -F/ '{print $2}' | tr '[:upper:]' '[:lower:]')
      elif [[ "$p" == "3. Areas/"* ]]; then
        area_name=$(echo "$p" | awk -F/ '{print $2}' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      elif [[ "$p" == "Personal/"* ]]; then
        area_name="personal"
      fi
      [[ -n "$area_name" ]] && areas_set=$(echo "$areas_set" | jq --arg a "$area_name" '. + [$a] | unique')
    done < <(echo "$cur_files" | jq -r '.[]')

    local commit_obj
    commit_obj=$(jq -n \
      --arg sha "$cur_sha" \
      --arg date "${cur_date:0:10}" \
      --arg subject "$cur_subject" \
      --arg kind "$kind" \
      --argjson files "$cur_files" \
      --argjson projects "$projects_set" \
      --argjson areas "$areas_set" \
      '{sha: $sha, date: $date, subject: $subject, kind: $kind, files: $files, projects: $projects, areas: $areas}')

    commits_arr=$(echo "$commits_arr" | jq --argjson c "$commit_obj" '. + [$c]')
  }

  while IFS= read -r line; do
    if [[ "$line" == "__COMMIT__" ]]; then
      flush_commit
      cur_sha="" cur_date="" cur_subject="" cur_files="[]"
      in_files=false
      # Read the next 3 lines: sha, date, subject
      IFS= read -r cur_sha
      IFS= read -r cur_date
      IFS= read -r cur_subject
      in_files=true
    elif [[ "$in_files" == "true" && -n "$line" ]]; then
      cur_files=$(echo "$cur_files" | jq --arg f "$line" '. + [$f]')
    fi
  done <<< "$raw"
  flush_commit

  jq -n --argjson c "$commits_arr" '{available: true, commits: $c}'
}

# ── Active Project Enumeration ───────────────────────────────────────
# Find all project hub files (type: project, status: active) under
# "2. Projects/{Area}/{Project}/{Project}.md" and "Personal/{Project}/{Project}.md".

# ── Recency Thresholds ───────────────────────────────────────────────
# Per Project Last-Touch Computation spec:
#   Hot:  0–3 days  (suppressed at render; tracked for completeness)
#   Warm: 4–13 days (surfaced in Needs Attention as "keep visible")
#   Cold: ≥14 days  (surfaced in Needs Attention as "archive candidates")
HOT_MAX_DAYS=3
WARM_MAX_DAYS=13

# ── Plan File Indexing (rule D) ──────────────────────────────────────
# Walk docs/superpowers/plans/*.md once. For each plan with a date and a
# resolvable project slug, emit an entry into a slug-keyed JSON object
# mapping slug → {date, path}. Slug resolution prefers the plan's
# `project:` frontmatter; falls back to a filename-suffix match against
# the active-project slug list passed in.
#
# Plan filename convention: YYYY-MM-DD-<slug-or-feature>.md
# Date source order: frontmatter `date:` → filename prefix YYYY-MM-DD.
#
# Output: JSON object {slug: {date, path}, ...}. Multiple plans for the
# same slug collapse to the max date.

build_plan_index() {
  local active_json="$1"
  local plans_dir="$VAULT/docs/superpowers/plans"
  local index="{}"

  [[ ! -d "$plans_dir" ]] && { echo "$index"; return; }

  # Build slug list for filename-suffix matching.
  # Sort longest-first so the most specific slug wins the fallback substring match
  # (e.g. "my-project-v2" beats "my-project" when both substring-match a plan filename).
  local known_slugs
  known_slugs=$(echo "$active_json" | jq -r '.[].slug' | awk '{print length, $0}' | sort -k1,1nr | cut -d' ' -f2-)

  local f base fname_date fm_date d slug
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    base=$(basename "$f" .md)

    # Filename prefix date YYYY-MM-DD
    if [[ "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})- ]]; then
      fname_date="${BASH_REMATCH[1]}"
    else
      fname_date=""
    fi

    fm_date=$(fm_value "$f" "date")
    if [[ "$fm_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      d="$fm_date"
    elif [[ -n "$fname_date" ]]; then
      d="$fname_date"
    else
      continue
    fi

    # Resolve slug: project: frontmatter wins, else suffix match.
    slug=$(fm_value "$f" "project")
    if [[ -z "$slug" ]]; then
      # Strip the YYYY-MM-DD- prefix, scan known slugs for a suffix match.
      # known_slugs is sorted longest-first so the most specific slug wins
      # (prevents "my-project" from grabbing a plan that belongs to "my-project-v2").
      local stripped="${base#????-??-??-}"
      while IFS= read -r candidate; do
        [[ -z "$candidate" ]] && continue
        if [[ "$stripped" == "$candidate"* || "$stripped" == *"$candidate"* ]]; then
          slug="$candidate"
          break
        fi
      done <<< "$known_slugs"
    fi

    [[ -z "$slug" ]] && continue

    local rel="${f#$VAULT/}"
    # Upsert: keep max date per slug
    index=$(echo "$index" | jq \
      --arg slug "$slug" --arg date "$d" --arg path "$rel" \
      '
      if (.[$slug] // null) == null or .[$slug].date < $date
      then .[$slug] = {date: $date, path: $path}
      else .
      end
      ')
  done < <(find "$plans_dir" -maxdepth 1 -type f -name "*.md" 2>/dev/null)

  echo "$index"
}

gather_active_projects() {
  local hubs_arr="[]"

  # Pattern 1: 2. Projects/{Area}/{Project}/{Project}.md
  while IFS= read -r hub; do
    [[ -z "$hub" ]] && continue
    local base dir
    base=$(basename "$hub" .md)
    dir=$(basename "$(dirname "$hub")")
    [[ "$base" != "$dir" ]] && continue
    local t s
    t=$(fm_value "$hub" "type")
    s=$(fm_value "$hub" "status")
    if [[ "$t" == "project" && "$s" == "active" ]]; then
      local slug area rel
      slug=$(fm_value "$hub" "project")
      area=$(fm_value "$hub" "area")
      rel="${hub#$VAULT/}"
      if [[ -z "$slug" ]]; then
        echo "WARN: hub $rel has type:project,status:active but missing project: slug — skipping" >&2
        continue
      fi
      hubs_arr=$(echo "$hubs_arr" | jq \
        --arg slug "$slug" --arg area "$area" --arg path "$rel" \
        --argjson rank "$(area_rank "$area")" \
        '. + [{slug: $slug, area: $area, hub_path: $path, area_priority_rank: $rank}]')
    fi
  done < <(find "$VAULT/2. Projects" -mindepth 3 -maxdepth 3 -name "*.md" 2>/dev/null)

  # Pattern 2: Personal/{Project}/{Project}.md
  while IFS= read -r hub; do
    [[ -z "$hub" ]] && continue
    local base dir
    base=$(basename "$hub" .md)
    dir=$(basename "$(dirname "$hub")")
    [[ "$base" != "$dir" ]] && continue
    local t s
    t=$(fm_value "$hub" "type")
    s=$(fm_value "$hub" "status")
    if [[ "$t" == "project" && "$s" == "active" ]]; then
      local slug area rel
      slug=$(fm_value "$hub" "project")
      area=$(fm_value "$hub" "area")
      rel="${hub#$VAULT/}"
      if [[ -z "$slug" ]]; then
        echo "WARN: hub $rel has type:project,status:active but missing project: slug — skipping" >&2
        continue
      fi
      hubs_arr=$(echo "$hubs_arr" | jq \
        --arg slug "$slug" --arg area "$area" --arg path "$rel" \
        --argjson rank "$(area_rank "$area")" \
        '. + [{slug: $slug, area: $area, hub_path: $path, area_priority_rank: $rank}]')
    fi
  done < <(find "$VAULT/Personal" -mindepth 2 -maxdepth 2 -name "*.md" 2>/dev/null)

  echo "$hubs_arr"
}

# ── Project Recency Computation (rule C + rule D) ────────────────────
# For each active project, compute last_activity_date using the spec's
# recommended rule:
#
#   project_last_touch = max(
#     latest .md with date: frontmatter in 2. Projects/<area>/<project>/ or Personal/<project>/,
#     latest plan file in docs/superpowers/plans/ referencing this project
#   )
#
# Emits per-project: {slug, area, hub_path, last_activity_date,
# days_silent, area_priority_rank, recency_source, plan_path,
# latest_in_project_age_days}.
#
# recency_source ∈ {"in-project", "plan", "none"}.
# plan_path is set iff recency_source == "plan".
#
# CONSUMER CONTRACT: branch on recency_source first. When "none",
# last_activity_date == "never" and days_silent == 999 are sentinels —
# do not feed them to date arithmetic or treat 999 as a real day count.

gather_project_recency() {
  local active_json="$1"
  local plan_index="$2"
  local result_arr="[]"

  while IFS= read -r hub_json; do
    [[ -z "$hub_json" || "$hub_json" == "null" ]] && continue
    local slug area hub_path project_folder
    slug=$(echo "$hub_json" | jq -r '.slug')
    area=$(echo "$hub_json" | jq -r '.area')
    hub_path=$(echo "$hub_json" | jq -r '.hub_path')
    project_folder=$(dirname "$hub_path")

    # (C) subtree scan — any .md with date: frontmatter
    local in_project_max=""
    local f f_date
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      f_date=$(fm_value "$f" "date")
      [[ ! "$f_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && continue
      if [[ -z "$in_project_max" || "$f_date" > "$in_project_max" ]]; then
        in_project_max="$f_date"
      fi
    done < <(find "$VAULT/$project_folder" -type f -name "*.md" 2>/dev/null)

    # (D) plan lookup
    local plan_date plan_path
    plan_date=$(echo "$plan_index" | jq -r --arg slug "$slug" '.[$slug].date // ""')
    plan_path=$(echo "$plan_index" | jq -r --arg slug "$slug" '.[$slug].path // ""')

    # Combine
    local last_activity recency_source
    if [[ -n "$plan_date" && ( -z "$in_project_max" || "$plan_date" > "$in_project_max" ) ]]; then
      last_activity="$plan_date"
      recency_source="plan"
    elif [[ -n "$in_project_max" ]]; then
      last_activity="$in_project_max"
      recency_source="in-project"
      plan_path=""
    else
      last_activity=""
      recency_source="none"
      plan_path=""
    fi

    # days_silent
    local days_silent
    if [[ -z "$last_activity" ]] || [[ ! "$last_activity" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      days_silent=999
      last_activity="never"
    else
      if [[ "$DATE_FLAVOR" == "bsd" ]]; then
        local t1 t2
        t1=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" +%s 2>/dev/null)
        t2=$(date -j -f "%Y-%m-%d" "$last_activity" +%s 2>/dev/null)
        days_silent=$(( (t1 - t2) / 86400 ))
      else
        days_silent=$(( ($(date -d "$TARGET_DATE" +%s) - $(date -d "$last_activity" +%s)) / 86400 ))
      fi
    fi

    # latest_in_project_age_days — set only when recency_source == "plan" and an in-project max exists,
    # so the render layer can say "latest in-project file is Md old". Null otherwise.
    local latest_in_project_age=""
    if [[ "$recency_source" == "plan" && -n "$in_project_max" && "$in_project_max" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      if [[ "$DATE_FLAVOR" == "bsd" ]]; then
        local lt1 lt2
        lt1=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" +%s 2>/dev/null)
        lt2=$(date -j -f "%Y-%m-%d" "$in_project_max" +%s 2>/dev/null)
        latest_in_project_age=$(( (lt1 - lt2) / 86400 ))
      else
        latest_in_project_age=$(( ($(date -d "$TARGET_DATE" +%s) - $(date -d "$in_project_max" +%s)) / 86400 ))
      fi
    fi

    result_arr=$(echo "$result_arr" | jq \
      --arg slug "$slug" --arg area "$area" --arg path "$hub_path" \
      --arg last "$last_activity" --argjson days "$days_silent" \
      --argjson rank "$(area_rank "$area")" \
      --arg src "$recency_source" --arg plan "$plan_path" \
      --arg lia "$latest_in_project_age" \
      '. + [{
         slug: $slug, area: $area, hub_path: $path,
         last_activity_date: $last, days_silent: $days,
         area_priority_rank: $rank,
         recency_source: $src,
         plan_path: (if $plan == "" then null else $plan end),
         latest_in_project_age_days: (if $lia == "" then null else ($lia | tonumber) end)
       }]')
  done < <(echo "$active_json" | jq -c '.[]')

  echo "$result_arr"
}

# ── Band Classification ──────────────────────────────────────────────
# Split a recency-annotated active project list into hot/warm/cold arrays.

band_projects() {
  local recency_json="$1"
  local hot warm cold

  hot=$(echo "$recency_json" | jq --argjson maxhot "$HOT_MAX_DAYS" \
    '[.[] | select(.days_silent <= $maxhot)]')
  warm=$(echo "$recency_json" | jq \
    --argjson maxhot "$HOT_MAX_DAYS" --argjson maxwarm "$WARM_MAX_DAYS" \
    '[.[] | select(.days_silent > $maxhot and .days_silent <= $maxwarm)]')
  cold=$(echo "$recency_json" | jq --argjson maxwarm "$WARM_MAX_DAYS" \
    '[.[] | select(.days_silent > $maxwarm)
      | . + {reason: (if .last_activity_date == "never"
                      then "no devlog or knowledge note in this project folder"
                      else "no devlog or knowledge note dated within \($maxwarm + 1) days"
                      end)}
     ]')

  jq -n --argjson h "$hot" --argjson w "$warm" --argjson c "$cold" \
    '{hot: $h, warm: $w, cold: $c}'
}

# ── Gather All Sources ────────────────────────────────────────────────

TODOIST=$(gather_todoist)
WORKITEMS=$(gather_workitems)
EVENING=$(gather_evening)
TASK_NOTES=$(gather_task_notes)
COMMITS=$(gather_commits "$(echo "$WINDOW_WORK" | jq -r '.recap_window.from')" "$(echo "$WINDOW_WORK" | jq -r '.recap_window.to')")
ACTIVE_PROJECTS=$(gather_active_projects)
PLAN_INDEX=$(build_plan_index "$ACTIVE_PROJECTS")
PROJECT_RECENCY=$(gather_project_recency "$ACTIVE_PROJECTS" "$PLAN_INDEX")
BANDS=$(band_projects "$PROJECT_RECENCY")
HOT=$(echo "$BANDS" | jq '.hot')
WARM=$(echo "$BANDS" | jq '.warm')
COLD=$(echo "$BANDS" | jq '.cold')

# ── Build Source Manifest ─────────────────────────────────────────────

window_from=$(echo "$WINDOW_WORK" | jq -r '.recap_window.from')
window_to=$(echo "$WINDOW_WORK" | jq -r '.recap_window.to')
window_beyond=$(echo "$WINDOW_WORK" | jq -r '.recap_window.beyond_lookback')
window_devlog_count=$(echo "$WINDOW_WORK" | jq '[.recap_window.days[].devlogs | length] | add // 0')
window_note_count=$(echo "$WINDOW_WORK" | jq '[.recap_window.days[].notes | length] | add // 0')

todoist_available=$(echo "$TODOIST" | jq -r '.available' 2>/dev/null || echo false)
todoist_error=$(echo "$TODOIST" | jq -r '.error // empty' 2>/dev/null)
workitems_available=$(echo "$WORKITEMS" | jq -r '.available' 2>/dev/null || echo false)
workitems_error=$(echo "$WORKITEMS" | jq -r '.error // empty' 2>/dev/null)
evening_found=$(echo "$EVENING" | jq -r '.found' 2>/dev/null || echo false)
task_notes_count=$(echo "$TASK_NOTES" | jq -r '.count' 2>/dev/null || echo 0)
task_notes_todo=$(echo "$TASK_NOTES" | jq -r '.todo_count' 2>/dev/null || echo 0)
task_notes_active=$(echo "$TASK_NOTES" | jq -r '.active_count' 2>/dev/null || echo 0)
task_notes_on_hold=$(echo "$TASK_NOTES" | jq -r '.on_hold_count' 2>/dev/null || echo 0)
task_notes_errors=$(echo "$TASK_NOTES" | jq -r '.errors | length' 2>/dev/null || echo 0)

if [[ "$window_beyond" == "true" ]]; then
  recap_summary="beyond lookback: no captured work in last 7 days"
elif [[ "$window_from" == "$window_to" ]]; then
  recap_summary="single-day window ($window_from): $window_devlog_count devlogs, $window_note_count notes"
else
  recap_summary="window $window_from → $window_to: $window_devlog_count devlogs, $window_note_count notes"
fi

hot_count=$(echo "$HOT" | jq 'length')
warm_count=$(echo "$WARM" | jq 'length')
cold_count=$(echo "$COLD" | jq 'length')

MANIFEST=$(jq -n \
  --arg recap "$recap_summary" \
  --arg todoist "$(if [[ "$todoist_available" == "true" ]]; then oc=$(echo "$TODOIST" | jq -r '.overdue_count'); tc=$(echo "$TODOIST" | jq -r '.today_count'); echo "success: $oc overdue, $tc today"; else echo "failed: $todoist_error"; fi)" \
  --arg workitems "$(if [[ "$workitems_available" == "true" ]]; then echo "success"; else echo "failed: $workitems_error"; fi)" \
  --arg evening "$(if [[ "$evening_found" == "true" ]]; then echo "success"; else echo "not found"; fi)" \
  --arg task_notes "$(if [[ "$task_notes_errors" -eq 0 ]]; then echo "success: $task_notes_count found ($task_notes_todo todo, $task_notes_active active, $task_notes_on_hold on-hold)"; else echo "partial: $task_notes_count found, $task_notes_errors errors"; fi)" \
  --arg project_recency "success: ${warm_count} warm, ${cold_count} cold, ${hot_count} hot (suppressed)" \
  '{recap_window: $recap, todoist: $todoist, workitems: $workitems, evening: $evening, task_notes: $task_notes, project_recency: $project_recency, linear: "pending (MCP — call from skill)", calendar: "not implemented"}')

# ── Output Combined JSON ─────────────────────────────────────────────

jq -n \
  --arg today "$TARGET_DATE" \
  --arg today_day "$TARGET_DAY" \
  --arg yesterday "$YESTERDAY" \
  --arg yesterday_day "$YESTERDAY_DAY" \
  --arg journal_path "$JOURNAL_REL" \
  --argjson journal_exists "$JOURNAL_EXISTS" \
  --argjson journal_has_context "$JOURNAL_HAS_CONTEXT" \
  --arg daily_hub_path "$DAILY_HUB_REL" \
  --argjson daily_hub_exists "$DAILY_HUB_EXISTS" \
  --arg yesterday_hub_path "$YESTERDAY_HUB_REL" \
  --argjson window_work "$WINDOW_WORK" \
  --argjson todoist "$TODOIST" \
  --argjson workitems "$WORKITEMS" \
  --argjson evening "$EVENING" \
  --argjson task_notes "$TASK_NOTES" \
  --argjson commits "$COMMITS" \
  --argjson active_projects "$ACTIVE_PROJECTS" \
  --argjson hot "$HOT" \
  --argjson warm "$WARM" \
  --argjson cold "$COLD" \
  --argjson source_manifest "$MANIFEST" \
  '{
    dates: {today: $today, today_day: $today_day, yesterday: $yesterday, yesterday_day: $yesterday_day},
    files: {journal_path: $journal_path, journal_exists: $journal_exists, journal_has_context: $journal_has_context, daily_hub_path: $daily_hub_path, daily_hub_exists: $daily_hub_exists, yesterday_hub_path: $yesterday_hub_path},
    recap_window: $window_work.recap_window,
    todoist: $todoist,
    workitems: $workitems,
    evening: $evening,
    task_notes: $task_notes,
    commits: $commits,
    active_projects: $active_projects,
    hot: $hot,
    warm: $warm,
    cold: $cold,
    source_manifest: $source_manifest
  }'
