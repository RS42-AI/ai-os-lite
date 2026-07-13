#!/usr/bin/env bash
# Shared helpers for /process-morning scripts.
# Source from any sibling script: `source "$(dirname "$0")/lib.sh"`

VAULT="${VAULT:-$HOME/Claude/ObsidianVault}"

# get_frontmatter <file>
# Prints everything between the first and second --- delimiters.
# Copied from start-day/scripts/gather_morning_context.sh — keep in sync.
get_frontmatter() {
  awk '/^---$/{if(f){exit}f=1;next}f' "$1" 2>/dev/null
}

# fm_value <file> <key>
# Reads a top-level frontmatter scalar key. Returns empty string if missing.
# Copied from start-day/scripts/gather_morning_context.sh — keep in sync.
fm_value() {
  local file="$1" key="$2"
  get_frontmatter "$file" | grep "^${key}:" | head -1 | sed "s/^${key}: *//" | sed 's/^["'"'"']//;s/["'"'"']$//'
}

# fm_list <file> <key>
# Reads a top-level frontmatter list key (YAML block sequence).
# Returns one item per line, unquoted. Returns empty if key absent.
# Copied from start-day/scripts/gather_morning_context.sh — keep in sync.
fm_list() {
  local file="$1" key="$2"
  get_frontmatter "$file" | \
    awk "/^${key}:/{p=1;next}/^[^ ]/{p=0}p" | \
    sed 's/^ *- *//' | sed 's/^["'"'"']//;s/["'"'"']$//'
}

# obs_path <vault-relative-path>
# Resolves a vault-relative path (e.g. "1. Daily/2026-05-16.md") to absolute.
obs_path() {
  echo "$VAULT/$1"
}

# yesterday_ymd <today YYYY-MM-DD>
# Returns yesterday in YYYY-MM-DD, BSD and GNU compatible.
# NOTE: BSD date requires -v before -f; plan stub had reversed order — fixed.
yesterday_ymd() {
  local today="$1"
  if date -j -v-1d -f "%Y-%m-%d" "$today" "+%Y-%m-%d" 2>/dev/null; then
    return
  fi
  date -d "$today -1 day" "+%Y-%m-%d"
}
