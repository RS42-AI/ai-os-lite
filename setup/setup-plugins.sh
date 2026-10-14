#!/usr/bin/env bash
# setup-plugins.sh — Install and configure Obsidian community plugins
#
# What it does:
#   1. Downloads missing essential plugins from GitHub
#   2. Writes plugin configurations (data.json) for each
#   3. Updates community-plugins.json to enable them
#
# Prerequisites:
#   - Obsidian vault exists at the target path
#   - curl available (ships with macOS; pre-installed on Ubuntu/WSL)
#
# Usage: bash setup-plugins.sh [vault_path]
#   vault_path defaults to ~/AIOS
#
# IMPORTANT: After running, restart Obsidian for changes to take effect.

set -euo pipefail

VAULT="${1:-$HOME/AIOS}"
PLUGINS_DIR="$VAULT/.obsidian/plugins"

valid_manifest() {
  python3 - "$1" "$2" <<'PYMAN'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    assert data.get("id") == sys.argv[2] and data.get("version")
except (OSError, ValueError, AssertionError, AttributeError):
    sys.exit(1)
PYMAN
}

# --- Helper: download plugin from GitHub ---
download_plugin() {
  local plugin_id="$1"
  local repo="$2"
  local plugin_dir="$PLUGINS_DIR/$plugin_id"

  if [ ! -e "$plugin_dir/.ai-os-install-incomplete" ] && [ -s "$plugin_dir/main.js" ] && valid_manifest "$plugin_dir/manifest.json" "$plugin_id" && ! head -c 200 "$plugin_dir/main.js" | grep -qiE '<!doctype html|<html'; then
    echo "  SKIP (already installed): $plugin_id — existing notices not audited or replaced"
    successful_plugins="${successful_plugins:-} $plugin_id"
    return 0
  fi
  echo "  Downloading $plugin_id from $repo..."
  local staging
  if ! staging="$(mktemp -d "$PLUGINS_DIR/.download.XXXXXX")"; then
    echo "  INCOMPLETE: cannot create $plugin_id staging directory."
    return 1
  fi
  if ! python3 "$SCRIPT_DIR/tools/plugin_release.py" "$repo" "$plugin_id" "$staging"; then
    echo "  INCOMPLETE: $plugin_id release or notices unavailable; existing files preserved."
    rm -rf "$staging"
    return 1
  fi
  if ! mkdir -p "$plugin_dir"; then
    echo "  INCOMPLETE: cannot create $plugin_id directory."
    rm -rf "$staging"
    return 1
  fi
  if ! : > "$plugin_dir/.ai-os-install-incomplete"; then
    echo "  INCOMPLETE: cannot record $plugin_id installation state."
    rm -rf "$staging"
    return 1
  fi
  # Required notices are present before any newly downloaded runtime files.
  # This function runs in an OR-list, so every copy needs an explicit guard.
  if ! cp -R "$staging/upstream-notices" "$plugin_dir/"; then
    echo "  INCOMPLETE: cannot preserve $plugin_id notices; runtime files not installed."
    rm -rf "$staging"
    return 1
  fi
  if ! cp "$staging/main.js" "$staging/manifest.json" "$plugin_dir/" ||
     { [ -f "$staging/styles.css" ] && ! cp "$staging/styles.css" "$plugin_dir/"; }; then
    echo "  INCOMPLETE: $plugin_id runtime copy failed; not newly enabled, existing settings retained."
    rm -rf "$staging"
    return 1
  fi
  if ! rm "$plugin_dir/.ai-os-install-incomplete"; then
    echo "  INCOMPLETE: cannot finish $plugin_id installation state; retry before enabling."
    rm -rf "$staging"
    return 1
  fi
  rm -rf "$staging"
  successful_plugins="${successful_plugins:-} $plugin_id"
  echo "  INSTALLED: $plugin_id"

}

