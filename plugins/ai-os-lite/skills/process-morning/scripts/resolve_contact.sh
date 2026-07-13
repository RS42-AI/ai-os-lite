#!/usr/bin/env bash
# Resolve a transcript-mentioned name to a canonical vault contact wikilink
# with a 1-line context summary. Tolerates voice-transcript fuzz (Mbali→Bali).
# Usage: resolve_contact.sh "First Name as spoken"
#
# Output JSON:
#   { name, wikilink, found, context }
#   found=true  → canonical match; wikilink is the note basename (no [[]])
#   found=false → no match; red-wikilink; context is null
#
# Bash 3 compatible (macOS ships 3.2). Uses tr for lowercasing, not ${var,,}.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

raw="${1:-}"
if [[ -z "$raw" ]]; then
  echo "Usage: resolve_contact.sh \"Name as spoken\"" >&2
  exit 1
fi

contacts_dir="$VAULT/4. Contacts/People"

if [[ ! -d "$contacts_dir" ]]; then
  jq -n --arg n "$raw" '{name: $n, wikilink: $n, found: false, context: null}'
  exit 0
fi

# Lowercase helper (bash 3 compatible)
lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

match=""

# Pass 1: exact prefix match on filenames (case-insensitive)
raw_lc="$(lc "$raw")"
while IFS= read -r f; do
  base=$(basename "$f" .md)
  base_lc="$(lc "$base")"
  # Match if file basename starts with the spoken name
  if [[ "$base_lc" == "$raw_lc"* ]]; then
    match="$base"
    break
  fi
done < <(find "$contacts_dir" -maxdepth 1 -type f -name "*.md" | sort || true)

# Pass 2: voice-fuzz tolerance — strip leading consonant prefix, retry
# Handles transcription artifacts: Mbali→Bali, Nkosi→Kosi, Mc→c, etc.
if [[ -z "$match" ]]; then
  for prefix in "Mb" "Mc" "Nd" "Nk" "Ng" "M" "N"; do
    # Only strip if the name actually starts with this prefix
    if [[ "$raw" == "$prefix"* ]]; then
      candidate="${raw#$prefix}"
      [[ -z "$candidate" ]] && continue
      candidate_lc="$(lc "$candidate")"
      while IFS= read -r f; do
        base=$(basename "$f" .md)
        base_lc="$(lc "$base")"
        if [[ "$base_lc" == "$candidate_lc"* ]]; then
          match="$base"
          break 2
        fi
      done < <(find "$contacts_dir" -maxdepth 1 -type f -name "*.md" | sort || true)
    fi
  done
fi

# No match → red wikilink (Obsidian will create the page on click)
if [[ -z "$match" ]]; then
  jq -n --arg n "$raw" \
    '{name: $n, wikilink: $n, found: false, context: null}'
  exit 0
fi

# Build 1-line context from frontmatter fields
abs="$contacts_dir/$match.md"
role="$(fm_value "$abs" "role" || true)"
# Contacts use "organization" field (not "org")
org="$(fm_value "$abs" "organization" || true)"

context=""
if [[ -n "$role" || -n "$org" ]]; then
  if [[ -n "$role" && -n "$org" ]]; then
    context="${role} @ ${org}"
  elif [[ -n "$role" ]]; then
    context="$role"
  else
    context="$org"
  fi
fi

# Fallback: first non-frontmatter, non-blank, non-heading line
if [[ -z "$context" ]]; then
  context="$(awk '/^---$/{c++; next} c==2 && NF && !/^#/{print; exit}' "$abs" || true)"
fi

jq -n --arg n "$raw" --arg wl "$match" \
  --arg ctx "$context" \
  '{name: $n, wikilink: $wl, found: true, context: $ctx}'
