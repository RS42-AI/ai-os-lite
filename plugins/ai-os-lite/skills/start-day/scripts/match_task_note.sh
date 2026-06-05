#!/bin/bash
# match_task_note.sh — Find task notes whose content matches search terms.
# Used by /process-journal to cross-reference priorities with existing task notes.
# Usage: match_task_note.sh "search term" [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Search is a literal fixed string (grep -F). Case-insensitive.
# Output: one matching vault-relative path per line. Empty output = no matches.
# Exit: 0 always (no match is not an error; missing vault is not an error).

set -u

SEARCH="${1:?Usage: match_task_note.sh \"search term\" [VAULT_PATH]}"
VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

if [[ ! -d "$VAULT" ]]; then
  echo "Vault directory not found: $VAULT" >&2
  exit 0
fi

# -exec ... + handles zero-match cleanly (no grep invocation),
# is NUL-safe by construction, and avoids xargs stdin-hang edge case.
while IFS= read -r file; do
  printf '%s\n' "${file#$VAULT/}"
done < <(
  find "$VAULT" -path "*/Tasks/*.md" -not -path "*/Templates/*" \
    -exec grep -liF "$SEARCH" {} + 2>/dev/null
)

exit 0