# --- Helper: write terminal plugin config (macOS + Windows/WSL profiles) ---
write_terminal_config() {
  local dir="$1"   # .../.obsidian/plugins/terminal
  mkdir -p "$dir"
  [ ! -e "$dir/data.json" ] || return 0
  cat > "$dir/data.json" << 'EOF'
{
  "addToCommand": true,
  "addToContextMenu": true,
  "createInstanceNearExistingOnes": true,
  "errorNoticeTimeout": 0,
  "exposeInternalModules": true,
  "focusOnNewInstance": true,
  "hideStatusBar": "focused",
  "interceptLogging": true,
  "language": "",
  "macOSOptionKeyPassthrough": true,
  "newInstanceBehavior": "newHorizontalSplit",
  "noticeTimeout": 5,
  "openChangelogOnUpdate": true,
  "pinNewInstance": true,
  "preferredRenderer": "webgl",
  "profiles": {
    "darwinExternalDefault": {
      "args": ["\"$PWD\""],
      "executable": "/System/Applications/Utilities/Terminal.app/Contents/macOS/Terminal",
      "followTheme": true,
      "name": "",
      "platforms": { "darwin": true },
      "restoreHistory": false,
      "rightClickAction": "copyPaste",
      "successExitCodes": ["0", "SIGINT", "SIGTERM"],
      "terminalOptions": { "documentOverride": null },
      "type": "external"
    },
    "darwinIntegratedDefault": {
      "args": ["--login"],
      "executable": "/bin/zsh",
      "followTheme": true,
      "name": "",
      "platforms": { "darwin": true },
      "pythonExecutable": "python3",
      "restoreHistory": false,
      "rightClickAction": "copyPaste",
      "successExitCodes": ["0", "SIGINT", "SIGTERM"],
      "terminalOptions": { "documentOverride": null },
      "type": "integrated",
      "useWin32Conhost": true
    },
    "win32IntegratedDefault": {
      "args": [],
      "executable": "wsl.exe",
      "followTheme": true,
      "name": "",
      "platforms": { "win32": true },
      "restoreHistory": false,
      "rightClickAction": "copyPaste",
      "successExitCodes": ["0", "SIGINT", "SIGTERM"],
      "terminalOptions": { "documentOverride": null },
      "type": "integrated",
      "useWin32Conhost": true
    },
    "developerConsole": {
      "followTheme": true,
      "name": "",
      "restoreHistory": false,
      "rightClickAction": "copyPaste",
      "successExitCodes": ["0", "SIGINT", "SIGTERM"],
      "terminalOptions": { "documentOverride": null },
      "type": "developerConsole"
    }
  },
  "defaultProfile": "darwinIntegratedDefault",
  "terminalOptions": { "documentOverride": null }
}
EOF
}

# Allow tests to source just the function definitions (skip the procedural body).
if [ "${KIT_SOURCE_ONLY:-0}" = "1" ]; then
  # shellcheck disable=SC2317 # Fallback is reachable only when the file is executed, not sourced.
  return 0 2>/dev/null || exit 0
fi

# Review the exact license before downloads or user-level configuration writes.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/tools/license_consent.py" "$VAULT" || exit $?

echo "=== Obsidian Plugin Setup ==="
echo "Vault: $VAULT"
echo ""

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required"; exit 1; }
[ -d "$VAULT" ] || { echo "ERROR: create the vault first"; exit 1; }
[ -z "$(find "$VAULT" -type l -print -quit)" ] || { echo "ERROR: symlinks need owner review"; exit 1; }
python3 - "$VAULT/.obsidian/community-plugins.json" <<'PYLIST'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.exists():
    data = json.loads(p.read_text())
    if not isinstance(data, list) or not all(isinstance(x, str) for x in data):
        sys.exit("ERROR: preserve and repair invalid community-plugins.json before setup")
PYLIST
mkdir -p "$PLUGINS_DIR"
failed=0
successful_plugins=""

# --- 1. Install missing plugins ---
echo "[1/3] Installing plugins..."

# Essential plugins to download if missing (bash 3.2 compatible — no associative arrays)
download_plugin "terminal" "polyipseity/obsidian-terminal" || failed=$((failed + 1))
download_plugin "obsidian-linter" "platers/obsidian-linter" || failed=$((failed + 1))
download_plugin "templater-obsidian" "SilentVoid13/Templater" || failed=$((failed + 1))
download_plugin "dataview" "blacksmithgu/obsidian-dataview" || failed=$((failed + 1))
download_plugin "obsidian-git" "Vinzent03/obsidian-git" || failed=$((failed + 1))
download_plugin "obsidian-local-rest-api" "coddingtonbear/obsidian-local-rest-api" || failed=$((failed + 1))
download_plugin "mcp-tools" "jacksteamdev/obsidian-mcp-tools" || failed=$((failed + 1))
download_plugin "editing-toolbar" "PKM-er/obsidian-editing-toolbar" || failed=$((failed + 1))
download_plugin "obsidian-excalidraw-plugin" "zsviczian/obsidian-excalidraw-plugin" || failed=$((failed + 1))
download_plugin "smart-connections" "brianpetro/obsidian-smart-connections" || failed=$((failed + 1))

