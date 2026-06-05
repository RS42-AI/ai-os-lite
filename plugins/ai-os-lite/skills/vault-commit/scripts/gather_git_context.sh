#!/bin/bash
# gather_git_context.sh — Deterministic git status collection for vault commits.
# Called by /vault-commit skill as Step 1. Outputs structured JSON to stdout.
# Usage: gather_git_context.sh [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. First argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Uses: git CLI, raw filesystem ops (frontmatter reading)
# Does NOT: call MCP tools, write files, make judgment calls, run git add/commit

set -uo pipefail

# ── Vault Path Resolution ────────────────────────────────────────────
VAULT="${1:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

if [[ ! -d "$VAULT" ]]; then
  echo '{"error": "Vault directory not found: '"$VAULT"'"}' >&2
  exit 1
fi

cd "$VAULT" || exit 1

# Verify this is a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo '{"error": "Not a git repository: '"$VAULT"'"}' >&2
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

# ── Utilities (shared pattern with other gather scripts) ─────────────

get_frontmatter() {
  awk '/^---$/{if(f){exit}f=1;next}f' "$1" 2>/dev/null
}

fm_value() {
  local file="$1" key="$2"
  get_frontmatter "$file" | grep "^${key}:" | head -1 | sed "s/^${key}: *//" | sed 's/^["'"'"']//;s/["'"'"']$//'
}

# JSON string escaping
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ── Infer area from file path ────────────────────────────────────────
# Resolves the area slug from a path's area-folder segment using AGENTS.md's
# canonical "areas" table (folder → slug). Reading the mapping from AGENTS.md —
# rather than a hardcoded list — is what makes this work for any user's areas,
# not just the one this plugin was authored against. Falls back to a mechanical
# slugify when AGENTS.md is absent or the folder isn't listed.
# Returns: an area slug, or "" when no area folder is present in the path.
infer_area_from_path() {
  local path="$1"
  # Personal is the vault-root folder; journals live under it.
  case "$path" in
    Personal/*|*/Personal/*|*Journal/*) echo "personal" ; return ;;
  esac
  # The area-folder segment sits right after "2. Projects/" or "3. Areas/".
  local seg=""
  case "$path" in
    *"2. Projects/"*) seg="${path#*2. Projects/}"; seg="${seg%%/*}" ;;
    *"3. Areas/"*)    seg="${path#*3. Areas/}";    seg="${seg%%/*}" ;;
  esac
  [[ -z "$seg" ]] && { echo "" ; return ; }
  # Look the folder up in AGENTS.md's areas table — rows like:
  #   | `3. Areas/1. Work/` | `work` |
  local slug=""
  if [[ -f "$VAULT/AGENTS.md" ]]; then
    slug=$(awk -F'|' -v seg="$seg" '
      $2 ~ /Areas\// && index($2, seg) {
        s=$3; gsub(/[`[:space:]]/, "", s)
        if (s ~ /^[a-z0-9-]+$/) { print s; exit }
      }' "$VAULT/AGENTS.md")
  fi
  # Fallback: strip a leading "N. " ordinal, lowercase, spaces → hyphens.
  if [[ -z "$slug" ]]; then
    slug=$(echo "$seg" | sed -E 's/^[0-9]+\. *//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  fi
  echo "$slug"
}

# ── Infer project from file path ─────────────────────────────────────
# Looks for 2. Projects/{Area}/{Project}/ and slugifies the project name
infer_project_from_path() {
  local path="$1"
  # Match: 2. Projects/{Area}/{Project}/...
  if [[ "$path" =~ 2\.\ Projects/[^/]+/([^/]+)/ ]]; then
    local name="${BASH_REMATCH[1]}"
    # Slugify: lowercase, spaces/underscores to hyphens
    echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' _' '-'
  else
    echo ""
  fi
}

# ── Infer type from file path ────────────────────────────────────────
infer_type_from_path() {
  local path="$1"
  case "$path" in
    *"Dev Log/"*) echo "devlog" ;;
    *"1. Daily/"*) echo "daily" ;;
    *"Journal/"*) echo "journal" ;;
    *"Meetings/"*) echo "meeting" ;;
    *"Notes/"*) echo "note" ;;
    *"Resources/"*) echo "resource" ;;
    *".obsidian/"*|*".claude/"*|*.json) echo "config" ;;
    *"Excalidraw/"*|*.excalidraw) echo "excalidraw" ;;
    *"Pasted Images/"*|*.png|*.jpg|*.jpeg|*.gif|*.svg) echo "image" ;;
    *"6. Main Notes/"*) echo "note" ;;
    *) echo "" ;;
  esac
}

