# Human license review for the native Windows bootstrap. No automatic yes mode.
# The same local receipt schema is checked by the Bash/Python setup helpers.

function Get-AiosLicensePolicy {
  param([string]$PackageRoot)
  $bytes = [IO.File]::ReadAllBytes((Join-Path $PackageRoot 'LICENSE'))
  $metadata = Get-Content -LiteralPath (Join-Path $PackageRoot 'LICENSE-METADATA.json') -Raw | ConvertFrom-Json
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  if ([string]::IsNullOrWhiteSpace($metadata.license_version) -or
      $metadata.publication_state -notin @('draft', 'release') -or
      -not $text.Contains($metadata.license_version)) {
    throw 'License text and metadata do not identify a matching draft/release policy.'
  }
  if ($metadata.publication_state -eq 'release' -and $text.Contains('DRAFT FOR PRIVATE REVIEW')) { throw 'Draft license text cannot be treated as an issued release.' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
  return @{ license_version = [string]$metadata.license_version; publication_state = [string]$metadata.publication_state;
    license_sha256 = $hash; license_text = $text; license_bytes = $bytes }
}

function Test-AiosReceipt {
  param($Receipt, $Policy)
  try {
    if ($Receipt.schema_version -ne 1 -or $Receipt.accepted -isnot [bool] -or $Receipt.accepted -ne $true -or $Receipt.affirmative_response -cne 'YES') { return $false }
    foreach ($field in @('license_version', 'license_sha256', 'publication_state')) {
      if ($Receipt.$field -cne $Policy[$field]) { return $false }
    }
    $effect = if ($Policy.publication_state -eq 'draft') { 'draft-review-only' } else { 'license-acceptance' }
    if ($Receipt.effect -cne $effect -or $Receipt.typed_name.Trim().Length -lt 2 -or $Receipt.typed_name.Length -gt 200 -or $Receipt.typed_name -match '[\x00-\x1f]') { return $false }
    # PowerShell 7 ConvertFrom-Json may materialize ISO timestamps as DateTime;
    # Windows PowerShell 5.1 leaves them as strings. Accept the same UTC value.
    if ($Receipt.accepted_at_utc -is [DateTime]) {
      if ($Receipt.accepted_at_utc.Kind -ne [DateTimeKind]::Utc) { return $false }
    } else {
      if ($Receipt.accepted_at_utc -notmatch 'Z$') { return $false }
      [void][DateTimeOffset]::Parse($Receipt.accepted_at_utc)
    }
    if ($Receipt.source -cnotin @('human-terminal', 'human-chat', 'human-windows-console')) { return $false }
    if ($Receipt.source -eq 'human-chat' -and [string]::IsNullOrWhiteSpace($Receipt.human_message_reference)) { return $false }
    if ($Receipt.capacity -ceq 'organization') {
      if ($Receipt.authority_confirmed -isnot [bool] -or $Receipt.authority_confirmed -ne $true -or $Receipt.organization.Trim().Length -lt 2 -or $Receipt.organization.Length -gt 200 -or $Receipt.organization -match '[\x00-\x1f]') { return $false }
    } elseif ($Receipt.capacity -cne 'personal' -or $Receipt.organization -or $Receipt.authority_confirmed) { return $false }
    return $true
  } catch { return $false }
}

function Assert-AiosOrdinaryPath {
  param([string]$Path)
  $current = [IO.Path]::GetFullPath($Path)
  while ($current) {
    $item = Get-Item -Force -LiteralPath $current -ErrorAction SilentlyContinue
    if ($null -ne $item) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Workspace and receipt paths must not contain links or junctions.'
      }
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ($parent -eq $current) { break }
    $current = $parent
  }
}

