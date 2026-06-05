#!/bin/bash
# audit_journal_links.sh — Verify every wikilink in the rendered morning
# journal entry resolves to exactly one vault file.
#
# Usage: audit_journal_links.sh YYYY-MM-DD [VAULT_PATH]
#
# Exits 0 with JSON report when every link resolves uniquely.
# Exits 1 with JSON report listing broken/ambiguous links when any link fails.
#
# Output shape:
# {
#   "ok": true|false,
#   "checked": N,
#   "ok_count": N,
#   "broken": [{"link": "[[X]]", "reason": "no match"}, ...],
#   "ambiguous": [{"link": "[[Y]]", "matches": ["path1.md","path2.md"]}, ...]
# }

set -uo pipefail

TARGET_DATE="${1:?Usage: audit_journal_links.sh YYYY-MM-DD [VAULT_PATH]}"
VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

JOURNAL="$VAULT/5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md"

if [[ ! -f "$JOURNAL" ]]; then
  jq -n --arg path "$JOURNAL" \
    '{ok: false, checked: 0, ok_count: 0, broken: [], ambiguous: [], error: ("journal not found: " + $path)}'
  exit 1
fi

# Scope the audit to the Recent Accomplishments block — that's the only region
# /start-day writes. Stops at the next H2 boundary (the `---` divider + ## Tasks Overview).
SECTION=$(awk '
  /^## Recent Accomplishments/ {p=1; next}
  /^## / && p {exit}
  p {print}
' "$JOURNAL")

if [[ -z "$SECTION" ]]; then
  jq -n '{ok: true, checked: 0, ok_count: 0, broken: [], ambiguous: [], note: "no Recent Accomplishments content to audit"}'
  exit 0
fi

# Extract wikilinks. Match [[...]] where ... is non-greedy and contains no nested ].
# Strip the optional |alias suffix to get the link target.
LINKS=$(echo "$SECTION" | grep -oE '\[\[[^]]+\]\]' | sed -E 's/^\[\[//; s/\]\]$//; s/\|.*$//')

CHECKED=0
OK_COUNT=0
BROKEN_JSON="[]"
AMBIGUOUS_JSON="[]"

# Sentinel strings that legitimately appear inside blockquotes with `**Key**:` syntax
# and must NOT be parsed as wikilinks. These don't have [[ ]] so they shouldn't match,
# but we defensively filter just in case future formatting adds them.
SKIP_PATTERNS=("NO EVENING ENTRY")

# Pre-build a list of all .md files in the vault, relative to vault root, for
# fast lookup. Excludes git internals, Obsidian state, trash, and the vault-setup
# kit scaffold (which mirrors real vault files for distribution — not live).
ALL_FILES=$(find "$VAULT" -type f -name "*.md" \
  -not -path "*/.git/*" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.trash/*" \
  -not -path "*/setup-kit/vault-files/*" \
  -not -path "*/system-settings/Templates/*" \
  2>/dev/null | sed "s|^$VAULT/||")

is_skip() {
  local link="$1"
  for s in "${SKIP_PATTERNS[@]}"; do
    [[ "$link" == "$s" ]] && return 0
  done
  return 1
}

while IFS= read -r link; do
  [[ -z "$link" ]] && continue
  is_skip "$link" && continue
  CHECKED=$((CHECKED + 1))

  # Two resolution modes:
  #   (a) Full path link: contains '/' → match exact path with .md appended.
  #   (b) Basename link: no '/' → match any file whose basename (sans .md) equals link.
  if [[ "$link" == *"/"* ]]; then
    if printf '%s\n' "$ALL_FILES" | grep -Fxq "${link}.md"; then
      matches="${link}.md"
    else
      matches=""
    fi
  else
    matches=$(printf '%s\n' "$ALL_FILES" | awk -F/ -v target="${link}.md" '$NF == target {print}')
  fi

  if [[ -z "$matches" ]]; then
    count=0
  else
    count=$(printf '%s\n' "$matches" | grep -c .)
  fi

  if [[ "$count" -eq 0 ]]; then
    BROKEN_JSON=$(echo "$BROKEN_JSON" | jq --arg l "[[${link}]]" \
      '. + [{link: $l, reason: "no match"}]')
  elif [[ "$count" -eq 1 ]]; then
    OK_COUNT=$((OK_COUNT + 1))
  else
    matches_json=$(printf '%s\n' "$matches" | jq -R . | jq -s .)
    AMBIGUOUS_JSON=$(echo "$AMBIGUOUS_JSON" | jq --arg l "[[${link}]]" --argjson m "$matches_json" \
      '. + [{link: $l, matches: $m}]')
  fi
done <<< "$LINKS"

BROKEN_COUNT=$(echo "$BROKEN_JSON" | jq 'length')
AMBIG_COUNT=$(echo "$AMBIGUOUS_JSON" | jq 'length')

if [[ "$BROKEN_COUNT" -eq 0 && "$AMBIG_COUNT" -eq 0 ]]; then
  jq -n --argjson c "$CHECKED" --argjson ok "$OK_COUNT" \
    '{ok: true, checked: $c, ok_count: $ok, broken: [], ambiguous: []}'
  exit 0
fi

jq -n \
  --argjson c "$CHECKED" \
  --argjson ok "$OK_COUNT" \
  --argjson b "$BROKEN_JSON" \
  --argjson a "$AMBIGUOUS_JSON" \
  '{ok: false, checked: $c, ok_count: $ok, broken: $b, ambiguous: $a}'
exit 1
