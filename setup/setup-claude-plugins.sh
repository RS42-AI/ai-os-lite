#!/usr/bin/env bash
# setup-claude-plugins.sh — install the AI-OS Lite Claude Code plugin
#
# Registers the AI-OS Lite marketplace and installs + enables the plugin, so
# the daily workflow commands are available in Claude Code:
#   /start-day  /process-morning  /prep-evening  /process-evening
#   /vault-commit  /project-sync
#
# Setup ORCHESTRATES installation of the bundled plugin — it does not
# vendor the plugin (setup and plugin now share one repository). The reviewed local checkout is the marketplace source.
#
# This step is OPTIONAL: if the CLI is missing or the marketplace can't be
# reached, it warns and the rest of the vault still works. Re-run this script
# alone any time: bash setup/setup-claude-plugins.sh [vault_path]
#
# Usage: bash setup/setup-claude-plugins.sh [vault_path]

set -uo pipefail   # NOTE: no -e — a plugin failure must not abort the install

VAULT="${1:-$HOME/AIOS}"

PLUGIN="ai-os-lite@ai-os-lite-marketplace"

echo "=== AI-OS Lite plugin setup ==="
echo ""

# --- 0. Preflight: claude CLI present? ---
if ! command -v claude >/dev/null 2>&1; then
  echo "  SKIP: 'claude' CLI not found on PATH."
  echo "  Install Claude Code, then re-run: bash setup/setup-claude-plugins.sh \"$VAULT\""
  exit 2
fi

# Review the exact license before downloads or user-level configuration writes.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
# Installing a different source after reviewing this license would lose the
# connection between reviewed terms and the actual package being installed.
MARKETPLACE="$PACKAGE_ROOT"
if [ -n "${AI_OS_LITE_MARKETPLACE:-}" ]; then
  if [ ! -d "$AI_OS_LITE_MARKETPLACE" ] || [ "$(cd "$AI_OS_LITE_MARKETPLACE" && pwd -P)" != "$PACKAGE_ROOT" ]; then
    echo "ERROR: marketplace override must name this reviewed local package; no files changed."
    exit 1
  fi
fi
python3 "$SCRIPT_DIR/tools/license_consent.py" "$VAULT" || exit $?

# --- 1. Register the marketplace ---
echo "[1/3] Registering AI-OS Lite marketplace ($MARKETPLACE)..."
if ! claude plugin marketplace add "$MARKETPLACE"; then
  echo ""
  echo "  WARNING: could not add the marketplace."
  echo "  Check that the client supports local marketplaces and can read this checkout."
  echo "  Vault files are ready; agent integration is incomplete — re-run this script once the repo is"
  echo "  reachable: bash setup/setup-claude-plugins.sh \"$VAULT\""
  exit 2
fi

# --- 2. Install the plugin ---
echo "[2/3] Installing AI-OS Lite plugin..."
if ! claude plugin install "$PLUGIN"; then
  echo "  WARNING: install failed. See the message above. Re-run to retry."
  exit 2
fi

# --- 3. Enable it (install != enable; both are needed for the commands to appear) ---
echo "[3/3] Enabling AI-OS Lite plugin..."
if enable_output="$(claude plugin enable "$PLUGIN" 2>&1)"; then
  printf '%s\n' "$enable_output"
elif claude plugin list --json | python3 -c '
import json, sys
plugins = json.load(sys.stdin)
sys.exit(0 if isinstance(plugins, list) and any(
    isinstance(plugin, dict) and plugin.get("id") == sys.argv[1]
    and plugin.get("scope") == "user" and plugin.get("enabled") is True
    for plugin in plugins
) else 1)
' "$PLUGIN"; then
  # Some clients enable on install and return an error when enabled again.
  # Verify the actual user-scoped state instead of matching an error message.
  echo "  AI-OS Lite is already enabled (verified in installed plugins)."
else
  printf '%s\n' "$enable_output" >&2
  echo "  WARNING: enable failed. Try manually: claude plugin enable $PLUGIN"
  exit 2
fi

echo ""
echo "=== AI-OS Lite Installed ==="
echo ""
echo "Start a fresh session in your vault, then try: /ai-os-lite:setup-context"
echo "Other commands now available: /process-morning /prep-evening"
echo "  /process-evening /vault-commit /project-sync"
