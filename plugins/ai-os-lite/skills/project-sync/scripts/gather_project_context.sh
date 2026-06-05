#!/bin/bash
# gather_project_context.sh — Deterministic project context gathering.
# Called by /project-sync skill as Step 1. Outputs structured JSON to stdout.
# Usage: gather_project_context.sh <project-slug> [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Uses: raw filesystem ops
# Does NOT: call MCP tools, write files, make judgment calls

set -uo pipefail

# ── Arguments ────────────────────────────────────────────────────────

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  echo '{"error": "Usage: gather_project_context.sh <project-slug> [VAULT_PATH]"}' >&2
  exit 1
fi

VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

if [[ ! -d "$VAULT" ]]; then
  echo '{"error": "Vault directory not found: '"$VAULT"'"}' >&2
  exit 1
fi

TODAY="${3:-$(date +%Y-%m-%d)}"

# ── Platform Detection (BSD vs GNU date) ─────────────────────────────

if date -j -f "%Y-%m-%d" "2000-01-01" +%s &>/dev/null; then
  DATE_FLAVOR="bsd"
else
  DATE_FLAVOR="gnu"
fi

date_add_days() {
  if [[ "$DATE_FLAVOR" == "bsd" ]]; then
    date -j -v"${2}d" -f "%Y-%m-%d" "$1" +%Y-%m-%d 2>/dev/null
  else
    date -d "$1 ${2} days" +%Y-%m-%d 2>/dev/null
  fi
}

# ── Utilities (shared with gather_morning_context.sh) ────────────────

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
  local file="$1" lines="${2:-30}"
  awk '/^---$/{if(f){p=1;next}f=1;next}p' "$file" 2>/dev/null | head -"$lines"
}

# ── Project Resolution ───────────────────────────────────────────────
# Resolve slug → area + display name + hub path + devlog dir
# Uses filesystem discovery, not a hardcoded table.

resolve_project() {
  local slug="$1"
  local projects_dir="$VAULT/2. Projects"

  # Search each area directory for a matching project folder
  for area_dir in "$projects_dir"/*/; do
    [[ ! -d "$area_dir" ]] && continue
    local area_name
    area_name=$(basename "$area_dir")

    for project_dir in "$area_dir"*/; do
      [[ ! -d "$project_dir" ]] && continue
      local project_name
      project_name=$(basename "$project_dir")

      # Generate slug from folder name: lowercase, spaces→hyphens, strip non-alnum
      local generated_slug
      generated_slug=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g')

      if [[ "$generated_slug" == "$slug" ]]; then
        # Determine area slug
        local area_slug
        area_slug=$(echo "$area_name" | tr '[:upper:]' '[:lower:]')

        # Find the hub file (project name.md in the project dir)
        local hub_file=""
        if [[ -f "$project_dir/${project_name}.md" ]]; then
          hub_file="2. Projects/${area_name}/${project_name}/${project_name}.md"
        fi

        local devlog_dir="2. Projects/${area_name}/${project_name}/Dev Log"
        local notes_dir="2. Projects/${area_name}/${project_name}/Notes"
        local tasks_dir="2. Projects/${area_name}/${project_name}/Tasks"

        jq -n \
          --arg slug "$slug" \
          --arg area "$area_slug" \
          --arg area_display "$area_name" \
          --arg project_name "$project_name" \
          --arg hub_path "$hub_file" \
          --argjson hub_exists "$(if [[ -n "$hub_file" && -f "$VAULT/$hub_file" ]]; then echo true; else echo false; fi)" \
          --arg devlog_dir "$devlog_dir" \
          --argjson devlog_dir_exists "$(if [[ -d "$VAULT/$devlog_dir" ]]; then echo true; else echo false; fi)" \
          --arg notes_dir "$notes_dir" \
          --argjson notes_dir_exists "$(if [[ -d "$VAULT/$notes_dir" ]]; then echo true; else echo false; fi)" \
          --arg tasks_dir "$tasks_dir" \
          --argjson tasks_dir_exists "$(if [[ -d "$VAULT/$tasks_dir" ]]; then echo true; else echo false; fi)" \
          '{slug: $slug, area: $area, area_display: $area_display, project_name: $project_name, hub_path: $hub_path, hub_exists: $hub_exists, devlog_dir: $devlog_dir, devlog_dir_exists: $devlog_dir_exists, notes_dir: $notes_dir, notes_dir_exists: $notes_dir_exists, tasks_dir: $tasks_dir, tasks_dir_exists: $tasks_dir_exists}'
        return 0
      fi
    done
  done

  # Not found
  jq -n --arg slug "$slug" '{slug: $slug, error: "Project not found for slug", hub_exists: false}'
  return 1
}