echo ""

# --- 2. Write plugin configurations ---
echo "[2/3] Writing plugin configurations..."

# --- Terminal ---
echo "  Configuring: Terminal"
# Terminal: the win32 profile launches the default WSL distro via wsl.exe.
# If the user's default distro is not Ubuntu, add "-d Ubuntu" to that profile's args.
[ ! -f "$PLUGINS_DIR/terminal/main.js" ] || write_terminal_config "$PLUGINS_DIR/terminal"

# --- Linter ---
echo "  Configuring: Linter"
if [ -f "$PLUGINS_DIR/obsidian-linter/main.js" ] && [ ! -e "$PLUGINS_DIR/obsidian-linter/data.json" ]; then
cat > "$PLUGINS_DIR/obsidian-linter/data.json" << 'EOF'
{
  "ruleConfigs": {
    "add-blank-line-after-yaml": { "enabled": true },
    "dedupe-yaml-array-values": {
      "enabled": true,
      "dedupe-alias-key": true,
      "dedupe-tag-key": true,
      "dedupe-array-keys": true,
      "ignore-keys": ""
    },
    "escape-yaml-special-characters": { "enabled": false },
    "force-yaml-escape": { "enabled": false },
    "format-tags-in-yaml": { "enabled": true },
    "format-yaml-array": {
      "enabled": true,
      "alias-key": true,
      "tag-key": true,
      "default-array-style": "multi-line",
      "default-array-keys": true,
      "force-single-line-array-style": "",
      "force-multi-line-array-style": ""
    },
    "insert-yaml-attributes": {
      "enabled": false,
      "text-to-insert": ""
    },
    "move-tags-to-yaml": { "enabled": false },
    "remove-yaml-keys": { "enabled": false },
    "sort-yaml-array-values": {
      "enabled": true,
      "sort-alias-key": true,
      "sort-tag-key": true,
      "sort-array-keys": true,
      "ignore-keys": "",
      "sort-order": "Ascending Alphabetical"
    },
    "yaml-key-sort": {
      "enabled": true,
      "yaml-key-priority-sort-order": "date\ndate created\ndate modified\nstatus\ntype\nproject\nsession_topic\ntags",
      "priority-keys-at-start-of-yaml": true,
      "yaml-sort-order-for-other-keys": "Ascending Alphabetical"
    },
    "yaml-timestamp": {
      "enabled": true,
      "date-created": true,
      "date-created-key": "date created",
      "date-created-source-of-truth": "file system",
      "date-modified": true,
      "date-modified-key": "date modified",
      "date-modified-source-of-truth": "file system",
      "format": "YYYY-MM-DD",
      "convert-to-utc": false,
      "update-on-file-contents-updated": "never"
    },
    "yaml-title": { "enabled": false },
    "yaml-title-alias": { "enabled": false },
    "capitalize-headings": { "enabled": false },
    "file-name-heading": { "enabled": false },
    "header-increment": { "enabled": false },
    "headings-start-line": { "enabled": false },
    "remove-trailing-punctuation-in-heading": { "enabled": false },
    "footnote-after-punctuation": { "enabled": false },
    "move-footnotes-to-the-bottom": { "enabled": false },
    "re-index-footnotes": { "enabled": false },
    "auto-correct-common-misspellings": { "enabled": false },
    "blockquote-style": { "enabled": false },
    "convert-bullet-list-markers": { "enabled": false },
    "default-language-for-code-fences": { "enabled": false },
    "emphasis-style": { "enabled": false },
    "no-bare-urls": { "enabled": false },
    "ordered-list-style": { "enabled": false },
    "proper-ellipsis": { "enabled": false },
    "quote-style": { "enabled": false },
    "remove-consecutive-list-markers": { "enabled": false },
    "remove-empty-list-markers": { "enabled": false },
    "remove-hyphenated-line-breaks": { "enabled": false },
    "remove-multiple-spaces": { "enabled": false },
    "strong-style": { "enabled": false },
    "two-spaces-between-lines-with-content": { "enabled": false },
    "unordered-list-style": { "enabled": false },
    "compact-yaml": { "enabled": false },
    "consecutive-blank-lines": { "enabled": false },
    "convert-spaces-to-tabs": { "enabled": false },
    "empty-line-around-blockquotes": { "enabled": false },
    "empty-line-around-code-fences": { "enabled": false },
    "empty-line-around-horizontal-rules": { "enabled": false },
    "empty-line-around-math-blocks": { "enabled": false },
    "empty-line-around-tables": { "enabled": false },
    "heading-blank-lines": { "enabled": false },
    "line-break-at-document-end": { "enabled": false },
    "move-math-block-indicators-to-their-own-line": { "enabled": false },
    "paragraph-blank-lines": { "enabled": false },
    "remove-empty-lines-between-list-markers-and-checklists": { "enabled": false },
    "remove-link-spacing": { "enabled": false },
    "remove-space-around-characters": { "enabled": false },
    "remove-space-before-or-after-characters": { "enabled": false },
    "space-after-list-markers": { "enabled": false },
    "space-between-chinese-japanese-or-korean-and-english-or-numbers": { "enabled": false },
    "trailing-spaces": { "enabled": false },
    "add-blockquote-indentation-on-paste": { "enabled": false },
    "prevent-double-checklist-indicator-on-paste": { "enabled": false },
    "prevent-double-list-item-indicator-on-paste": { "enabled": false },
    "proper-ellipsis-on-paste": { "enabled": false },
    "remove-hyphens-on-paste": { "enabled": false },
    "remove-leading-or-trailing-whitespace-on-paste": { "enabled": false },
    "remove-leftover-footnotes-from-quote-on-paste": { "enabled": false },
    "remove-multiple-blank-lines-on-paste": { "enabled": false }
  },
  "lintOnSave": true,
  "recordLintOnSaveLogs": false,
  "displayChanged": true,
  "suppressMessageWhenNoChange": false,
  "lintOnFileChange": false,
  "displayLintOnFileChangeNotice": false,
  "settingsConvertedToConfigKeyValues": true,
  "foldersToIgnore": [
    "Excalidraw",
    "system-settings/Pasted Images",
    "system-settings/Templates"
  ],
  "filesToIgnore": [{"match": "(^|/)(AGENTS|CLAUDE)\\.md$", "flags": ""}],
  "linterLocale": "system-default",
  "logLevel": "ERROR",
  "lintCommands": [],
  "customRegexes": [],
  "commonStyles": {
    "aliasArrayStyle": "multi-line",
    "tagArrayStyle": "multi-line",
    "minimumNumberOfDollarSignsToBeAMathBlock": 2,
    "escapeCharacter": "\"",
    "removeUnnecessaryEscapeCharsForMultiLineArrays": false
  }
}
EOF
fi

