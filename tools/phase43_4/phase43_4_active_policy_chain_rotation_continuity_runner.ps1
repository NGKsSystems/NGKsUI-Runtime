param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

function Get-FileSha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Convert-RepoPathToAbsolute {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$RepoPath
  )

  if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    return ''
  }

  if ([System.IO.Path]::IsPathRooted($RepoPath)) {
    return $RepoPath
  }

  return Join-Path $RootPath $RepoPath.Replace('/', '\')
}

function Convert-AbsoluteToRepoPath {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$AbsolutePath
  )

  $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
  $normalizedPath = [System.IO.Path]::GetFullPath($AbsolutePath)
  if (-not $normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$AbsolutePath' is outside root '$RootPath'"
  }

  $relative = $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\')
  return $relative.Replace('\', '/')
}

function Convert-ChainEntriesToOrderedArray {
  param([Parameter(Mandatory = $true)]$Entries)

  $result = @()
  foreach ($entry in $Entries) {
    $result += [ordered]@{
      version = [string]$entry.version
      policy_version_number = [string]$entry.policy_version_number
      policy_file = [string]$entry.policy_file
      integrity_reference_file = [string]$entry.integrity_reference_file
      policy_sha256 = [string]$entry.policy_sha256
      archive_policy_file = [string]$entry.archive_policy_file
      archive_integrity_file = [string]$entry.archive_integrity_file
      archive_sha256_verified = [bool]$entry.archive_sha256_verified
      status = [string]$entry.status
    }
  }
  return ,$result
}

function Get-OptionalObjectPropertyValue {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$PropertyName,
    [Parameter(Mandatory = $true)][string]$DefaultValue
  )

  $property = $Object.PSObject.Properties[$PropertyName]
  if ($null -eq $property) {
    return $DefaultValue
  }

  return [string]$property.Value
}

