#Requires -Version 5.1
<#
  setup-windows.ps1 — Windows entry point for AI-OS Lite.
  Enables WSL2 + Ubuntu, installs prerequisites inside WSL, then drives the kit's
  sub-scripts directly: portable Markdown vault + chosen assistant skills.
  Obsidian plugins and Claude MCP are separate explicit opt-ins.
  Selected assistant CLIs are installed in WSL when missing; sign-in is separate.
  The user never types a Linux command.

  Usage (from an elevated PowerShell):
    .\setup-windows.ps1
    .\setup-windows.ps1 -Agent codex
    .\setup-windows.ps1 -Agent both
    .\setup-windows.ps1 -Agent codex -VaultPath "D:\My Notes\Vault"
    .\setup-windows.ps1 -Agent claude -WithObsidianPlugins -WithObsidianMcp

  The new-vault default is USERPROFILE\AIOS. -VaultPath selects an explicit
  existing or custom local Windows folder. No existing vault is discovered or moved.
  Assistant plugin configuration stays in its own user-level location.

  -WithObsidianPlugins downloads community plugins after a close-Obsidian pause.
  -WithObsidianMcp configures Claude MCP + QMD and requires claude|both plus
  running Obsidian with Local REST API and MCP Tools enabled. Use both switches
  if those plugins are not installed yet. A blank key skips MCP as incomplete.
#>
param(
  [string]$Distro = "Ubuntu",
  [string]$KitRepo = "",
  [ValidateSet("claude", "codex", "both")]
  [string]$Agent = "claude",
  [string]$VaultPath = "",
  [switch]$WithObsidianPlugins,
  [switch]$WithObsidianMcp
)
$ErrorActionPreference = "Stop"

function ConvertTo-BashLiteral {
  param([string]$Value)
  return "'" + $Value.Replace("'", "'\''") + "'"
}

function Resolve-WindowsVaultPath {
  param([string]$RequestedPath, [string]$ProfilePath)
  if ($RequestedPath -eq "") {
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
      throw "USERPROFILE is unavailable. Provide -VaultPath with an absolute local Windows folder."
    }
    $RequestedPath = $ProfilePath.TrimEnd([char[]]"\/") + '\AIOS'
  }
  # A local drive path is portable through WSL. Reject relative/UNC paths,
  # drive roots, traversal segments and Windows-invalid/control characters.
  if ($RequestedPath -notmatch '^[A-Za-z]:[\\/][^<>:"|?*\x00-\x1f]+$' -or
      $RequestedPath -match '(^|[\\/])\.\.?([\\/]|$)' -or
      $RequestedPath -match '[. ]([\\/]|$)') {
    throw "VaultPath must be an absolute local Windows folder, for example D:\Notes\AIOS."
  }
  return $RequestedPath
}

function ConvertTo-WslVaultPath {
  param([string]$WindowsPath, [string]$SelectedDistro)
  $pathArg = ConvertTo-BashLiteral $WindowsPath
  $mapped = @(wsl.exe -d $SelectedDistro -- bash -o pipefail -lc "wslpath -a -u $pathArg")
  if ($LASTEXITCODE -ne 0 -or $mapped.Count -ne 1) {
    throw "WSL could not translate the selected Windows vault path; no vault files changed."
  }
  $result = ([string]$mapped[0]).TrimEnd([char[]]"`r`n")
  if (-not $result.StartsWith('/') -or $result -match '[\x00-\x1f]') {
    throw "WSL returned an invalid vault path; no vault files changed."
  }
  return $result
}

function Test-Admin { ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltinRole]::Administrator) }