# ── Infer date from filename ─────────────────────────────────────────
# Many vault files start with YYYY-MM-DD in the filename
infer_date_from_filename() {
  local path="$1"
  local basename
  basename=$(basename "$path")
  if [[ "$basename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# ── Collect Changed Files ────────────────────────────────────────────

# git status --short --porcelain for machine-readable output
# Status codes: M=modified, A=added, ??=untracked, D=deleted, R=renamed
# --untracked-files=all recurses into untracked directories so each file is
# listed individually instead of being collapsed to a single directory entry.
# Note: avoid mapfile (bash 4+), use while read for macOS compatibility
STATUS_LINES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && STATUS_LINES+=("$line")
done < <(git status --short --porcelain --untracked-files=all 2>/dev/null)

TOTAL_FILES=${#STATUS_LINES[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
  cat <<EOF
{
  "today": "$TODAY",
  "vault": "$VAULT",
  "total_files": 0,
  "files": [],
  "recent_commits": [],
  "source_manifest": {
    "git_status": "success: 0 changed files",
    "frontmatter_reads": "skipped: no files to read"
  }
}
EOF
  exit 0
fi

# ── Read Recent Commits (for style matching) ─────────────────────────

RECENT_COMMITS=""
while IFS= read -r line; do
  escaped=$(json_escape "$line")
  if [[ -n "$RECENT_COMMITS" ]]; then
    RECENT_COMMITS="${RECENT_COMMITS},"
  fi
  RECENT_COMMITS="${RECENT_COMMITS}\"${escaped}\""
done < <(git log --oneline -10 2>/dev/null)

# ── Process Each File ────────────────────────────────────────────────

FILES_JSON=""
FM_SUCCESS=0
FM_SKIPPED=0
FM_FAILED=0

for line in "${STATUS_LINES[@]}"; do
  # Parse git status line: XY filename (or XY "filename" for paths with spaces)
  git_status="${line:0:2}"
  git_status=$(echo "$git_status" | xargs)  # trim whitespace
  filepath="${line:3}"
  # Remove surrounding quotes if present
  filepath="${filepath#\"}"
  filepath="${filepath%\"}"

  # Determine if file exists (deleted files won't)
  file_exists="false"
  if [[ -f "$VAULT/$filepath" ]]; then
    file_exists="true"
  fi

  # Read frontmatter for .md files that exist
  fm_date=""
  fm_type=""
  fm_area=""
  fm_project=""

  if [[ "$file_exists" == "true" && "$filepath" == *.md ]]; then
    fm_date=$(fm_value "$VAULT/$filepath" "date")
    fm_type=$(fm_value "$VAULT/$filepath" "type")
    fm_area=$(fm_value "$VAULT/$filepath" "area")
    fm_project=$(fm_value "$VAULT/$filepath" "project")
    if [[ -n "$fm_date" || -n "$fm_type" ]]; then
      FM_SUCCESS=$((FM_SUCCESS + 1))
    else
      FM_FAILED=$((FM_FAILED + 1))
    fi
  else
    FM_SKIPPED=$((FM_SKIPPED + 1))
  fi

  # Infer from path where frontmatter is missing
  inferred_area=$(infer_area_from_path "$filepath")
  inferred_project=$(infer_project_from_path "$filepath")
  inferred_type=$(infer_type_from_path "$filepath")
  inferred_date=$(infer_date_from_filename "$filepath")

  # Resolve: frontmatter wins, then inference, then empty
  resolved_date="${fm_date:-$inferred_date}"
  resolved_type="${fm_type:-$inferred_type}"
  resolved_area="${fm_area:-$inferred_area}"
  resolved_project="${fm_project:-$inferred_project}"

  # Build file JSON
  escaped_path=$(json_escape "$filepath")
  escaped_status=$(json_escape "$git_status")

  file_json="{"
  file_json+="\"path\":\"$escaped_path\","
  file_json+="\"git_status\":\"$escaped_status\","
  file_json+="\"exists\":$file_exists,"
  file_json+="\"date\":\"$resolved_date\","
  file_json+="\"type\":\"$resolved_type\","
  file_json+="\"area\":\"$resolved_area\","
  file_json+="\"project\":\"$resolved_project\","
  file_json+="\"fm_date\":\"${fm_date}\","
  file_json+="\"fm_type\":\"${fm_type}\","
  file_json+="\"fm_area\":\"${fm_area}\","
  file_json+="\"fm_project\":\"${fm_project}\","
  file_json+="\"inferred_date\":\"${inferred_date}\","
  file_json+="\"inferred_type\":\"${inferred_type}\","
  file_json+="\"inferred_area\":\"${inferred_area}\","
  file_json+="\"inferred_project\":\"${inferred_project}\""
  file_json+="}"

  if [[ -n "$FILES_JSON" ]]; then
    FILES_JSON="${FILES_JSON},"
  fi
  FILES_JSON="${FILES_JSON}${file_json}"
done

# ── Output ───────────────────────────────────────────────────────────

cat <<EOF
{
  "today": "$TODAY",
  "vault": "$VAULT",
  "total_files": $TOTAL_FILES,
  "files": [$FILES_JSON],
  "recent_commits": [$RECENT_COMMITS],
  "source_manifest": {
    "git_status": "success: $TOTAL_FILES changed files",
    "frontmatter_reads": "success: $FM_SUCCESS read, $FM_SKIPPED skipped (non-md/deleted), $FM_FAILED failed (no frontmatter)"
  }
}
EOF