PROJECT_JSON=$(resolve_project "$SLUG")
PROJECT_FOUND=$(echo "$PROJECT_JSON" | jq -r '.hub_exists' 2>/dev/null)

if [[ "$PROJECT_FOUND" != "true" ]]; then
  # Output partial result so the skill can report the error
  jq -n \
    --arg today "$TODAY" \
    --argjson project "$PROJECT_JSON" \
    '{today: $today, project: $project, hub: null, devlogs: [], recent_notes: [], workitems: null, source_manifest: {project_resolution: "failed", hub: "skipped", devlogs: "skipped", recent_notes: "skipped", workitems: "skipped", linear: "pending (MCP)"}}'
  exit 0
fi

# Extract resolved paths
HUB_PATH=$(echo "$PROJECT_JSON" | jq -r '.hub_path')
DEVLOG_DIR=$(echo "$PROJECT_JSON" | jq -r '.devlog_dir')
NOTES_DIR=$(echo "$PROJECT_JSON" | jq -r '.notes_dir')
TASKS_DIR=$(echo "$PROJECT_JSON" | jq -r '.tasks_dir')
AREA=$(echo "$PROJECT_JSON" | jq -r '.area')

# ── Hub Current Status Extraction ────────────────────────────────────

extract_current_status() {
  local hub_file="$VAULT/$HUB_PATH"
  [[ ! -f "$hub_file" ]] && { echo '{"found": false}'; return; }

  # Extract everything between "## Current Status" or "### Current Status" and the next same-or-higher heading
  local section
  section=$(awk '/^##+ Current Status/{p=1;lvl=length($1);next}/^#{2,}/{if(p && length($1)<=lvl)exit}p' "$hub_file" 2>/dev/null)

  if [[ -z "$section" ]]; then
    echo '{"found": false}'
    return
  fi

  # v2 format: just Current Status text + optional Blocked
  local current_status_text
  current_status_text=$(echo "$section" | sed '/^<!-- /d')

  # v1 compat: extract sub-sections if they exist
  local last_session next_actions blocked progress_summary
  last_session=$(echo "$section" | grep '^\*\*Last session\*\*' | head -1)
  next_actions=$(echo "$section" | awk '/^### Next Actions/{p=1;next}/^### /{if(p)exit}p')
  blocked=$(echo "$section" | awk '/^### Blocked/{p=1;next}/^### /{if(p)exit}p')
  progress_summary=$(echo "$section" | awk '/^### Progress Summary/{p=1;next}/^### |^## /{if(p)exit}p')

  jq -n \
    --arg current_status_text "$current_status_text" \
    --arg last_session "$last_session" \
    --arg next_actions "$next_actions" \
    --arg blocked "$blocked" \
    --arg progress_summary "$progress_summary" \
    '{found: true, current_status_text: $current_status_text, last_session: $last_session, next_actions: $next_actions, blocked: $blocked, progress_summary: $progress_summary}'
}

HUB_STATUS=$(extract_current_status)

# ── Devlog Discovery ─────────────────────────────────────────────────
# Find the N most recent devlogs for this project (by filename date prefix)