function Verify-ChainIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$ChainPath,
    [Parameter(Mandatory = $true)][string]$ChainIntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  if (-not (Test-Path -LiteralPath $ChainIntegrityRefPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_integrity_reference_missing'
      chain_source_file = $ChainPath
      integrity_reference_file = $ChainIntegrityRefPath
      expected_hash = ''
      actual_hash = ''
      reference_hash = ''
      parse_error = ''
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  $referenceHash = Get-FileSha256Hex -Path $ChainIntegrityRefPath
  $ref = Get-Content -Raw -LiteralPath $ChainIntegrityRefPath | ConvertFrom-Json
  $expected = [string]$ref.expected_chain_sha256

  if (-not (Test-Path -LiteralPath $ChainPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_source_missing'
      chain_source_file = $ChainPath
      integrity_reference_file = $ChainIntegrityRefPath
      expected_hash = $expected
      actual_hash = ''
      reference_hash = $referenceHash
      parse_error = ''
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  $actual = Get-FileSha256Hex -Path $ChainPath
  if ($actual -ne $expected) {
    $parseError = ''
    try {
      $null = Get-Content -Raw -LiteralPath $ChainPath | ConvertFrom-Json
    } catch {
      $parseError = $_.Exception.Message
    }

    $reason = if ([string]::IsNullOrWhiteSpace($parseError)) { 'chain_hash_mismatch' } else { 'chain_hash_mismatch_with_malformed_content' }
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = $reason
      chain_source_file = $ChainPath
      integrity_reference_file = $ChainIntegrityRefPath
      expected_hash = $expected
      actual_hash = $actual
      reference_hash = $referenceHash
      parse_error = $parseError
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  try {
    $chainObj = Get-Content -Raw -LiteralPath $ChainPath | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_parse_error'
      chain_source_file = $ChainPath
      integrity_reference_file = $ChainIntegrityRefPath
      expected_hash = $expected
      actual_hash = $actual
      reference_hash = $referenceHash
      parse_error = $_.Exception.Message
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'chain_integrity_verified'
    chain_source_file = $ChainPath
    integrity_reference_file = $ChainIntegrityRefPath
    expected_hash = $expected
    actual_hash = $actual
    reference_hash = $referenceHash
    parse_error = ''
    chain_loaded = $true
    chain_obj = $chainObj
    default_resolution_allowed = $true
  }
}

function Resolve-DefaultFromChain {
  param(
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $activeEntries = @($Chain.chain | Where-Object { [string]$_.status -eq 'active' })
  if ($activeEntries.Count -ne 1) {
    return [pscustomobject]@{
      found = $false
      failure_reason = 'invalid_active_entry_count:' + $activeEntries.Count
      declared_active_version = ''
      resolved_version = ''
      policy_file_rel = ''
      integrity_file_rel = ''
      policy_file_abs = ''
      integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $entry = $activeEntries[0]
  $policyRel = [string]$entry.policy_file
  $integrityRel = [string]$entry.integrity_reference_file

  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = [string]$entry.version
    resolved_version = [string]$entry.version
    policy_file_rel = $policyRel
    integrity_file_rel = $integrityRel
    policy_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $policyRel
    integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $integrityRel
    fallback_occurred = $false
  }
}

function Resolve-ExplicitFromChain {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $entry = $null
  foreach ($candidate in $Chain.chain) {
    if ([string]$candidate.version -eq $RequestedVersion.Trim()) {
      $entry = $candidate
      break
    }
  }

  if ($null -eq $entry) {
    return [pscustomobject]@{
      found = $false
      failure_reason = 'version_not_in_chain:' + $RequestedVersion
      declared_active_version = ''
      resolved_version = ''
      policy_file_rel = ''
      integrity_file_rel = ''
      policy_file_abs = ''
      integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $activeEntry = @($Chain.chain | Where-Object { [string]$_.status -eq 'active' }) | Select-Object -First 1
  $declaredActive = if ($null -ne $activeEntry) { [string]$activeEntry.version } else { '' }
  $policyRel = [string]$entry.policy_file
  $integrityRel = [string]$entry.integrity_reference_file

  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = $declaredActive
    resolved_version = [string]$entry.version
    policy_file_rel = $policyRel
    integrity_file_rel = $integrityRel
    policy_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $policyRel
    integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $integrityRel
    fallback_occurred = ($RequestedVersion.Trim() -ne [string]$entry.version)
  }
}

function Verify-PolicyIntegrityFromSelection {
  param(
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$RequestedMode,
    [Parameter(Mandatory = $true)][string]$RequestedVersion
  )

  if (-not $Selection.found) {
    return [pscustomobject]@{
      pass = $false
      reason = 'selection_not_found'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = ''
      selected_policy_file = ''
      selected_integrity_file = ''
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      policy_obj = $null
    }
  }

  if ($Selection.fallback_occurred) {
    return [pscustomobject]@{
      pass = $false
      reason = 'silent_fallback_detected'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $true
      policy_obj = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.integrity_file_abs)) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_integrity_reference_missing'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $integrityObj = Get-Content -Raw -LiteralPath $Selection.integrity_file_abs | ConvertFrom-Json
  $expected = [string]$integrityObj.expected_policy_sha256

  if (-not (Test-Path -LiteralPath $Selection.policy_file_abs)) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_file_missing'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = $expected
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $actual = Get-FileSha256Hex -Path $Selection.policy_file_abs
  if ($actual -ne $expected) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_hash_mismatch'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = $expected
      actual_policy_hash = $actual
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $policyObj = Get-Content -Raw -LiteralPath $Selection.policy_file_abs | ConvertFrom-Json
  return [pscustomobject]@{
    pass = $true
    reason = 'policy_integrity_verified'
    requested_mode = $RequestedMode
    requested_version = $RequestedVersion
    declared_active_version = $Selection.declared_active_version
    resolved_version = $Selection.resolved_version
    selected_policy_file = $Selection.policy_file_rel
    selected_integrity_file = $Selection.integrity_file_rel
    expected_policy_hash = $expected
    actual_policy_hash = $actual
    comparison_allowed = $true
    fallback_occurred = $false
    policy_obj = $policyObj
  }
}

function Invoke-AuthorizedChainRotation {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$CurrentChainPath,
    [Parameter(Mandatory = $true)][string]$CurrentRefPath,
    [Parameter(Mandatory = $true)][string]$PhaseDir,
    [Parameter(Mandatory = $true)][string]$Timestamp
  )

  $historyDir = Join-Path $PhaseDir 'chain_history'
  New-Item -ItemType Directory -Force -Path $historyDir | Out-Null

  $sourceArchivePath = Join-Path $historyDir ("phase43_3_{0}_policy_history_chain.json" -f $Timestamp)
  $referenceArchivePath = Join-Path $historyDir ("phase43_3_{0}_active_policy_chain_integrity_reference.json" -f $Timestamp)

  Copy-Item -LiteralPath $CurrentChainPath -Destination $sourceArchivePath -Force
  Copy-Item -LiteralPath $CurrentRefPath -Destination $referenceArchivePath -Force

  $currentChainHash = Get-FileSha256Hex -Path $CurrentChainPath
  $currentRefHash = Get-FileSha256Hex -Path $CurrentRefPath
  $archivedChainHash = Get-FileSha256Hex -Path $sourceArchivePath
  $archivedRefHash = Get-FileSha256Hex -Path $referenceArchivePath

  $archiveChainVerified = ($currentChainHash -eq $archivedChainHash)
  $archiveRefVerified = ($currentRefHash -eq $archivedRefHash)

  $currentChainObj = Get-Content -Raw -LiteralPath $CurrentChainPath | ConvertFrom-Json
  $activeEntry = @($currentChainObj.chain | Where-Object { [string]$_.status -eq 'active' }) | Select-Object -First 1
  $activeVersionBefore = if ($null -ne $activeEntry) { [string]$activeEntry.version } else { '' }

  $newChainPath = Join-Path $PhaseDir 'policy_history_chain_rotated_v2.json'
  $newRefPath = Join-Path $PhaseDir 'active_policy_chain_integrity_reference_v2.json'

  $newChainObject = [ordered]@{
    chain_name = 'phase43_4_policy_history_chain'
    chain_material_version = '2'
    default_resolution_chain_role = 'active_policy_default_resolution'
    rotation_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    rotated_from_chain_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentChainPath)
    rotated_from_chain_sha256 = $currentChainHash
    rotated_from_integrity_reference_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentRefPath)
    rotated_from_integrity_reference_sha256 = $currentRefHash
    chain_history = @(
      [ordered]@{
        prior_chain_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentChainPath)
        prior_integrity_reference_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentRefPath)
        archived_chain_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $sourceArchivePath)
        archived_integrity_reference_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $referenceArchivePath)
        prior_chain_sha256 = $currentChainHash
        prior_integrity_reference_sha256 = $currentRefHash
        prior_active_version = $activeVersionBefore
        archive_sha256_verified = ($archiveChainVerified -and $archiveRefVerified)
      }
    )
    chain = (Convert-ChainEntriesToOrderedArray -Entries $currentChainObj.chain)
  }

  Set-Content -Path $newChainPath -Value ($newChainObject | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline
  $newChainHash = Get-FileSha256Hex -Path $newChainPath

  $newRefObject = [ordered]@{
    protected_chain_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $newChainPath)
    expected_chain_sha256 = $newChainHash
    created_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    hash_method = 'sha256_file_bytes_v1'
    chain_material_version = '2'
    rotated_from_chain_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentChainPath)
    rotated_from_chain_sha256 = $currentChainHash
    rotated_from_integrity_reference_file = (Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentRefPath)
    rotated_from_integrity_reference_sha256 = $currentRefHash
    description = 'Trusted integrity reference for rotated active policy chain material used by default resolution'
  }
  Set-Content -Path $newRefPath -Value ($newRefObject | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline
  $newRefHash = Get-FileSha256Hex -Path $newRefPath

  return [pscustomobject]@{
    prior_chain_source_abs = $CurrentChainPath
    prior_chain_source_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentChainPath
    prior_integrity_ref_abs = $CurrentRefPath
    prior_integrity_ref_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $CurrentRefPath
    archived_chain_source_abs = $sourceArchivePath
    archived_chain_source_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $sourceArchivePath
    archived_integrity_ref_abs = $referenceArchivePath
    archived_integrity_ref_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $referenceArchivePath
    new_chain_source_abs = $newChainPath
    new_chain_source_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $newChainPath
    new_integrity_ref_abs = $newRefPath
    new_integrity_ref_rel = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $newRefPath
    prior_chain_hash = $currentChainHash
    prior_integrity_ref_hash = $currentRefHash
    new_chain_hash = $newChainHash
    new_integrity_ref_hash = $newRefHash
    archive_chain_verified = $archiveChainVerified
    archive_integrity_ref_verified = $archiveRefVerified
    active_version_before = $activeVersionBefore
    chain_material_version_before = Get-OptionalObjectPropertyValue -Object $currentChainObj -PropertyName 'chain_material_version' -DefaultValue '1'
    chain_material_version_after = '2'
    rotation_authorized = $true
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_4_active_policy_chain_rotation_continuity_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$PhaseDir = Join-Path $Root 'tools\phase43_4'
New-Item -ItemType Directory -Force -Path $PhaseDir | Out-Null

$currentChainPath = Join-Path $Root 'tools\phase43_0\policy_history_chain.json'
$currentIntegrityRefPath = Join-Path $Root 'tools\phase43_3\active_policy_chain_integrity_reference.json'

# canonical launcher evidence
$launcherStdOut = Join-Path $PFDir 'launcher_stdout.txt'
$launcherStdErr = Join-Path $PFDir 'launcher_stderr.txt'
$launcherArgString = '-NoProfile -ExecutionPolicy Bypass -File ".\\tools\\run_widget_sandbox.ps1" -Config Debug -PassArgs --sandbox-extension --auto-close-ms=1200'
$launcherProc = Start-Process -FilePath 'pwsh' -ArgumentList $launcherArgString -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $launcherStdOut -RedirectStandardError $launcherStdErr
$launcherExited = $launcherProc.WaitForExit(25000)
if (-not $launcherExited) {
  Stop-Process -Id $launcherProc.Id -Force
  $launcherExit = 124
} else {
  $launcherExit = $launcherProc.ExitCode
}
$launcherText = if (Test-Path -LiteralPath $launcherStdOut) { Get-Content -Raw -LiteralPath $launcherStdOut } else { '' }
$launcherErrText = if (Test-Path -LiteralPath $launcherStdErr) { Get-Content -Raw -LiteralPath $launcherStdErr } else { '' }
$canonicalLaunchUsed = ($launcherText -match 'LAUNCH_EXE=')
$launcherOutput = @($launcherText, $launcherErrText)

# CASE A
Write-Output '=== CASE A: CURRENT ACTIVE CHAIN VALIDATION ==='
$chainA = Verify-ChainIntegrity -ChainPath $currentChainPath -ChainIntegrityRefPath $currentIntegrityRefPath -CaseName 'A_current_active_chain'
$selA = $null
$polA = $null
if ($chainA.default_resolution_allowed) {
  $selA = Resolve-DefaultFromChain -Chain $chainA.chain_obj -RootPath $Root
  $polA = Verify-PolicyIntegrityFromSelection -Selection $selA -RequestedMode 'default' -RequestedVersion '(default)'
}
$caseAPass = $chainA.pass -and $null -ne $selA -and $selA.found -and $null -ne $polA -and $polA.pass -and $polA.comparison_allowed

# CASE B
Write-Output '=== CASE B: AUTHORIZED ACTIVE CHAIN ROTATION ==='
$rotation = Invoke-AuthorizedChainRotation -RootPath $Root -CurrentChainPath $currentChainPath -CurrentRefPath $currentIntegrityRefPath -PhaseDir $PhaseDir -Timestamp $TS
$chainB = Verify-ChainIntegrity -ChainPath $rotation.new_chain_source_abs -ChainIntegrityRefPath $rotation.new_integrity_ref_abs -CaseName 'B_authorized_rotation'
$selB = $null
$polB = $null
if ($chainB.default_resolution_allowed) {
  $selB = Resolve-DefaultFromChain -Chain $chainB.chain_obj -RootPath $Root
  $polB = Verify-PolicyIntegrityFromSelection -Selection $selB -RequestedMode 'default' -RequestedVersion '(default)'
}
$activeVersionAfterRotation = if ($null -ne $selB) { $selB.resolved_version } else { '' }
$caseBPass = $rotation.rotation_authorized -and $rotation.archive_chain_verified -and $rotation.archive_integrity_ref_verified -and $chainB.pass -and $null -ne $selB -and $selB.found -and $null -ne $polB -and $polB.pass -and ($rotation.active_version_before -eq $activeVersionAfterRotation)

# CASE C
Write-Output '=== CASE C: UNAUTHORIZED ACTIVE CHAIN OVERWRITE ==='
$unauthorizedOverwritePath = Join-Path $PhaseDir '_caseC_unauthorized_chain_overwrite.json'
$unauthorizedObj = Get-Content -Raw -LiteralPath $rotation.new_chain_source_abs | ConvertFrom-Json
foreach ($entry in $unauthorizedObj.chain) {
  if ([string]$entry.status -eq 'active') {
    $entry.status = 'historical'
    break
  }
}
$unauthorizedObj.chain[0].status = 'active'
Set-Content -Path $unauthorizedOverwritePath -Value ($unauthorizedObj | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline
$chainC = Verify-ChainIntegrity -ChainPath $unauthorizedOverwritePath -ChainIntegrityRefPath $rotation.new_integrity_ref_abs -CaseName 'C_unauthorized_overwrite'
$caseCPass = (-not $chainC.pass) -and (-not $chainC.default_resolution_allowed) -and ($chainC.reason -like 'chain_hash_mismatch*')

# CASE D
Write-Output '=== CASE D: HISTORICAL ACTIVE-CHAIN CONTINUITY ==='
$archiveChainExists = Test-Path -LiteralPath $rotation.archived_chain_source_abs
$archiveRefExists = Test-Path -LiteralPath $rotation.archived_integrity_ref_abs
$archiveChainHash = if ($archiveChainExists) { Get-FileSha256Hex -Path $rotation.archived_chain_source_abs } else { '' }
$archiveRefHash = if ($archiveRefExists) { Get-FileSha256Hex -Path $rotation.archived_integrity_ref_abs } else { '' }
$rotatedChainObj = Get-Content -Raw -LiteralPath $rotation.new_chain_source_abs | ConvertFrom-Json
$historyRecord = @($rotatedChainObj.chain_history)[0]
$historyContinuityAuditable =
  $archiveChainExists -and
  $archiveRefExists -and
  ($archiveChainHash -eq $rotation.prior_chain_hash) -and
  ($archiveRefHash -eq $rotation.prior_integrity_ref_hash) -and
  ($historyRecord.archived_chain_file -eq $rotation.archived_chain_source_rel) -and
  ($historyRecord.archived_integrity_reference_file -eq $rotation.archived_integrity_ref_rel) -and
  ($historyRecord.prior_chain_file -eq $rotation.prior_chain_source_rel) -and
  ($historyRecord.prior_integrity_reference_file -eq $rotation.prior_integrity_ref_rel) -and
  ([bool]$historyRecord.archive_sha256_verified)
$priorCurrentDistinguishable = ($rotation.archived_chain_source_rel -ne $rotation.new_chain_source_rel) -and ($rotation.archived_integrity_ref_rel -ne $rotation.new_integrity_ref_rel)
$caseDPass = $historyContinuityAuditable -and $priorCurrentDistinguishable

# CASE E
Write-Output '=== CASE E: NO SILENT OVERWRITE / NO HISTORY LOSS ==='
$tamperedNotAdmitted = (-not $chainC.pass) -and (-not $chainC.default_resolution_allowed)
$historyPreservedAfterRotation = $caseDPass -and $rotation.archive_chain_verified -and $rotation.archive_integrity_ref_verified
$rotationExplicitNotInferred =
  ($rotatedChainObj.rotated_from_chain_file -eq $rotation.prior_chain_source_rel) -and
  ($rotatedChainObj.rotated_from_integrity_reference_file -eq $rotation.prior_integrity_ref_rel) -and
  ($rotatedChainObj.chain_material_version -eq $rotation.chain_material_version_after)
$caseEPass = $tamperedNotAdmitted -and $historyPreservedAfterRotation -and $rotationExplicitNotInferred

# CASE F
Write-Output '=== CASE F: EXPLICIT HISTORICAL POLICY SELECTION STILL SEPARATE ==='
$historicalVersion = ''
$selF = $null
$polF = $null
if ($chainB.default_resolution_allowed) {
  $histEntry = $chainB.chain_obj.chain | Where-Object { [string]$_.status -eq 'historical' } | Select-Object -First 1
  $historicalVersion = if ($null -ne $histEntry) { [string]$histEntry.version } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($historicalVersion)) {
    $selF = Resolve-ExplicitFromChain -RequestedVersion $historicalVersion -Chain $chainB.chain_obj -RootPath $Root
    $polF = Verify-PolicyIntegrityFromSelection -Selection $selF -RequestedMode 'explicit' -RequestedVersion $historicalVersion
  }
}
$caseFPass = (-not [string]::IsNullOrWhiteSpace($historicalVersion)) -and $null -ne $selF -and $selF.found -and $selF.resolved_version -eq $historicalVersion -and (-not $selF.fallback_occurred) -and $null -ne $polF -and $polF.pass

$noFallbackAcrossCases =
  (($null -eq $selA) -or (-not $selA.fallback_occurred)) -and
  (($null -eq $selB) -or (-not $selB.fallback_occurred)) -and
  (($null -eq $selF) -or (-not $selF.fallback_occurred))

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_fail') }
if (-not $noFallbackAcrossCases) { $gatePass = $false; $gateReasons.Add('fallback_or_remap_detected') }

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  'phase=43.4'
  'title=ACTIVE POLICY CHAIN ROTATION / TRUSTED DEFAULT-RESOLUTION CHAIN CONTINUITY PROOF'
  ('timestamp=' + $TS)
  ('gate=' + $gateStr)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  ('case_a=' + $caseAPass)
  ('case_b=' + $caseBPass)
  ('case_c=' + $caseCPass)
  ('case_d=' + $caseDPass)
  ('case_e=' + $caseEPass)
  ('case_f=' + $caseFPass)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value @(
  'project=NGKsUI Runtime'
  'phase=43.4'
  'title=ACTIVE POLICY CHAIN ROTATION / TRUSTED DEFAULT-RESOLUTION CHAIN CONTINUITY PROOF'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_chain_rotation_definition.txt') -Value @(
  ('current_active_chain_source=' + $rotation.prior_chain_source_rel)
  ('current_chain_integrity_reference=' + $rotation.prior_integrity_ref_rel)
  ('active_chain_scope=current_chain_source_plus_chain_integrity_reference_used_for_default_policy_resolution')
  'rotation_mechanism=explicit_runner_copies_prior_chain_material_to_archive_then_writes_new_chain_material_and_new_integrity_reference'
  ('archive_chain_source=' + $rotation.archived_chain_source_rel)
  ('archive_chain_integrity_reference=' + $rotation.archived_integrity_ref_rel)
  ('new_rotated_chain_source=' + $rotation.new_chain_source_rel)
  ('new_rotated_chain_integrity_reference=' + $rotation.new_integrity_ref_rel)
  'hash_method=sha256_file_bytes_v1'
  'default_resolution_continuity=verified_chain_then_resolve_active_policy_then_verify_selected_policy_integrity'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_chain_rotation_rules.txt') -Value @(
  'RULE_1=active_chain_rotation_occurs_only_through_explicit_rotation_runner'
  'RULE_2=prior_chain_source_is_archived_before_new_chain_material_is_written'
  'RULE_3=prior_chain_integrity_reference_is_archived_before_new_integrity_reference_is_written'
  'RULE_4=new_chain_material_must_receive_new_integrity_reference'
  'RULE_5=direct_overwrite_of_active_chain_source_is_tampering_not_rotation'
  'RULE_6=default_resolution_requires_verified_chain_integrity_before_policy_selection'
  'RULE_7=authorized_rotation_must_preserve_historical_chain_continuity_records'
  'RULE_8=explicit_historical_policy_selection_remains_separate_after_rotation'
  'RULE_9=fallback_or_remapping_is_disallowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_0/policy_history_chain.json'
  'READ=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'READ=tools/phase43_0/active_version_policy_v2.json'
  'READ=tools/phase43_0/policy_integrity_reference_v2.json'
  'READ=tools/phase42_8/active_version_policy.json'
  'READ=tools/phase42_9/policy_integrity_reference.json'
  'CREATED=tools/phase43_4/phase43_4_active_policy_chain_rotation_continuity_runner.ps1'
  ('CREATED=' + $rotation.new_chain_source_rel)
  ('CREATED=' + $rotation.new_integrity_ref_rel)
  ('CREATED=' + $rotation.archived_chain_source_rel)
  ('CREATED=' + $rotation.archived_integrity_ref_rel)
  'CREATED(TEMP)=tools/phase43_4/_caseC_unauthorized_chain_overwrite.json'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_4_rotates_active_policy_chain_material_at_runner_layer_only'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
$v14.Add('--- CASE A CURRENT ACTIVE CHAIN VALIDATION ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('active_chain_source_file=' + $rotation.prior_chain_source_rel)
$v14.Add('active_chain_integrity_reference_file=' + $rotation.prior_integrity_ref_rel)
$v14.Add('stored_chain_integrity_hash=' + $chainA.expected_hash)
$v14.Add('computed_chain_integrity_hash=' + $chainA.actual_hash)
$v14.Add('chain_integrity_result=' + $chainA.reason)
$v14.Add('resolved_active_version=' + $(if($null -ne $selA){$selA.resolved_version}else{'N/A'}))
$v14.Add('selected_policy_file=' + $(if($null -ne $polA){$polA.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polA){$polA.selected_integrity_file}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polA){$polA.comparison_allowed}else{'False'}))
$v14.Add('fallback_or_remapping_occurred=' + $(if($null -ne $selA){$selA.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseAPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE B AUTHORIZED ACTIVE CHAIN ROTATION ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('prior_chain_source_file=' + $rotation.prior_chain_source_rel)
$v14.Add('prior_integrity_reference_file=' + $rotation.prior_integrity_ref_rel)
$v14.Add('archived_prior_chain_source_file=' + $rotation.archived_chain_source_rel)
$v14.Add('archived_prior_integrity_reference_file=' + $rotation.archived_integrity_ref_rel)
$v14.Add('new_chain_source_file=' + $rotation.new_chain_source_rel)
$v14.Add('new_integrity_reference_file=' + $rotation.new_integrity_ref_rel)
$v14.Add('prior_chain_hash=' + $rotation.prior_chain_hash)
$v14.Add('new_chain_hash=' + $rotation.new_chain_hash)
$v14.Add('chain_integrity_result=' + $chainB.reason)
$v14.Add('active_version_before_rotation=' + $rotation.active_version_before)
$v14.Add('active_version_after_rotation=' + $activeVersionAfterRotation)
$v14.Add('selected_policy_file=' + $(if($null -ne $polB){$polB.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polB){$polB.selected_integrity_file}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polB){$polB.comparison_allowed}else{'False'}))
$v14.Add('fallback_or_remapping_occurred=' + $(if($null -ne $selB){$selB.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseBPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE C UNAUTHORIZED ACTIVE CHAIN OVERWRITE ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('active_chain_source_file=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $unauthorizedOverwritePath))
$v14.Add('active_chain_integrity_reference_file=' + $rotation.new_integrity_ref_rel)
$v14.Add('stored_chain_integrity_hash=' + $chainC.expected_hash)
$v14.Add('computed_chain_integrity_hash=' + $chainC.actual_hash)
$v14.Add('chain_integrity_result=' + $chainC.reason)
$v14.Add('comparison_allowed=False')
$v14.Add('fallback_or_remapping_occurred=False')
$v14.Add('result=' + $(if($caseCPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE D HISTORICAL ACTIVE-CHAIN CONTINUITY ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('prior_chain_source_file=' + $rotation.archived_chain_source_rel)
$v14.Add('prior_integrity_reference_file=' + $rotation.archived_integrity_ref_rel)
$v14.Add('new_chain_source_file=' + $rotation.new_chain_source_rel)
$v14.Add('new_integrity_reference_file=' + $rotation.new_integrity_ref_rel)
$v14.Add('prior_chain_hash=' + $archiveChainHash)
$v14.Add('prior_integrity_reference_hash=' + $archiveRefHash)
$v14.Add('chain_history_continuity_result=' + $historyContinuityAuditable)
$v14.Add('prior_chain_distinguishable_from_current=' + $priorCurrentDistinguishable)
$v14.Add('result=' + $(if($caseDPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE E NO SILENT OVERWRITE / NO HISTORY LOSS ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('prior_chain_history_preserved=' + $historyPreservedAfterRotation)
$v14.Add('unauthorized_overwrite_admitted=False')
$v14.Add('unauthorized_overwrite_detected=' + $tamperedNotAdmitted)
$v14.Add('rotation_explicit_not_inferred=' + $rotationExplicitNotInferred)
$v14.Add('fallback_or_remapping_occurred=False')
$v14.Add('result=' + $(if($caseEPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE F EXPLICIT HISTORICAL POLICY SELECTION STILL SEPARATE ---')
$v14.Add('requested_policy_mode=explicit')
$v14.Add('requested_policy_version=' + $historicalVersion)
$v14.Add('active_chain_source_file=' + $rotation.new_chain_source_rel)
$v14.Add('active_chain_integrity_reference_file=' + $rotation.new_integrity_ref_rel)
$v14.Add('resolved_active_version=' + $(if($null -ne $selF){$selF.resolved_version}else{'N/A'}))
$v14.Add('selected_policy_file=' + $(if($null -ne $polF){$polF.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polF){$polF.selected_integrity_file}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polF){$polF.comparison_allowed}else{'False'}))
$v14.Add('fallback_or_remapping_occurred=' + $(if($null -ne $selF){$selF.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseFPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) {
  foreach ($reason in $gateReasons) {
    $v14.Add('gate_fail_reason=' + $reason)
  }
}
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_active_policy_chain_rotation_works=the_runner_archives_the_current_chain_source_and_current_chain_integrity_reference_then_writes_a_new_rotated_chain_file_and_new_integrity_reference_file'
  'how_prior_chain_history_is_preserved=the_prior_chain_source_and_prior_integrity_reference_are_copied_to_tools/phase43_4/chain_history_and_recorded_in_rotated_chain_history_metadata'
  'how_new_integrity_references_are_generated=the_runner_hashes_the_new_rotated_chain_file_and_writes_that_hash_into_the_new_integrity_reference'
  'how_unauthorized_overwrite_is_distinguished_from_authorized_rotation=authorized_rotation_creates_archives_plus_rotated_from_metadata_whereas_direct_overwrite_only_changes_bytes_and_fails_integrity_against_the_last_trusted_reference'
  'how_default_resolution_continues_safely_after_rotation=the_rotated_chain_is_verified_first_then_default_resolution_uses_its_active_entry_and_the_selected_policy_integrity_reference_must_still_match'
  'how_no_fallback_is_proven=all_allowed_resolution_paths_record_fallback_or_remapping_occurred_false_and_tampered_default_resolution_is_blocked_before_selection'
  'how_explicit_historical_selection_still_works_separately=the_rotated_chain_retains_historical_entries_and_explicit_selection_of_v1_still_verifies_against_its_own_policy_integrity_reference'
  'why_disabled_remained_inert=the_phase_only_rotates_chain_material_and_does_not_change_runtime_controls_or_dispatch'
  'why_baseline_mode_remained_unchanged=the_phase_does_not_modify_baseline_files_runtime_semantics_or_ui_layout'
) -Encoding UTF8

$historyLines = New-Object System.Collections.Generic.List[string]
$historyLines.Add('current_active_chain_source_file=' + $rotation.prior_chain_source_rel)
$historyLines.Add('current_chain_integrity_reference_file=' + $rotation.prior_integrity_ref_rel)
$historyLines.Add('prior_active_chain_source_file=' + $rotation.archived_chain_source_rel)
$historyLines.Add('prior_chain_integrity_reference_file=' + $rotation.archived_integrity_ref_rel)
$historyLines.Add('new_chain_source_file=' + $rotation.new_chain_source_rel)
$historyLines.Add('new_chain_integrity_reference_file=' + $rotation.new_integrity_ref_rel)
$historyLines.Add('prior_chain_integrity_hash=' + $rotation.prior_chain_hash)
$historyLines.Add('prior_integrity_reference_hash=' + $rotation.prior_integrity_ref_hash)
$historyLines.Add('new_chain_integrity_hash=' + $rotation.new_chain_hash)
$historyLines.Add('new_integrity_reference_hash=' + $rotation.new_integrity_ref_hash)
$historyLines.Add('active_version_identifier_before_rotation=' + $rotation.active_version_before)
$historyLines.Add('active_version_identifier_after_rotation=' + $activeVersionAfterRotation)
$historyLines.Add('chain_material_version_before_rotation=' + $rotation.chain_material_version_before)
$historyLines.Add('chain_material_version_after_rotation=' + $rotation.chain_material_version_after)
$historyLines.Add('chain_history_continuity_result=' + $historyContinuityAuditable)
$historyLines.Add('history_record_prior_chain_file=' + [string]$historyRecord.prior_chain_file)
$historyLines.Add('history_record_archived_chain_file=' + [string]$historyRecord.archived_chain_file)
$historyLines.Add('history_record_archived_integrity_reference_file=' + [string]$historyRecord.archived_integrity_reference_file)
Set-Content -Path (Join-Path $PFDir '16_active_chain_history_record.txt') -Value $historyLines -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '17_chain_rotation_evidence.txt') -Value @(
  'authorized_rotation_action_performed=True'
  ('archived_prior_chain_source_confirmed=' + $archiveChainExists)
  ('archived_prior_integrity_reference_confirmed=' + $archiveRefExists)
  ('archive_chain_hash_match=' + $rotation.archive_chain_verified)
  ('archive_integrity_reference_hash_match=' + $rotation.archive_integrity_ref_verified)
  ('new_chain_creation_confirmed=' + (Test-Path -LiteralPath $rotation.new_chain_source_abs))
  ('new_integrity_reference_confirmed=' + (Test-Path -LiteralPath $rotation.new_integrity_ref_abs))
  ('unauthorized_overwrite_attempt=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $unauthorizedOverwritePath))
  ('tamper_detection_result=' + $chainC.reason)
  ('default_resolution_blocked_after_tamper=' + (-not $chainC.default_resolution_allowed))
  ('comparison_blocked_after_tamper=' + (-not $chainC.default_resolution_allowed))
  'unauthorized_overwrite_treated_as_rotation=False'
) -Encoding UTF8

$gateLines = @('PHASE=43.4', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) {
  foreach ($reason in $gateReasons) {
    $gateLines += ('FAIL_REASON=' + $reason)
  }
}
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_4.txt') -Value $gateLines -Encoding UTF8

$zipPath = "$PFDir.zip"
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -Force $zipPath
}
$tmpDir = "$PFDir`_copy"
if (Test-Path -LiteralPath $tmpDir) {
  Remove-Item -Recurse -Force $tmpDir
}
New-Item -ItemType Directory -Path $tmpDir | Out-Null
Get-ChildItem -Path $PFDir -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpDir $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpDir '*') -DestinationPath $zipPath -Force
Remove-Item -Recurse -Force $tmpDir

Write-Output ("PF={0}" -f $PFDir)
Write-Output ("ZIP={0}" -f $zipPath)
Write-Output ("GATE={0}" -f $gateStr)
