#!/bin/bash
# commit_daily_scaffold.sh — Commits the day's populated scaffold (daily hub +
# morning journal entry) in the vault git repo so the morning-entry edits that
# follow are visible as a distinct modification in git history.
# Called by /start-day as Step 5b, after the journal page is fully rendered.
# Usage: commit_daily_scaffold.sh YYYY-MM-DD [VAULT_PATH]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# Commits ONLY the two scaffold paths (pathspec-limited add + commit) — other
# dirty vault files, including private-flag stamps written by the gather
# script, are left for /vault-commit's nightly pass.
#
# Idempotency: if neither scaffold path has uncommitted changes, the script
# skips with {committed: false, reason: "no_changes"} — re-running /start-day
# never produces a duplicate commit. A re-run that changed the rendered
# content commits again (a legitimate new snapshot, same message).
#
# Failure semantics: always exits 0 (warn, don't block start-day). A failed
# commit surfaces as {committed: false, error: "..."} for the execution
# report. Usage errors (missing date arg) are the only non-zero exit.
#
# Outputs JSON:
#   {"committed": true|false, "sha": ...|null, "message": ...|null,
#    "files": [...], "reason": ...|null, "error": ...|null}

set -uo pipefail

TARGET_DATE="${1:?Usage: commit_daily_scaffold.sh YYYY-MM-DD [VAULT_PATH]}"
VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"

JOURNAL_REL="5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md"
HUB_REL="1. Daily/${TARGET_DATE}.md"
COMMIT_MSG="chore: start-day scaffold for ${TARGET_DATE}"

# emit committed sha message files_json reason error — single JSON exit point
emit() {
  jq -n \
    --argjson committed "$1" \
    --arg sha "$2" \
    --arg message "$3" \
    --argjson files "$4" \
    --arg reason "$5" \
    --arg error "$6" \
    '{committed: $committed,
      sha: (if $sha == "" then null else $sha end),
      message: (if $message == "" then null else $message end),
      files: $files,
      reason: (if $reason == "" then null else $reason end),
      error: (if $error == "" then null else $error end)}'
}

if [[ ! -d "$VAULT" ]]; then
  emit false "" "" "[]" "" "Vault directory not found: $VAULT"
  exit 0
fi

if ! git -C "$VAULT" rev-parse --is-inside-work-tree &>/dev/null; then
  emit false "" "" "[]" "" "Not a git repository: $VAULT"
  exit 0
fi

# Collect the scaffold paths that exist on disk
PATHS=()
[[ -f "$VAULT/$JOURNAL_REL" ]] && PATHS+=("$JOURNAL_REL")
[[ -f "$VAULT/$HUB_REL" ]] && PATHS+=("$HUB_REL")

if [[ ${#PATHS[@]} -eq 0 ]]; then
  emit false "" "" "[]" "" "Neither scaffold file exists: $JOURNAL_REL, $HUB_REL"
  exit 0
fi

FILES_JSON=$(printf '%s\n' "${PATHS[@]}" | jq -R . | jq -s .)

# Idempotency gate: nothing changed (or untracked) at the scaffold paths → skip
if [[ -z "$(git -C "$VAULT" status --porcelain -- "${PATHS[@]}")" ]]; then
  emit false "" "" "$FILES_JSON" "no_changes" ""
  exit 0
fi

# Stage and commit ONLY the scaffold paths. The pathspec on commit guarantees
# unrelated changes staged by other tools are not swept into this commit.
if ! ADD_OUT=$(git -C "$VAULT" add -- "${PATHS[@]}" 2>&1); then
  emit false "" "" "$FILES_JSON" "" "git add failed: $(echo "$ADD_OUT" | head -1)"
  exit 0
fi

if ! COMMIT_OUT=$(git -C "$VAULT" commit -m "$COMMIT_MSG" -- "${PATHS[@]}" 2>&1); then
  emit false "" "" "$FILES_JSON" "" "git commit failed: $(echo "$COMMIT_OUT" | head -1)"
  exit 0
fi

SHA=$(git -C "$VAULT" rev-parse --short HEAD 2>/dev/null)
emit true "$SHA" "$COMMIT_MSG" "$FILES_JSON" "" ""