gather_project_devlogs() {
  local devlog_path="$VAULT/$DEVLOG_DIR"
  [[ ! -d "$devlog_path" ]] && { echo "[]"; return; }

  local result="["
  local first=true
  local count=0
  local max_devlogs=5

  # Sort by filename descending (most recent first)
  local files
  files=$(find "$devlog_path" -name "*.md" -type f 2>/dev/null | sort -r)

  if [[ -z "$files" ]]; then
    echo "[]"
    return
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ "$count" -ge "$max_devlogs" ]] && break

    local rel="${file#$VAULT/}"
    local filename
    filename=$(basename "$file" .md)

    # Extract date from filename (YYYY-MM-DD prefix)
    local devlog_date
    devlog_date=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "")

    # Calculate days ago
    local days_ago=-1
    if [[ -n "$devlog_date" && "$DATE_FLAVOR" == "bsd" ]]; then
      local devlog_epoch today_epoch
      devlog_epoch=$(date -j -f "%Y-%m-%d" "$devlog_date" +%s 2>/dev/null || echo 0)
      today_epoch=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || echo 0)
      if [[ "$devlog_epoch" -gt 0 && "$today_epoch" -gt 0 ]]; then
        days_ago=$(( (today_epoch - devlog_epoch) / 86400 ))
      fi
    elif [[ -n "$devlog_date" && "$DATE_FLAVOR" == "gnu" ]]; then
      local devlog_epoch today_epoch
      devlog_epoch=$(date -d "$devlog_date" +%s 2>/dev/null || echo 0)
      today_epoch=$(date -d "$TODAY" +%s 2>/dev/null || echo 0)
      if [[ "$devlog_epoch" -gt 0 && "$today_epoch" -gt 0 ]]; then
        days_ago=$(( (today_epoch - devlog_epoch) / 86400 ))
      fi
    fi

    local topic area project preview tasks_json

    topic=$(fm_value "$file" "session_topic")
    area=$(fm_value "$file" "area")
    project=$(fm_value "$file" "project")
    preview=$(content_preview "$file" 30 | head -c 800)

    local tasks_raw
    tasks_raw=$(fm_list "$file" "tasks")
    if [[ -n "$tasks_raw" ]]; then
      tasks_json=$(echo "$tasks_raw" | jq -R . | jq -s .)
    else
      tasks_json="[]"
    fi

    [[ "$first" == "true" ]] && first=false || result+=","
    result+=$(jq -n \
      --arg path "$rel" \
      --arg filename "$filename" \
      --arg date "$devlog_date" \
      --argjson days_ago "$days_ago" \
      --arg session_topic "$topic" \
      --arg project "$project" \
      --arg area "$area" \
      --argjson tasks "$tasks_json" \
      --arg preview "$preview" \
      '{path: $path, filename: $filename, date: $date, days_ago: $days_ago, session_topic: $session_topic, project: $project, area: $area, tasks: $tasks, preview: $preview}')

    count=$((count + 1))
  done <<< "$files"

  result+="]"
  echo "$result"
}

DEVLOGS=$(gather_project_devlogs)

# ── Knowledge Notes (enhanced scan) ────────────────────────────────
# Find notes in the project's Notes/ folder, scan for resolution sections

