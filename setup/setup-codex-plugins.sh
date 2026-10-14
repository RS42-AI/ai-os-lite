#!/usr/bin/env bash
# setup-codex-plugins.sh — install the AI-OS Lite Codex plugin
#
# Registers the reviewed local AI-OS Lite marketplace and installs the plugin for the
# current Codex user. The plugin is user-level, while the vault remains an
# independent per-user instance.
#
# This step is OPTIONAL: if Codex is missing or the marketplace cannot be
# reached, the vault setup remains usable and this script can be re-run later.
#
# Usage: bash setup/setup-codex-plugins.sh [vault_path]

set -uo pipefail

VAULT="${1:-$HOME/AIOS}"
PLUGIN="ai-os-lite@ai-os-lite-marketplace"

echo "=== AI-OS Lite Codex plugin setup ==="
echo "Vault: $VAULT"
echo ""

if ! command -v codex >/dev/null 2>&1; then
  echo "  SKIP: 'codex' CLI not found on PATH."
  echo "  Install Codex, then re-run: bash setup/setup-codex-plugins.sh \"$VAULT\""
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

echo "[1/2] Registering AI-OS Lite marketplace ($MARKETPLACE)..."
if ! codex plugin marketplace add "$MARKETPLACE"; then
  echo ""
  echo "  WARNING: could not add the AI-OS Lite marketplace."
  echo "  Vault files are ready; agent integration is incomplete. Re-run this script to retry."
  exit 2
fi

echo "[2/2] Installing AI-OS Lite for Codex..."
if ! codex plugin add "$PLUGIN"; then
  echo "  WARNING: plugin installation failed. Re-run this script to retry."
  exit 2
fi

echo ""
echo "=== AI-OS Lite Installed for Codex ==="
echo ""
echo "Start a new Codex task with this vault as the workspace:"
echo "  $VAULT"
echo "Then try: Run \$setup-context."