function Get-AiosEvidenceHash {
  param([byte[]]$Bytes)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Assert-AiosHistory {
  param([string]$History)
  Assert-AiosOrdinaryPath $History
  if (Test-Path -LiteralPath $History) {
    if (-not (Test-Path -LiteralPath $History -PathType Container)) { throw 'Acceptance history must be an ordinary directory; preserve it for owner review.' }
    foreach ($entry in Get-ChildItem -Force -LiteralPath $History) {
      Assert-AiosOrdinaryPath $entry.FullName
      if ($entry.PSIsContainer -or $entry.Name -cnotmatch '^[0-9a-f]{64}\.json$' -or
          (Get-AiosEvidenceHash ([IO.File]::ReadAllBytes($entry.FullName))) -cne $entry.BaseName) {
        throw 'Acceptance history differs from its saved evidence; preserve it for owner review.'
      }
    }
  }
}

function Save-AiosHistoryEntry {
  param([string]$History, [byte[]]$Bytes)
  $destination = Join-Path $History ((Get-AiosEvidenceHash $Bytes) + '.json')
  Assert-AiosOrdinaryPath $destination
  if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($destination)) -cne [Convert]::ToBase64String($Bytes)) {
      throw 'Acceptance history collision; preserve the existing evidence for owner review.'
    }
    return
  }
  # CreateNew cannot overwrite an existing entry, including a concurrent write.
  $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
}

# Lower-level persistence for test fixtures and the guarded human entry point.
# This never collects or invents consent; the caller must supply actual evidence.
function Save-AiosReceipt {
  param([string]$Workspace, $Policy, $Receipt)
  if (-not (Test-AiosReceipt $Receipt $Policy)) { throw 'Invalid acceptance evidence; no files changed.' }
  $recordDir = Join-Path $Workspace '.ai-os'
  $recordPath = Join-Path $recordDir 'license-acceptance.json'
  $licenseDir = Join-Path $recordDir 'licenses'
  $snapshot = Join-Path $licenseDir ($Policy.license_sha256 + '.txt')
  $history = Join-Path $recordDir 'acceptance-history'
  $ignorePath = Join-Path $recordDir '.gitignore'
  foreach ($path in @($Workspace, $recordDir, $recordPath, $licenseDir, $snapshot, $history, $ignorePath)) { Assert-AiosOrdinaryPath $path }
  Assert-AiosHistory $history
  $previous = if (Test-Path -LiteralPath $recordPath) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($recordPath)) } else { $null }
  $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($Receipt | ConvertTo-Json -Depth 4))
  if ((Test-Path -LiteralPath $snapshot) -and (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Policy.license_sha256) {
    throw 'The saved license snapshot differs from the reviewed text; preserve it for owner review.'
  }
  [void][IO.Directory]::CreateDirectory($licenseDir)
  $privateIgnore = "/license-acceptance.json`n/licenses/`n/acceptance-history/`n/.license-*.tmp`n"
  $previousIgnore = if (Test-Path -LiteralPath $ignorePath) { [IO.File]::ReadAllText($ignorePath) } else { '' }
  if (-not $previousIgnore.EndsWith($privateIgnore)) {
    $prefix = if ($previousIgnore -and -not $previousIgnore.EndsWith("`n")) { "`n" } else { '' }
    [IO.File]::AppendAllText($ignorePath, ($prefix + $privateIgnore), (New-Object Text.UTF8Encoding($false)))
  }
  if (-not (Test-Path -LiteralPath $snapshot)) { [IO.File]::WriteAllBytes($snapshot, $Policy.license_bytes) }
  [void][IO.Directory]::CreateDirectory($history)
  # Preserve even malformed old evidence without promoting it to valid consent.
  if ($null -ne $previous) { Save-AiosHistoryEntry $history ([Convert]::FromBase64String($previous)) }
  Save-AiosHistoryEntry $history $bytes
  if ($previous -ceq [Convert]::ToBase64String($bytes)) { return }
  $temporary = Join-Path $recordDir ('.license-' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllBytes($temporary, $bytes)
    $current = if (Test-Path -LiteralPath $recordPath) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($recordPath)) } else { $null }
    if ($current -cne $previous) { throw 'The current acceptance changed during review; history was preserved, but the current record was not replaced.' }
    Move-Item -LiteralPath $temporary -Destination $recordPath -Force
  } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}