scan_knowledge_notes() {
  local notes_path="$VAULT/$NOTES_DIR"
  [[ ! -d "$notes_path" ]] && { echo "[]"; return; }

  local result="["
  local first=true

  for file in "$notes_path"/*.md; do
    [[ ! -f "$file" ]] && continue

    local rel="${file#$VAULT/}"
    local name
    name=$(basename "$file" .md)
    local status
    status=$(fm_value "$file" "status")

    # Check modification time (days ago)
    local modified_days_ago=-1
    if [[ "$DATE_FLAVOR" == "bsd" ]]; then
      local mod_epoch today_epoch
      mod_epoch=$(stat -f %m "$file" 2>/dev/null || echo 0)
      today_epoch=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || echo 0)
      [[ "$mod_epoch" -gt 0 && "$today_epoch" -gt 0 ]] && modified_days_ago=$(( (today_epoch - mod_epoch) / 86400 ))
    else
      local mod_epoch today_epoch
      mod_epoch=$(stat -c %Y "$file" 2>/dev/null || echo 0)
      today_epoch=$(date -d "$TODAY" +%s 2>/dev/null || echo 0)
      [[ "$mod_epoch" -gt 0 && "$today_epoch" -gt 0 ]] && modified_days_ago=$(( (today_epoch - mod_epoch) / 86400 ))
    fi

    # Scan for resolution-pattern headings
    local has_resolution=false
    local resolution_heading=""
    local match
    match=$(grep -iE '^#{1,3}\s*(resolution|update|completed|what changed)' "$file" 2>/dev/null | head -1)
    if [[ -n "$match" ]]; then
      has_resolution=true
      resolution_heading="$match"
    fi

    [[ "$first" == "true" ]] && first=false || result+=","
    result+=$(jq -n \
      --arg path "$rel" \
      --arg name "$name" \
      --arg status "$status" \
      --argjson modified_days_ago "$modified_days_ago" \
      --argjson has_resolution_section "$has_resolution" \
      --arg resolution_heading "$resolution_heading" \
      '{path: $path, name: $name, status: $status, modified_days_ago: $modified_days_ago, has_resolution_section: $has_resolution_section, resolution_heading: $resolution_heading}')
  done

  result+="]"
  echo "$result"
}

KNOWLEDGE_NOTES=$(scan_knowledge_notes)

# ── External Work Items (inert stub) ─────────────────────────────────

gather_workitems() { jq -n '{available: false, reason: "not configured for this install", work_items: []}'; }

WORKITEMS=$(gather_workitems)

# ── Stale Detection ──────────────────────────────────────────────────
# Check how many days since the last devlog

compute_staleness() {
  local most_recent_devlog
  most_recent_devlog=$(echo "$DEVLOGS" | jq -r '.[0].date // empty' 2>/dev/null)

  if [[ -z "$most_recent_devlog" ]]; then
    jq -n '{last_devlog_date: null, days_since_last_devlog: -1, is_stale: true, stale_threshold: 7}'
    return
  fi

  local days_since
  days_since=$(echo "$DEVLOGS" | jq -r '.[0].days_ago' 2>/dev/null)

  local is_stale=false
  if [[ "$days_since" -ge 7 ]]; then
    is_stale=true
  fi

  jq -n \
    --arg last_date "$most_recent_devlog" \
    --argjson days_since "$days_since" \
    --argjson is_stale "$is_stale" \
    '{last_devlog_date: $last_date, days_since_last_devlog: $days_since, is_stale: $is_stale, stale_threshold: 7}'
}

STALENESS=$(compute_staleness)

# ── Task Notes ──────────────────────────────────────────────────────
# Find all task notes in the project's Tasks/ folder

gather_task_notes() {
  local tasks_path="$VAULT/$TASKS_DIR"
  [[ ! -d "$tasks_path" ]] && { echo "[]"; return; }

  local result="["
  local first=true

  for file in "$tasks_path"/*.md; do
    [[ ! -f "$file" ]] && continue

    local rel="${file#$VAULT/}"
    local name
    name=$(basename "$file" .md)
    local status date external_id
    status=$(fm_value "$file" "status")
    date=$(fm_value "$file" "date")
    external_id=$(fm_value "$file" "external_id")
    local priority due_date scheduled_date done_date blocked_by
    priority=$(fm_value "$file" "priority")
    due_date=$(fm_value "$file" "due_date")
    scheduled_date=$(fm_value "$file" "scheduled_date")
    done_date=$(fm_value "$file" "done_date")
    blocked_by=$(fm_value "$file" "blocked_by")

    # Parse wikilinks from body (after frontmatter)
    local linked_notes
    linked_notes=$(awk '/^---$/{if(f){p=1;next}f=1;next}p' "$file" 2>/dev/null \
      | grep -oE '\[\[[^]]+\]\]' | sort -u | jq -R . | jq -s .)
    [[ -z "$linked_notes" || "$linked_notes" == "null" ]] && linked_notes="[]"

    # Find most recent devlog referencing this task
    local last_ref=""
    local days_since_activity=-1
    if [[ -d "$VAULT/$DEVLOG_DIR" ]]; then
      last_ref=$(grep -rl "\[\[$name\]\]" "$VAULT/$DEVLOG_DIR"/*.md 2>/dev/null \
        | xargs -I{} basename {} .md 2>/dev/null \
        | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -r | head -1)
      if [[ -n "$last_ref" ]]; then
        if [[ "$DATE_FLAVOR" == "bsd" ]]; then
          local ref_epoch today_epoch
          ref_epoch=$(date -j -f "%Y-%m-%d" "$last_ref" +%s 2>/dev/null || echo 0)
          today_epoch=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || echo 0)
          [[ "$ref_epoch" -gt 0 && "$today_epoch" -gt 0 ]] && days_since_activity=$(( (today_epoch - ref_epoch) / 86400 ))
        else
          local ref_epoch today_epoch
          ref_epoch=$(date -d "$last_ref" +%s 2>/dev/null || echo 0)
          today_epoch=$(date -d "$TODAY" +%s 2>/dev/null || echo 0)
          [[ "$ref_epoch" -gt 0 && "$today_epoch" -gt 0 ]] && days_since_activity=$(( (today_epoch - ref_epoch) / 86400 ))
        fi
      fi
    fi

    local is_stale=false
    [[ "$days_since_activity" -ge 7 ]] && is_stale=true

    # Handle null for last_ref (--arg always produces string, need JSON null)
    local last_ref_json="null"
    [[ -n "$last_ref" ]] && last_ref_json="\"$last_ref\""

    [[ "$first" == "true" ]] && first=false || result+=","
    result+=$(jq -n \
      --arg path "$rel" \
      --arg name "$name" \
      --arg status "$status" \
      --arg date "$date" \
      --arg priority "$priority" \
      --arg due_date "$due_date" \
      --arg scheduled_date "$scheduled_date" \
      --arg done_date "$done_date" \
      --arg blocked_by "$blocked_by" \
      --arg external_id "$external_id" \
      --argjson linked_notes "$linked_notes" \
      --argjson last_devlog_referencing "$last_ref_json" \
      --argjson days_since_activity "$days_since_activity" \
      --argjson is_stale "$is_stale" \
      '{path: $path, name: $name, status: $status, date: $date, priority: $priority, due_date: $due_date, scheduled_date: $scheduled_date, done_date: $done_date, blocked_by: $blocked_by, external_id: $external_id, linked_notes: $linked_notes, last_devlog_referencing: $last_devlog_referencing, days_since_activity: $days_since_activity, is_stale: $is_stale}')
  done

  result+="]"
  echo "$result"
}

TASK_NOTES=$(gather_task_notes)

# ── Cross-Project Devlogs ──────────────────────────────────────────
# Search all Dev Log folders for mentions of this project (14-day window)

find_cross_project_devlogs() {
  local project_name
  project_name=$(echo "$PROJECT_JSON" | jq -r '.project_name')
  local cutoff
  cutoff=$(date_add_days "$TODAY" "-14")

  local projects_dir="$VAULT/2. Projects"
  local result="["
  local first=true

  # Search all Dev Log folders EXCEPT this project's
  local files
  files=$(grep -rl "\[\[$project_name\]\]" "$projects_dir"/*/*/Dev\ Log/*.md 2>/dev/null \
    | grep -v "$DEVLOG_DIR" || true)

  if [[ -z "$files" ]]; then
    echo "[]"
    return
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    local devlog_date
    devlog_date=$(basename "$file" .md | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "")
    [[ -z "$devlog_date" ]] && continue

    # Only include if within 14-day window
    [[ "$devlog_date" < "$cutoff" ]] && continue

    local rel="${file#$VAULT/}"
    local devlog_project
    devlog_project=$(fm_value "$file" "project")

    # Get the line mentioning this project for context
    local mention_context
    mention_context=$(grep -n "\[\[$project_name\]\]" "$file" 2>/dev/null | head -1)

    [[ "$first" == "true" ]] && first=false || result+=","
    result+=$(jq -n \
      --arg path "$rel" \
      --arg project "$devlog_project" \
      --arg date "$devlog_date" \
      --arg mention_context "$mention_context" \
      '{path: $path, project: $project, date: $date, mention_context: $mention_context}')
  done <<< "$files"

  result+="]"
  echo "$result"
}

CROSS_PROJECT=$(find_cross_project_devlogs)

# ── Build Source Manifest ────────────────────────────────────────────

devlog_count=$(echo "$DEVLOGS" | jq 'length' 2>/dev/null || echo 0)
workitems_available=$(echo "$WORKITEMS" | jq -r '.available' 2>/dev/null || echo false)

task_count=$(echo "$TASK_NOTES" | jq 'length' 2>/dev/null || echo 0)
task_todo=$(echo "$TASK_NOTES" | jq '[.[] | select(.status == "todo")] | length' 2>/dev/null || echo 0)
task_active=$(echo "$TASK_NOTES" | jq '[.[] | select(.status == "active")] | length' 2>/dev/null || echo 0)
task_done=$(echo "$TASK_NOTES" | jq '[.[] | select(.status == "done")] | length' 2>/dev/null || echo 0)
task_on_hold=$(echo "$TASK_NOTES" | jq '[.[] | select(.status == "on-hold")] | length' 2>/dev/null || echo 0)
knowledge_count=$(echo "$KNOWLEDGE_NOTES" | jq 'length' 2>/dev/null || echo 0)
resolution_count=$(echo "$KNOWLEDGE_NOTES" | jq '[.[] | select(.has_resolution_section)] | length' 2>/dev/null || echo 0)
cross_count=$(echo "$CROSS_PROJECT" | jq 'length' 2>/dev/null || echo 0)

MANIFEST=$(jq -n \
  --arg project_resolution "success" \
  --arg hub "success" \
  --arg tasks "$(if [[ "$task_count" -gt 0 ]]; then echo "success: $task_count found ($task_todo todo, $task_active active, $task_done done, $task_on_hold on-hold)"; else echo "none found"; fi)" \
  --arg devlogs "$(if [[ "$devlog_count" -gt 0 ]]; then echo "success: $devlog_count found"; else echo "none found"; fi)" \
  --arg knowledge_notes "$(if [[ "$knowledge_count" -gt 0 ]]; then echo "success: $knowledge_count found, $resolution_count with resolution sections"; else echo "none found"; fi)" \
  --arg cross_project "$(if [[ "$cross_count" -gt 0 ]]; then echo "success: $cross_count found"; else echo "none found"; fi)" \
  --arg workitems "$(if [[ "$workitems_available" == "true" ]]; then echo "success"; else echo "skipped: not configured for this install"; fi)" \
  '{project_resolution: $project_resolution, hub: $hub, tasks: $tasks, devlogs: $devlogs, knowledge_notes: $knowledge_notes, cross_project: $cross_project, workitems: $workitems, linear: "pending (MCP — call from skill)"}')

# ── Output Combined JSON ────────────────────────────────────────────

jq -n \
  --arg today "$TODAY" \
  --argjson project "$PROJECT_JSON" \
  --argjson hub_status "$HUB_STATUS" \
  --argjson tasks "$TASK_NOTES" \
  --argjson devlogs "$DEVLOGS" \
  --argjson knowledge_notes "$KNOWLEDGE_NOTES" \
  --argjson cross_project_devlogs "$CROSS_PROJECT" \
  --argjson workitems "$WORKITEMS" \
  --argjson staleness "$STALENESS" \
  --argjson source_manifest "$MANIFEST" \
  '{
    today: $today,
    project: $project,
    hub_status: $hub_status,
    tasks: $tasks,
    devlogs: $devlogs,
    knowledge_notes: $knowledge_notes,
    cross_project_devlogs: $cross_project_devlogs,
    workitems: $workitems,
    staleness: $staleness,
    source_manifest: $source_manifest
  }'
