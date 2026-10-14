#!/usr/bin/env bash
# setup-vault.sh — Bootstrap or update an Obsidian vault with hub-and-spoke structure
#
# Usage:
#   bash setup-vault.sh [vault_path]
#     Fresh install: creates folder structure, copies starter content (non-clobber),
#     initializes git.
#
#   bash setup-vault.sh --update <existing_vault_path>
#     Update existing vault: installs /update-structure slash command, records
#     kit path in <vault>/.vault-kit-path, runs the same non-clobber copy to add
#     new canonical files, and completes empty containers for project hubs at
#     supported paths. Content moves remain in the previewed update flow.
#     User then runs /update-structure in Claude Code to apply outstanding
#     structure updates.
#
#   vault_path defaults to ~/AIOS
#
# Safe to re-run in either mode — never overwrites user files.

set -euo pipefail

UPDATE_MODE=0
EDITION="personal"
POSITIONAL=()
usage() {
  echo 'Usage: bash setup/setup-vault.sh [--update] [vault_path]'
  echo 'Requires Python 3.10+ and Git. Fresh default: ~/AIOS'
  echo '--update requires the explicit existing vault path; no vault is discovered or moved.'
}
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --update) UPDATE_MODE=1; shift ;;
    --edition)
      [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "ERROR: --edition requires a value; the supported setup is generalized"; exit 1; }
      EDITION="$2"; shift 2 ;;
    --edition=*) EDITION="${1#*=}"; shift ;;
    --*) echo "ERROR: unknown option $1"; usage; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
