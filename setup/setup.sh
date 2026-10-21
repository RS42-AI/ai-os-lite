#!/usr/bin/env bash
# AI-OS Lite setup: portable vault files and the chosen assistant's skills.
set -euo pipefail
EDITION=personal
AGENT=claude
WITH_OBSIDIAN_PLUGINS=0
WITH_OBSIDIAN_MCP=0
usage() {
  cat <<'USAGE'
Usage: bash setup/setup.sh [--agent=claude|codex|both|none]
                          [--with-obsidian-plugins] [--with-obsidian-mcp] [vault_path]
Defaults: generalized workspace, Claude skills, ~/AIOS. Obsidian is optional.
A human reviews the license in a terminal before setup writes; no automatic acceptance.
Core setup requires Python 3.10+, Git and the chosen assistant CLI already installed.
Assistant skill installation needs network access; verify sign-in in a new session.
  --with-obsidian-plugins  Download community plugins into this vault; close Obsidian first.
  --with-obsidian-mcp      Configure Claude's Obsidian MCP and QMD integration (claude|both only).
                         Requires running Obsidian with Local REST API and MCP Tools enabled.
                         Use the plugins flag as well if those plugins are not installed yet.
SETUP_YES=1 skips coordination pauses, never license acceptance. Supply OBSIDIAN_API_KEY for noninteractive MCP setup.
Exit 2 means vault files are ready but one or more requested integrations are incomplete.
USAGE
}
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --edition|--agent)
      if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
        echo "ERROR: $1 requires a value"
        exit 1
      fi
      if [ "$1" = --edition ]; then EDITION="$2"; else AGENT="$2"; fi
      shift 2 ;;
    --edition=*) EDITION="${1#*=}"; shift ;;
    --agent=*) AGENT="${1#*=}"; shift ;;
    --with-obsidian-plugins) WITH_OBSIDIAN_PLUGINS=1; shift ;;
    --with-obsidian-mcp) WITH_OBSIDIAN_MCP=1; shift ;;
    --*) echo "ERROR: unknown option $1"; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
if [ ${#POSITIONAL[@]} -gt 1 ]; then echo "ERROR: provide one vault path"; exit 1; fi
if [ ${#POSITIONAL[@]} -gt 0 ]; then VAULT="${POSITIONAL[0]}"; else VAULT="$HOME/AIOS"; fi
case "$EDITION" in
  personal) ;;
  team) echo "ERROR: legacy team edition has been retired; use generalized setup; existing workspace unchanged."; exit 1 ;;
  *) echo "ERROR: unknown --edition '$EDITION'; only generalized personal setup remains."; exit 1 ;;
esac
case "$AGENT" in claude|codex|both|none) ;; *) echo "ERROR: unknown --agent '$AGENT' (expected: claude | codex | both | none)"; exit 1 ;; esac
if [ "$WITH_OBSIDIAN_MCP" -eq 1 ] && [ "$AGENT" != claude ] && [ "$AGENT" != both ]; then
  echo "ERROR: --with-obsidian-mcp requires --agent=claude or --agent=both."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/setup-vault.sh" "$VAULT"
incomplete=0
run_integration() {
  if bash "$SCRIPT_DIR/$1.sh" "$VAULT"; then return 0; fi
  echo "INCOMPLETE: $1. Retry: bash setup/$1.sh \"$VAULT\""
  incomplete=$((incomplete + 1))
}
if [ "$AGENT" = claude ] || [ "$AGENT" = both ]; then
  run_integration setup-claude-plugins
fi
if [ "$AGENT" = codex ] || [ "$AGENT" = both ]; then
  run_integration setup-codex-plugins
fi
if [ "$WITH_OBSIDIAN_PLUGINS" -eq 1 ]; then
  echo "Close Obsidian before installing community plugins."
  if [ -n "${SETUP_YES:-}" ] || read -r -p "Press Enter when ready (Ctrl+C stops here): "; then
    run_integration setup-plugins
  else
    echo "INCOMPLETE: Obsidian plugin installation was not confirmed; rerun with --with-obsidian-plugins."
    incomplete=$((incomplete + 1))
  fi
fi
if [ "$WITH_OBSIDIAN_MCP" -eq 1 ]; then
  echo "Open this vault in Obsidian and enable Local REST API and MCP Tools."
  api_key="${OBSIDIAN_API_KEY:-}"
  if [ -z "$api_key" ] && [ -z "${SETUP_YES:-}" ]; then
    read -r -p "Paste the Local REST API key (or press Enter to skip MCP): " api_key || api_key=""
  fi
  if [[ -n "${api_key//[[:space:]]/}" ]]; then
    OBSIDIAN_API_KEY="$api_key" run_integration setup-mcp
  else
    echo "INCOMPLETE: requested Obsidian MCP setup skipped; supply a key and rerun with --with-obsidian-mcp."
    incomplete=$((incomplete + 1))
  fi
fi
echo "Portable Markdown vault files are ready at: $VAULT"
echo "Read Personal/2. Projects/Vault-Setup/Vault-Setup.md to begin."
if [ "$incomplete" -gt 0 ]; then
  echo "PARTIAL: $incomplete integration step(s) need attention; rerun the listed step(s)."
  exit 2
fi
if [ "$AGENT" = none ]; then
  echo "Requested vault setup completed. Use any Markdown editor; Obsidian is optional."
else
  echo "Requested setup steps completed. Start the chosen assistant in this vault, sign in if needed, and verify Lite skills in a new session."
fi