function Test-WslReady {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
  # Directly probe the distro rather than parsing wsl --list output (UTF-16LE decoding
  # is unreliable across PS 5.1 console code pages). If the distro is installed and
  # functional, `wsl -d <Distro> -- true` exits 0.
  try {
    wsl.exe -d $Distro -- true 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

# Phase 1 — preflight
if ($KitRepo) { throw "-KitRepo is retired. Run the complete reviewed local package; no files changed." }
if ($WithObsidianMcp -and $Agent -notin @("claude", "both")) {
  throw "-WithObsidianMcp requires -Agent claude or -Agent both."
}
$winVaultPath = Resolve-WindowsVaultPath $VaultPath $env:USERPROFILE
if (-not (Test-Admin)) { throw "Re-run this file as Administrator (right-click -> Run as administrator)." }

# Review the local package before WSL, downloads, prerequisites, or setup writes.
# A single detached copy of this script is insufficient: keep the full package.
. (Join-Path $PSScriptRoot 'license-consent.ps1')
Confirm-AiosLicense -Workspace $winVaultPath -PackageRoot (Split-Path $PSScriptRoot -Parent)

# Phase 2 — WSL install (reboot-and-resume)
if (-not (Test-WslReady)) {
  Write-Host "Installing WSL2 + $Distro. Your PC will need ONE restart." -ForegroundColor Cyan
  wsl.exe --install -d $Distro
  if ($LASTEXITCODE -ne 0) { throw "WSL installation failed (exit $LASTEXITCODE). Resolve the error before rebooting or continuing." }
  Write-Host "`nRESTART your PC, then double-click this file again to finish." -ForegroundColor Yellow
  exit 0   # resume on re-run after reboot
}

# Phase 3 — in-WSL prerequisites (idempotent)
# Run each command as a separate wsl.exe call with bash -lc to avoid CRLF issues:
# PS 5.1 re-encodes CRLF when piping multi-line strings to native processes even after
# an in-memory -replace, so piped here-strings reliably break bash brace-groups.
# Keep the existing WSL sudo policy. The installer may ask for the WSL user's
# password for prerequisite installation; it never grants permanent passwordless sudo.

$wslVaultPath = ConvertTo-WslVaultPath $winVaultPath $Distro
$wslVaultArg = ConvertTo-BashLiteral $wslVaultPath

Write-Host "Phase 3: Installing prerequisites in WSL..." -ForegroundColor Cyan
wsl.exe -d $Distro -- bash -o pipefail -lc 'sudo apt-get update -y && sudo apt-get install -y git curl unzip python3 jq file'
if ($LASTEXITCODE -ne 0) { throw "WSL apt-get failed (exit $LASTEXITCODE). See errors above." }

wsl.exe -d $Distro -- bash -o pipefail -lc 'command -v node >/dev/null 2>&1 || { curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs; }'
if ($LASTEXITCODE -ne 0) { throw "WSL Node.js install failed (exit $LASTEXITCODE). See errors above." }

if ($Agent -in @("claude", "both")) {
  wsl.exe -d $Distro -- bash -o pipefail -lc 'command -v claude >/dev/null 2>&1 || sudo npm install -g @anthropic-ai/claude-code'
  if ($LASTEXITCODE -ne 0) { throw "WSL Claude Code install failed (exit $LASTEXITCODE). See errors above." }
}

if ($Agent -in @("codex", "both")) {
  wsl.exe -d $Distro -- bash -o pipefail -lc 'command -v codex >/dev/null 2>&1 || sudo npm install -g @openai/codex'
  if ($LASTEXITCODE -ne 0) { throw "WSL Codex install failed (exit $LASTEXITCODE). See errors above." }
}


# Phase 4 — drive the sub-scripts directly, with the human-coordination pauses
# happening here in the PowerShell console (a real TTY) instead of piping the
# interactive setup.sh into a TTY-less bash -s (which aborts at its read pauses).

# 4.1 — run the same reviewed package through WSL; never silently fetch another
# branch or license after the person accepted the local package's exact text.
$wslPackageRoot = ConvertTo-WslVaultPath (Split-Path $PSScriptRoot -Parent) $Distro
$wslSetupArg = ConvertTo-BashLiteral ($wslPackageRoot.TrimEnd('/') + '/setup')

# 4.2 — create the portable vault on the Windows filesystem.
# Git identity and the first backup commit remain the owner's choice.
# Windows editors can read this path directly; Obsidian is optional.

wsl.exe -d $Distro -- bash -o pipefail -lc "cd $wslSetupArg && SETUP_YES=1 bash setup-vault.sh $wslVaultArg"
if ($LASTEXITCODE -ne 0) { throw "WSL vault setup failed (exit $LASTEXITCODE). See errors above." }

# 4.3 — attempt each selected assistant integration independently.
$setupFailures = @()
if ($Agent -in @("claude", "both")) {
  wsl.exe -d $Distro -- bash -o pipefail -lc "cd $wslSetupArg && bash setup-claude-plugins.sh $wslVaultArg"
  if ($LASTEXITCODE -ne 0) { $setupFailures += "Claude plugin setup" }
}
if ($Agent -in @("codex", "both")) {
  wsl.exe -d $Distro -- bash -o pipefail -lc "cd $wslSetupArg && bash setup-codex-plugins.sh $wslVaultArg"
  if ($LASTEXITCODE -ne 0) { $setupFailures += "Codex plugin setup" }
}

# 4.4 — optional Obsidian community plugins; never downloaded by core setup.
if ($WithObsidianPlugins) {
  Write-Host "Close Obsidian before installing community plugins into: $winVaultPath"
  Read-Host "Press Enter when ready (Ctrl+C stops here)" | Out-Null
  wsl.exe -d $Distro -- bash -o pipefail -lc "cd $wslSetupArg && SETUP_YES=1 bash setup-plugins.sh $wslVaultArg"
  if ($LASTEXITCODE -ne 0) { $setupFailures += "Obsidian community plugins" }
}

# 4.5 — optional Claude MCP; its prerequisites are installed only on opt-in.
if ($WithObsidianMcp) {
  Write-Host "Open Obsidian (Windows) and open this folder as a vault: $winVaultPath"
  Write-Host "Enable Local REST API and MCP Tools, then copy Settings -> Local REST API -> API Key."
  $apiKey = Read-Host "Paste the Local REST API key (or press Enter to skip MCP)"
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Warning "Requested Obsidian MCP setup skipped; no API key supplied."
    $setupFailures += "Obsidian MCP setup (skipped)"
  } else {
    # Escape the single-quoted Bash value; never print the supplied key.
    $apiKeyArg = ConvertTo-BashLiteral $apiKey
    wsl.exe -d $Distro -- bash -o pipefail -lc 'command -v bun >/dev/null 2>&1 || { curl -fsSL https://bun.sh/install | bash; }'
    if ($LASTEXITCODE -ne 0) {
      $setupFailures += "Obsidian MCP prerequisite (Bun)"
    } else {
      wsl.exe -d $Distro -- bash -o pipefail -lc "cd $wslSetupArg && OBSIDIAN_API_KEY=$apiKeyArg bash setup-mcp.sh $wslVaultArg"
      if ($LASTEXITCODE -ne 0) { $setupFailures += "Obsidian MCP setup" }
    }
  }
}
if ($setupFailures.Count -gt 0) {
  throw "Setup is incomplete: $($setupFailures -join ', '). Keep the vault and rerun the affected setup step after resolving its error."
}

# Phase 5 — report requested installation, with sign-in and live verification separate.
Write-Host "`n=== Requested setup steps finished ===" -ForegroundColor Green
Write-Host "Portable Markdown vault: $winVaultPath" -ForegroundColor Cyan
Write-Host "Use any Markdown editor; Obsidian is optional."
Write-Host "Open Ubuntu and change to the vault: cd $wslVaultArg"
if ($Agent -eq "claude") {
  Write-Host "Start Claude Code, sign in if needed, and try /ai-os-lite:setup-context in a new session." -ForegroundColor Cyan
} elseif ($Agent -eq "codex") {
  Write-Host "Start Codex, sign in if needed, and ask it to run `$setup-context in a new session." -ForegroundColor Cyan
} else {
  Write-Host "Start either Claude Code or Codex in the vault, sign in if needed, and verify the Lite skills in a new session." -ForegroundColor Cyan
}