# --- Templater ---
echo "  Configuring: Templater"
if [ -f "$PLUGINS_DIR/templater-obsidian/main.js" ] && [ ! -e "$PLUGINS_DIR/templater-obsidian/data.json" ]; then
cat > "$PLUGINS_DIR/templater-obsidian/data.json" << 'EOF'
{
  "command_timeout": 5,
  "templates_folder": "system-settings/Templates",
  "templates_pairs": [["", ""]],
  "trigger_on_file_creation": true,
  "auto_jump_to_cursor": false,
  "enable_system_commands": false,
  "shell_path": "",
  "user_scripts_folder": "",
  "enable_folder_templates": true,
  "folder_templates": [
    {
      "folder": "system-settings/Templates",
      "template": "system-settings/Templates/Full Note Template.md"
    },
    {
      "folder": "5. Resources/Personal/Journal/Morning Entries",
      "template": "system-settings/Templates/Journal Entry Template.md"
    },
    {
      "folder": "5. Resources/Personal/Journal/Evening Entries",
      "template": "system-settings/Templates/Evening Journal Template.md"
    },
    { "folder": "", "template": "" }
  ],
  "enable_file_templates": false,
  "file_templates": [{ "regex": ".*", "template": "" }],
  "syntax_highlighting": true,
  "syntax_highlighting_mobile": false,
  "enabled_templates_hotkeys": [],
  "startup_templates": [""],
  "intellisense_render": 1
}
EOF
fi