# Separated for deterministic mocked-input tests. This collects data only;
# only Confirm-AiosLicense performs the terminal check and persists evidence.
function Read-AiosHumanResponse {
  param($policy)
  Write-Host $policy.license_text
  Write-Host ('Exact license SHA-256: ' + $policy.license_sha256)
  if ($policy.publication_state -eq 'draft') {
    Write-Host 'PRIVATE DRAFT: this is a review rehearsal, not operative license acceptance or publication approval.'
  }
  Write-Host 'Only you, the human user, may answer. Your response stays in this workspace; nothing is sent to RS42.'
  $answer = Read-Host 'After reading the full text, type YES to agree (anything else stops)'
  if ($answer.Trim() -cne 'YES') { throw 'License not accepted; no setup files changed.' }
  $name = (Read-Host 'Type your full name').Trim()
  $capacity = (Read-Host 'Type personal or organization for the capacity in which you accept').Trim().ToLowerInvariant()
  $organization = ''
  $authority = $false
  if ($capacity -eq 'organization') {
    $organization = (Read-Host "Type the organization's legal name").Trim()
    $authority = (Read-Host 'Type YES to confirm you are authorized to bind that organization').Trim() -ceq 'YES'
  }
  $effect = if ($policy.publication_state -eq 'draft') { 'draft-review-only' } else { 'license-acceptance' }
  $receipt = [ordered]@{
    schema_version = 1; license_version = $policy.license_version; license_sha256 = $policy.license_sha256;
    publication_state = $policy.publication_state; effect = $effect; accepted = $true; affirmative_response = 'YES';
    typed_name = $name; capacity = $capacity; organization = $organization; authority_confirmed = $authority;
    accepted_at_utc = [DateTime]::UtcNow.ToString('o'); source = 'human-windows-console'; human_message_reference = ''
  }
  if (-not (Test-AiosReceipt ([pscustomobject]$receipt) $policy)) { throw 'License response incomplete or invalid; no setup files changed.' }
  return [pscustomobject]$receipt
}

function Confirm-AiosLicense {
  param([string]$Workspace, [string]$PackageRoot, [switch]$ReviewAgain)
  $fullWorkspace = [IO.Path]::GetFullPath($Workspace).TrimEnd([char[]]"\/")
  $fullPackage = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char[]]"\/")
  if ($fullWorkspace -eq $fullPackage -or $fullWorkspace.StartsWith($fullPackage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose a workspace separate from the product checkout.'
  }
  $policy = Get-AiosLicensePolicy $PackageRoot
  $recordDir = Join-Path $Workspace '.ai-os'
  $recordPath = Join-Path $recordDir 'license-acceptance.json'
  $licenseDir = Join-Path $recordDir 'licenses'
  $snapshot = Join-Path $licenseDir ($policy.license_sha256 + '.txt')
  $ignorePath = Join-Path $recordDir '.gitignore'
  $history = Join-Path $recordDir 'acceptance-history'
  foreach ($path in @($Workspace, $recordDir, $recordPath, $licenseDir, $snapshot, $history, $ignorePath)) { Assert-AiosOrdinaryPath $path }
  Assert-AiosHistory $history
  if ((Test-Path -LiteralPath $Workspace) -and -not (Test-Path -LiteralPath $Workspace -PathType Container)) {
    throw 'Selected workspace is not a directory.'
  }
  if (-not $ReviewAgain -and (Test-Path -LiteralPath $recordPath)) {
    try {
      $existing = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
      if ((Test-AiosReceipt $existing $policy) -and (Test-Path -LiteralPath $snapshot) -and (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $policy.license_sha256) {
        $capacity = if ($existing.capacity -eq 'organization') { $existing.organization } else { 'personal capacity' }
        Write-Host ('Using the local record for ' + $existing.typed_name + ' (' + $capacity + ').')
        return
      }
    } catch { # Invalid or old evidence requires a new explicit human response.
    }
  }
  if ($Host.Name -ne 'ConsoleHost' -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    throw 'Human license review requires an interactive local console. An assistant must not accept or emulate the human. No setup files changed.'
  }
  $receipt = Read-AiosHumanResponse $policy
  Save-AiosReceipt -Workspace $Workspace -Policy $policy -Receipt $receipt
  Write-Host $(if ($policy.publication_state -eq 'draft') { 'Local review record saved.' } else { 'Local license acceptance saved.' })
}