if [ ${#POSITIONAL[@]} -gt 1 ]; then
  echo "ERROR: provide exactly one vault path"; usage; exit 1
fi
if [ "$UPDATE_MODE" -eq 1 ] && { [ ${#POSITIONAL[@]} -ne 1 ] || [ -z "${POSITIONAL[0]}" ]; }; then
  echo "ERROR: --update requires an explicit existing vault path; no files changed."
  exit 1
fi
# bash 3.2 (macOS): guard empty-array expansion under `set -u`
if [ ${#POSITIONAL[@]} -gt 0 ]; then set -- "${POSITIONAL[@]}"; else set --; fi

VAULT="${1:-$HOME/AIOS}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/vault-files"

# The former personal flag remains a compatibility alias for generalized setup.
# Reject the retired path before creating files or recording license acceptance.
case "$EDITION" in
  personal) ;;
  team)
    echo "ERROR: the legacy team edition has been retired; no workspace files changed."
    echo "Use generalized setup without --edition. For an existing workspace, read setup/docs/switching-to-team-edition.md first."
    exit 1 ;;
  *) echo "ERROR: unknown --edition '$EDITION'; use generalized setup without --edition."; exit 1 ;;
esac

if [ ! -d "$SRC" ]; then
  echo "ERROR: vault-files/ not found at $SRC"
  echo "Make sure you're running this script from the kit's root directory."
  exit 1
fi

for required in python3 git; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "ERROR: $required is required. Install it and rerun; no vault files changed."
    exit 1
  fi
done
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
  echo "ERROR: Python 3.10 or later is required; no vault files changed."
  exit 1
fi
if [ -L "$VAULT" ]; then
  echo "ERROR: the vault path must not be a symlink."
  exit 1
fi
# Reject existing symlinks before copying content into the target tree.
if [ -d "$VAULT" ] && [ -n "$(find "$VAULT" -type l -print -quit)" ]; then
  echo "ERROR: existing symlinks need owner review before setup."
  exit 1
fi

if [ "$UPDATE_MODE" -eq 1 ] && [ ! -d "$VAULT" ]; then
  echo "ERROR: --update requires an existing workspace; $VAULT does not exist. No files changed."
  exit 1
fi

# Only a person may accept the exact license before any workspace writes.
python3 "$SCRIPT_DIR/tools/license_consent.py" "$VAULT" || exit $?

if [ "$UPDATE_MODE" -eq 1 ]; then
  echo "=== Vault Setup — Update Mode ==="
else
  echo "=== Vault Setup ==="
fi
echo "Target vault: $VAULT"
echo ""

if [ "$UPDATE_MODE" -eq 1 ]; then
  echo "[update] Recording kit path to $VAULT/.vault-kit-path"
  echo "$SCRIPT_DIR" > "$VAULT/.vault-kit-path"
  echo "[update] Installing /update-structure slash command"
  mkdir -p "$VAULT/.claude/commands"
  if [ ! -e "$VAULT/.claude/commands/update-structure.md" ]; then
    cp "$SCRIPT_DIR/commands/update-structure.md" "$VAULT/.claude/commands/update-structure.md"
  elif ! cmp -s "$SCRIPT_DIR/commands/update-structure.md" "$VAULT/.claude/commands/update-structure.md"; then
    echo "  Preserved existing update command. Review the current command at:"
    echo "  $SCRIPT_DIR/commands/update-structure.md"
  fi
fi

# --- 1. Create folder structure ---
echo "[1/4] Creating folder structure..."

# Top-level folders that always exist (some are populated by content files,
# others are intentionally empty to be filled by the user over time).
# Generalized structure supports both personal and work projects.
folders=(
  "1. Daily"
  "2. Projects"
  "3. Areas"
  "4. Contacts"
  "4. Contacts/People"
  "4. Contacts/Meetings"
  "5. Resources"
  "5. Resources/Personal"
  "5. Resources/Personal/Journal"
  "5. Resources/Personal/Journal/Morning Entries"
  "5. Resources/Personal/Journal/Evening Entries"
  "6. Main Notes"
  "Personal"
  "Personal/1. Goals"
  "Personal/2. Projects"
  "Personal/Tasks"
  "system-settings"
  "system-settings/Templates"
  "system-settings/Pasted Images"
)

for folder in "${folders[@]}"; do
  if [ "$folder" = "Personal/1. Goals" ] && { [ -d "$VAULT/Personal/Goals" ] || [ -d "$VAULT/3. Areas/Personal/Goals" ]; }; then
    continue # The exact migration must move the old goal root into this path.
  fi
  mkdir -p "$VAULT/$folder"
done
echo "  Ensured ${#folders[@]} folders exist"

# --- 2. Copy starter content over the vault ---
# is_excluded REL: preserve existing workspace instructions and legacy roots.
is_excluded() {
  local rel="$1"
  if [ "$UPDATE_MODE" -eq 1 ]; then
    case "$rel" in
      AGENTS.md|CLAUDE.md)
        return 0
        ;;
      Personal/Personal.md)
        [ -f "$VAULT/3. Areas/Personal/Personal.md" ] && return 0
        ;;
      Personal/2.\ Projects/Vault-Setup/*)
        [ -d "$VAULT/Personal/Vault-Setup" ] && return 0
        ;;
    esac
  fi
  return 1
}

# copy_tree BASE [SUBPATH]: non-clobber copy of files under BASE/[SUBPATH] into
# $VAULT, preserving each file's path relative to BASE. Existing files are kept.
copied_count=0
copy_tree() {
  local base="$1" sub="${2:-}"
  local root="$base"
  [ -n "$sub" ] && root="$base/$sub"
  local src_file rel dest
  while IFS= read -r -d '' src_file; do
    rel="${src_file#"$base"/}"
    if is_excluded "$rel"; then continue; fi
    dest="$VAULT/$rel"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ]; then
      : # skip existing files silently
    else
      cp "$src_file" "$dest"
      copied_count=$((copied_count + 1))
    fi
  done < <(find "$root" -type f -print0)
}

echo "[2/4] Copying starter content..."
copy_tree "$SRC"
echo "  Copied $copied_count new files (existing files left alone)"

# Empty project containers cannot be represented by Git. Discover the project
# hubs that were just installed and materialize the reviewed project shape.
# In update mode this remains additive: moves use the separate preview/apply
# flow documented by /update-structure.
if command -v python3 >/dev/null 2>&1; then
  scaffold_result="$(python3 "$SCRIPT_DIR/tools/project_structure.py" scaffold --vault "$VAULT")"
  scaffold_count="$(printf '%s\n' "$scaffold_result" | sed -n 's/.*"created_count": \([0-9][0-9]*\).*/\1/p')"
  echo "  Ensured complete project containers (${scaffold_count:-0} added)"
else
  echo "ERROR: python3 is required to create complete project containers."
  exit 1
fi

# --- 3. Place CLAUDE.md ---
# The CLAUDE.md from vault-files/ is already copied above. This step just
# notes it for the user since it's the most important file in the vault.

if [ -f "$VAULT/CLAUDE.md" ]; then
  echo "[3/4] CLAUDE.md present at vault root"
else
  echo "[3/4] WARNING: CLAUDE.md missing. Copy from $SRC/CLAUDE.md manually."
fi

# --- 4. Initialize git ---
echo "[4/4] Checking git..."

if [ ! -e "$VAULT/.git" ]; then
  git -C "$VAULT" init -q
fi
if [ ! -e "$VAULT/.gitignore" ]; then
  cat > "$VAULT/.gitignore" << 'GITEOF'
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/plugins/*/data.json
.trash/
.DS_Store
.vault-kit-path
.vault-structure-preview.json
.vault-structure-backups/
.vault-structure-migrations/
GITEOF
fi
if git -C "$VAULT" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "  Git history preserved"
else
  # Do not change the user's global identity or automatically stage existing work.
  echo "  Git initialized; create your first backup commit when ready:"
  echo "    git -C \"$VAULT\" add ."
  echo "    git -C \"$VAULT\" commit -m \"feat: initialize personal vault\""
fi

echo ""
echo "=== Vault files ready ==="
echo ""
if [ "$UPDATE_MODE" -eq 1 ]; then
  echo "Next steps:"
  echo "  1. Open Claude Code or Codex in: $VAULT"
  echo "  2. In Claude Code, run: /update-structure"
  echo "     (applies outstanding structure updates interactively)"
else
  echo "Next steps:"
  echo "  1. Use this folder as your Markdown workspace: $VAULT"
  echo "  2. If needed, run setup/setup.sh for your chosen assistant with this same vault path."
  echo "     Choose --agent=claude, --agent=codex or --agent=both, then start it in the vault."
  echo "     Sign in if needed and verify the Lite skills in a new session."
  echo "  3. Optionally ask the assistant to run setup-context to personalize one useful example."
  echo "  4. Read Personal/2. Projects/Vault-Setup/Vault-Setup.md to begin."
  echo "  Optional: open this folder in Obsidian; use --with-obsidian-plugins only if wanted."
fi