# --- Git ---
echo "  Configuring: Git"
if [ -f "$PLUGINS_DIR/obsidian-git/main.js" ] && [ ! -e "$PLUGINS_DIR/obsidian-git/data.json" ]; then
cat > "$PLUGINS_DIR/obsidian-git/data.json" << 'EOF'
{
  "commitMessage": "vault backup: {{date}}",
  "autoCommitMessage": "vault backup: {{date}}",
  "commitDateFormat": "YYYY-MM-DD HH:mm:ss",
  "autoSaveInterval": 0,
  "autoPushInterval": 0,
  "autoPullInterval": 0,
  "autoPullOnBoot": false,
  "disablePush": false,
  "pullBeforePush": true,
  "disablePopups": false,
  "showErrorNotices": true,
  "showStatusBar": true,
  "syncMethod": "merge",
  "refreshSourceControl": true,
  "showBranchStatusBar": true,
  "showFileMenu": true,
  "diffStyle": "split"
}
EOF
else
  echo "    SKIP (config exists): obsidian-git"
fi

echo ""

# --- 3. Update community-plugins.json ---
echo "[3/4] Updating community-plugins.json..."

python3 - "$VAULT/.obsidian" "$successful_plugins" <<'PYMERGE'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1]); target = root / "community-plugins.json"
existing = json.loads(target.read_text()) if target.exists() else []
ids = sys.argv[2].split()
for plugin in ids:
    directory = root / "plugins" / plugin
    try:
        manifest = json.loads((directory / "manifest.json").read_text())
        javascript = (directory / "main.js").read_bytes()
        valid_js = bool(javascript) and b"<html" not in javascript[:200].lower() and b"<!doctype html" not in javascript[:200].lower()
        if manifest.get("id") == plugin and manifest.get("version") and valid_js and plugin not in existing:
            existing.append(plugin)
    except (OSError, ValueError):
        pass
raw = json.dumps(existing, indent=2) + "\n"
if not target.exists() or json.loads(target.read_text()) != existing:
    target.write_text(raw)
PYMERGE
echo "  Preserved enabled plugins; added successfully installed plugins"

echo ""

# --- 4. Set default attachment folder ---
# Without this, Obsidian's default sends pasted images/screenshots to the vault
# root. Point them at system-settings/Pasted Images to match the canonical vault.
echo "[4/4] Setting attachment folder location..."

APP_JSON="$VAULT/.obsidian/app.json"
if [ ! -f "$APP_JSON" ]; then
  cat > "$APP_JSON" << 'EOF'
{
  "attachmentFolderPath": "system-settings/Pasted Images"
}
EOF
  echo "  Set attachments -> system-settings/Pasted Images"
else
  echo "  SKIP (app.json exists): not overwriting existing Obsidian settings."
  echo "  If pasted images land in the vault root, set Settings -> Files & Links"
  echo "  -> 'Default location for new attachments' to system-settings/Pasted Images."
fi

echo ""
echo "=== Obsidian plugin step finished ==="
echo ""
echo "IMPORTANT: Restart Obsidian for changes to take effect."
echo ""
echo "After restart, verify:"
echo "  1. Settings → Community Plugins → all 10 plugins listed and enabled"
echo "  2. Open a terminal: Cmd+P → 'Terminal: Open terminal'"
echo "  3. Create a note from its template; Linter preserves the template-defined type/status"
echo "  4. Settings → Local REST API → copy the API Key (needed for MCP setup)"
echo ""
echo "Plugin list:"
echo "  - Terminal         → integrated terminal for Claude Code"
echo "  - Linter           → formats YAML on save; templates supply note fields"
echo "  - Templater        → folder templates for journals, daily hubs"
echo "  - Dataview         → advanced queries"
echo "  - Git              → version control from Obsidian"
echo "  - Local REST API   → MCP bridge (obsidian-mcp-tools depends on this)"
echo "  - MCP Tools        → Claude Code ↔ Obsidian connection"
echo "  - Editing Toolbar  → formatting toolbar"
echo "  - Excalidraw       → visual diagrams"
echo "  - Smart Connections → AI-powered note linking"

if [ "$failed" -gt 0 ]; then
  echo "INCOMPLETE: $failed plugin download(s) failed. Vault files and custom settings are preserved."
  echo "Retry: bash setup/setup-plugins.sh \"$VAULT\""
  exit 2
fi
