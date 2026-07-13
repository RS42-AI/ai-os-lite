#!/bin/bash
# commit_journal_processing.sh — Commits the day's processing output (morning
# journal entry + AI Summary + bottom marker, daily hub + priorities block,
# and any task notes created in Step 7) in the vault git repo so the
# processing run is a distinct, legible git step — separate from the /start-day
# scaffold snapshot and the nightly /vault-commit sweep.
# Called by /process-morning as Step 8j, after all writes complete (Steps 6, 7,
# 8a-8i).
# Usage: commit_journal_processing.sh YYYY-MM-DD [VAULT_PATH] [TASK_NOTE_PATH...]
#
# VAULT_PATH resolution (first match wins):
#   1. Second argument to script
#   2. PERSONAL_OS_VAULT environment variable
#   3. Default: $HOME/Claude/ObsidianVault
#
# TASK_NOTE_PATH: zero or more vault-relative paths to task notes created or
#   modified in Step 7. If none are passed, the script commits only the two
#   core processing paths (journal entry + daily hub).
#
# Commits ONLY the listed paths (pathspec-limited add + commit) — other dirty
# vault files (private stamps, unrelated edits) are left for /vault-commit's
# nightly pass.
#
# Idempotency: if none of the listed paths have uncommitted changes, the script
# skips with {committed: false, reason: "no_changes"} — re-running /process-
# journal never produces a duplicate commit. A re-run that refreshed the AI
# Summary, priorities, or bottom marker commits again (a legitimate new snapshot,
# same message).
#
# Failure semantics: always exits 0 (warn, don't block process-morning). A
# failed commit surfaces as {committed: false, error: "..."} for the execution
# report. Usage errors (missing date arg) are the only non-zero exit.
#
# Outputs JSON:
#   {"committed": true|false, "sha": ...|null, "message": ...|null,
#    "files": [...], "reason": ...|null, "error": ...|null}

set -uo pipefail

TARGET_DATE="${1:?Usage: commit_journal_processing.sh YYYY-MM-DD [VAULT_PATH] [TASK_NOTE_PATH...]}"
VAULT="${2:-${PERSONAL_OS_VAULT:-$HOME/Claude/ObsidianVault}}"
TASK_PATHS=()
if [[ $# -gt 2 ]]; then
  TASK_PATHS=("${@:3}")
fi

JOURNAL_REL="5. Resources/Personal/Journal/Morning Entries/${TARGET_DATE}.md"
HUB_REL="1. Daily/${TARGET_DATE}.md"
COMMIT_MSG="docs: process-morning for ${TARGET_DATE}"

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

# Collect the core paths that exist on disk
PATHS=()
[[ -f "$VAULT/$JOURNAL_REL" ]] && PATHS+=("$JOURNAL_REL")
[[ -f "$VAULT/$HUB_REL" ]] && PATHS+=("$HUB_REL")

# Append any task note paths that exist on disk
if [[ ${#TASK_PATHS[@]} -gt 0 ]]; then
  for p in "${TASK_PATHS[@]}"; do
    [[ -f "$VAULT/$p" ]] && PATHS+=("$p")
  done
fi

if [[ ${#PATHS[@]} -eq 0 ]]; then
  emit false "" "" "[]" "" "Neither core file exists: $JOURNAL_REL, $HUB_REL"
  exit 0
fi

FILES_JSON=$(printf '%s\n' "${PATHS[@]}" | jq -R . | jq -s .)

# Idempotency gate: nothing changed (or untracked) at the listed paths → skip
if [[ -z "$(git -C "$VAULT" status --porcelain -- "${PATHS[@]}")" ]]; then
  emit false "" "" "$FILES_JSON" "no_changes" ""
  exit 0
fi

# Stage and commit ONLY the listed paths. The pathspec on commit guarantees
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
