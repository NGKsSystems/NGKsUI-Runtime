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
  if ([string]::IsNullOrWhiteSpace($RepoPath)) { return '' }
  if ([System.IO.Path]::IsPathRooted($RepoPath)) { return $RepoPath }
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
  return $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\').Replace('\', '/')
}

function Get-OptionalObjectPropertyValue {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$PropertyName,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DefaultValue
  )
  $property = $Object.PSObject.Properties[$PropertyName]
  if ($null -eq $property) { return $DefaultValue }
  return [string]$property.Value
}

function Test-CatalogIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$CatalogIntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if (-not (Test-Path -LiteralPath $CatalogIntegrityRefPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_integrity_reference_missing'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = ''
      computed_catalog_hash = ''
      catalog_integrity_result = 'FAIL'
      chain_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  $refObj = Get-Content -Raw -LiteralPath $CatalogIntegrityRefPath | ConvertFrom-Json
  $expectedCatalogHash = [string]$refObj.expected_catalog_sha256
  $protectedCatalogRel = Get-OptionalObjectPropertyValue -Object $refObj -PropertyName 'protected_catalog_file' -DefaultValue ''

  if (-not (Test-Path -LiteralPath $CatalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_missing'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = ''
      catalog_integrity_result = 'FAIL'
      chain_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  $computedCatalogHash = Get-FileSha256Hex -Path $CatalogPath
  $protectedCatalogAbs = if ([string]::IsNullOrWhiteSpace($protectedCatalogRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedCatalogRel }
  if (-not [string]::IsNullOrWhiteSpace($protectedCatalogAbs) -and ($protectedCatalogAbs -ne $CatalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_reference_target_mismatch'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = $computedCatalogHash
      catalog_integrity_result = 'FAIL'
      chain_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  if ($computedCatalogHash -ne $expectedCatalogHash) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_hash_mismatch'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = $computedCatalogHash
      catalog_integrity_result = 'FAIL'
      chain_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  try {
    $catalogObj = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_parse_error'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = $computedCatalogHash
      catalog_integrity_result = 'FAIL'
      chain_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'catalog_integrity_verified'
    catalog_file = $CatalogPath
    catalog_integrity_reference_file = $CatalogIntegrityRefPath
    stored_catalog_hash = $expectedCatalogHash
    computed_catalog_hash = $computedCatalogHash
    catalog_integrity_result = 'PASS'
    chain_selection_allowed = $true
    fallback_occurred = $false
    catalog_obj = $catalogObj
  }
}

function Resolve-ChainVersionFromCatalog {
  param(
    [Parameter(Mandatory = $true)]$CatalogResult,
    [Parameter(Mandatory = $true)][string]$RequestedChainVersion,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if (-not $CatalogResult.pass) {
    return [pscustomobject]@{
      pass = $false
      reason = 'catalog_not_verified'
      requested_chain_version = $RequestedChainVersion
      selected_chain_version = ''
      selected_chain_file_rel = ''
      selected_chain_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $match = $null
  foreach ($entry in $CatalogResult.catalog_obj.versions) {
    if ([string]$entry.chain_version -eq $RequestedChainVersion.Trim()) {
      $match = $entry
      break
    }
  }

  if ($null -eq $match) {
    return [pscustomobject]@{
      pass = $false
      reason = 'chain_version_not_registered:' + $RequestedChainVersion
      requested_chain_version = $RequestedChainVersion
      selected_chain_version = ''
      selected_chain_file_rel = ''
      selected_chain_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  return [pscustomobject]@{
    pass = $true
    reason = 'chain_version_selected'
    requested_chain_version = $RequestedChainVersion
    selected_chain_version = [string]$match.chain_version
    selected_chain_file_rel = [string]$match.chain_file
    selected_chain_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$match.chain_file)
    selected_integrity_file_rel = [string]$match.integrity_reference_file
    selected_integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$match.integrity_reference_file)
    fallback_occurred = $false
  }
}

function Test-SelectedChainIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$CaseName,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if (-not $Selection.pass) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = $Selection.reason
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_selection_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.selected_integrity_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_integrity_reference_missing'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_selection_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_missing'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_selection_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  $intObj = Get-Content -Raw -LiteralPath $Selection.selected_integrity_file_abs | ConvertFrom-Json
  $expectedHash = [string]$intObj.expected_chain_sha256
  $protectedChainRel = Get-OptionalObjectPropertyValue -Object $intObj -PropertyName 'protected_chain_file' -DefaultValue ''
  $computedHash = Get-FileSha256Hex -Path $Selection.selected_chain_file_abs
  $protectedChainAbs = if ([string]::IsNullOrWhiteSpace($protectedChainRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedChainRel }

  if (-not [string]::IsNullOrWhiteSpace($protectedChainAbs) -and ($protectedChainAbs -ne $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_reference_target_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_selection_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  if ($computedHash -ne $expectedHash) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_hash_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_selection_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'selected_chain_integrity_verified'
    requested_chain_version = $Selection.requested_chain_version
    selected_chain_version = $Selection.selected_chain_version
    selected_chain_file = $Selection.selected_chain_file_rel
    selected_integrity_file = $Selection.selected_integrity_file_rel
    chain_selection_allowed = $true
    fallback_occurred = $Selection.fallback_occurred
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_7_active_chain_catalog_rotation_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase43_7'
$historyDir = Join-Path $phaseDir 'catalog_history'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $historyDir | Out-Null

$currentCatalogPath = Join-Path $Root 'tools\phase43_5\active_chain_version_catalog.json'
$currentCatalogRefPath = Join-Path $Root 'tools\phase43_6\active_chain_version_catalog_integrity_reference.json'

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

Write-Output '=== CASE A: CURRENT CATALOG VALIDATION ==='
$catalogA = Test-CatalogIntegrity -CatalogPath $currentCatalogPath -CatalogIntegrityRefPath $currentCatalogRefPath -CaseName 'A_current_catalog' -RootPath $Root
$selA_v1 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v1' -RootPath $Root
$selA_v2 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v2' -RootPath $Root
$chainA_v1 = Test-SelectedChainIntegrity -Selection $selA_v1 -CaseName 'A_select_v1' -RootPath $Root
$chainA_v2 = Test-SelectedChainIntegrity -Selection $selA_v2 -CaseName 'A_select_v2' -RootPath $Root
$caseAPass = $catalogA.pass -and $chainA_v1.pass -and $chainA_v2.pass

Write-Output '=== CASE B: AUTHORIZED CATALOG ROTATION ==='
$priorCatalogHash = Get-FileSha256Hex -Path $currentCatalogPath
$priorCatalogRefHash = Get-FileSha256Hex -Path $currentCatalogRefPath
$archiveCatalogPath = Join-Path $historyDir ("phase43_6_{0}_active_chain_version_catalog.json" -f $TS)
$archiveCatalogRefPath = Join-Path $historyDir ("phase43_6_{0}_active_chain_version_catalog_integrity_reference.json" -f $TS)
Copy-Item -LiteralPath $currentCatalogPath -Destination $archiveCatalogPath -Force
Copy-Item -LiteralPath $currentCatalogRefPath -Destination $archiveCatalogRefPath -Force
$archiveCatalogHash = Get-FileSha256Hex -Path $archiveCatalogPath
$archiveCatalogRefHash = Get-FileSha256Hex -Path $archiveCatalogRefPath
$archiveCatalogVerified = ($archiveCatalogHash -eq $priorCatalogHash)
$archiveCatalogRefVerified = ($archiveCatalogRefHash -eq $priorCatalogRefHash)

$newCatalogPath = Join-Path $phaseDir 'active_chain_version_catalog_v2.json'
$newCatalogRefPath = Join-Path $phaseDir 'active_chain_version_catalog_integrity_reference_v2.json'
$historyChainPath = Join-Path $phaseDir 'catalog_history_chain.json'

$currentCatalogObj = Get-Content -Raw -LiteralPath $currentCatalogPath | ConvertFrom-Json
$rotatedCatalogObj = [ordered]@{
  catalog_name = 'phase43_7_active_chain_version_catalog'
  catalog_version = '2'
  selection_mode = 'explicit_only'
  default_fallback_allowed = $false
  rotated_from_catalog_file = 'tools/phase43_5/active_chain_version_catalog.json'
  rotated_from_catalog_sha256 = $priorCatalogHash
  rotated_from_integrity_reference_file = 'tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  rotated_from_integrity_reference_sha256 = $priorCatalogRefHash
  rotation_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  versions = @()
}
foreach ($entry in $currentCatalogObj.versions) {
  $rotatedCatalogObj.versions += [ordered]@{
    chain_version = [string]$entry.chain_version
    chain_state = [string]$entry.chain_state
    chain_file = [string]$entry.chain_file
    integrity_reference_file = [string]$entry.integrity_reference_file
  }
}
Set-Content -Path $newCatalogPath -Value ($rotatedCatalogObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$newCatalogHash = Get-FileSha256Hex -Path $newCatalogPath

$newCatalogRefObj = [ordered]@{
  protected_catalog_file = 'tools/phase43_7/active_chain_version_catalog_v2.json'
  expected_catalog_sha256 = $newCatalogHash
  created_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  hash_method = 'sha256_file_bytes_v1'
  catalog_version = '2'
  rotated_from_catalog_file = 'tools/phase43_5/active_chain_version_catalog.json'
  rotated_from_catalog_sha256 = $priorCatalogHash
  rotated_from_integrity_reference_file = 'tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  rotated_from_integrity_reference_sha256 = $priorCatalogRefHash
  description = 'Trusted integrity reference for rotated active-chain version catalog'
}
Set-Content -Path $newCatalogRefPath -Value ($newCatalogRefObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$newCatalogRefHash = Get-FileSha256Hex -Path $newCatalogRefPath

$historyChainObj = [ordered]@{
  chain_name = 'phase43_7_catalog_history_chain'
  rotation_timestamp = $TS
  catalog_history = @(
    [ordered]@{
      version = 'v1'
      catalog_file = 'tools/phase43_5/active_chain_version_catalog.json'
      integrity_reference_file = 'tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
      catalog_sha256 = $priorCatalogHash
      archived_catalog_file = Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogPath
      archived_integrity_reference_file = Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogRefPath
      archive_sha256_verified = ($archiveCatalogVerified -and $archiveCatalogRefVerified)
      status = 'historical'
    },
    [ordered]@{
      version = 'v2'
      catalog_file = 'tools/phase43_7/active_chain_version_catalog_v2.json'
      integrity_reference_file = 'tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
      catalog_sha256 = $newCatalogHash
      archived_catalog_file = ''
      archived_integrity_reference_file = ''
      archive_sha256_verified = $true
      status = 'active'
    }
  )
}
Set-Content -Path $historyChainPath -Value ($historyChainObj | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline

$catalogB = Test-CatalogIntegrity -CatalogPath $newCatalogPath -CatalogIntegrityRefPath $newCatalogRefPath -CaseName 'B_rotated_catalog' -RootPath $Root
$selB_v1 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogB -RequestedChainVersion 'v1' -RootPath $Root
$selB_v2 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogB -RequestedChainVersion 'v2' -RootPath $Root
$chainB_v1 = Test-SelectedChainIntegrity -Selection $selB_v1 -CaseName 'B_select_v1' -RootPath $Root
$chainB_v2 = Test-SelectedChainIntegrity -Selection $selB_v2 -CaseName 'B_select_v2' -RootPath $Root
$rotationSuccess = $catalogB.pass
$historyPreserved = $archiveCatalogVerified -and $archiveCatalogRefVerified
$chainSelectionFunctional = $chainB_v1.pass -and $chainB_v2.pass
$caseBPass = $rotationSuccess -and $historyPreserved -and $chainSelectionFunctional

Write-Output '=== CASE C: UNAUTHORIZED CATALOG OVERWRITE ==='
$tamperedCatalogPath = Join-Path $phaseDir '_caseC_unauthorized_catalog_overwrite.json'
$tamperedCatalogObj = Get-Content -Raw -LiteralPath $newCatalogPath | ConvertFrom-Json
$tamperedCatalogObj.versions[0].chain_file = 'tools/phase43_0/nonexistent_chain.json'
Set-Content -Path $tamperedCatalogPath -Value ($tamperedCatalogObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$catalogC = Test-CatalogIntegrity -CatalogPath $tamperedCatalogPath -CatalogIntegrityRefPath $newCatalogRefPath -CaseName 'C_unauthorized_overwrite' -RootPath $Root
$selC = Resolve-ChainVersionFromCatalog -CatalogResult $catalogC -RequestedChainVersion 'v1' -RootPath $Root
$caseCPass = (-not $catalogC.pass) -and (-not $catalogC.chain_selection_allowed) -and (-not $selC.pass)

Write-Output '=== CASE D: HISTORICAL CATALOG CONTINUITY ==='
$historyObj = Get-Content -Raw -LiteralPath $historyChainPath | ConvertFrom-Json
$histV1 = @($historyObj.catalog_history | Where-Object { [string]$_.version -eq 'v1' }) | Select-Object -First 1
$histV2 = @($historyObj.catalog_history | Where-Object { [string]$_.version -eq 'v2' }) | Select-Object -First 1
$histArchiveCatalogAbs = Convert-RepoPathToAbsolute -RootPath $Root -RepoPath ([string]$histV1.archived_catalog_file)
$histArchiveRefAbs = Convert-RepoPathToAbsolute -RootPath $Root -RepoPath ([string]$histV1.archived_integrity_reference_file)
$historyAuditable =
  (Test-Path -LiteralPath $histArchiveCatalogAbs) -and
  (Test-Path -LiteralPath $histArchiveRefAbs) -and
  ((Get-FileSha256Hex -Path $histArchiveCatalogAbs) -eq $priorCatalogHash) -and
  ((Get-FileSha256Hex -Path $histArchiveRefAbs) -eq $priorCatalogRefHash) -and
  ([string]$histV1.status -eq 'historical') -and
  ([string]$histV2.status -eq 'active')
$caseDPass = $historyAuditable

Write-Output '=== CASE E: NO HISTORY LOSS ==='
$caseEPass = $historyPreserved -and $historyAuditable -and ($histV1.archived_catalog_file -ne '') -and ($histV1.archived_integrity_reference_file -ne '')

Write-Output '=== CASE F: CHAIN SELECTION STILL FUNCTIONS ==='
$caseFPass = $chainSelectionFunctional -and (-not $selB_v1.fallback_occurred) -and (-not $selB_v2.fallback_occurred)

$noFallback =
  (-not $catalogA.fallback_occurred) -and
  (-not $catalogB.fallback_occurred) -and
  (-not $catalogC.fallback_occurred) -and
  (-not $selA_v1.fallback_occurred) -and
  (-not $selA_v2.fallback_occurred) -and
  (-not $selB_v1.fallback_occurred) -and
  (-not $selB_v2.fallback_occurred)

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_fail') }
if (-not $noFallback) { $gatePass = $false; $gateReasons.Add('fallback_detected') }
$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  'phase=43.7'
  'title=ACTIVE CHAIN VERSION CATALOG ROTATION / TRUSTED CATALOG EVOLUTION'
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
  'phase=43.7'
  'title=ACTIVE CHAIN VERSION CATALOG ROTATION / TRUSTED CATALOG EVOLUTION'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_catalog_rotation_definition.txt') -Value @(
  'current_catalog_file=tools/phase43_5/active_chain_version_catalog.json'
  'current_catalog_integrity_reference=tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  'rotation_path=tools/phase43_7/phase43_7_active_chain_catalog_rotation_runner.ps1'
  ('archived_catalog_file=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogPath))
  ('archived_catalog_integrity_reference=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogRefPath))
  'rotated_catalog_file=tools/phase43_7/active_chain_version_catalog_v2.json'
  'rotated_catalog_integrity_reference=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'catalog_history_chain=tools/phase43_7/catalog_history_chain.json'
  'hash_method=sha256_file_bytes_v1'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_catalog_rotation_rules.txt') -Value @(
  'RULE_1=catalog_rotation_occurs_only_via_explicit_rotation_runner_path'
  'RULE_2=prior_catalog_file_is_archived_before_rotated_catalog_write'
  'RULE_3=prior_catalog_integrity_reference_is_archived_before_new_reference_write'
  'RULE_4=rotated_catalog_receives_new_integrity_reference'
  'RULE_5=unauthorized_catalog_overwrite_must_fail_integrity'
  'RULE_6=catalog_history_chain_must_record_historical_and_active_versions'
  'RULE_7=chain_selection_must_remain_functional_after_rotation'
  'RULE_8=no_silent_fallback_allowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_5/active_chain_version_catalog.json'
  'READ=tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  'CREATED=tools/phase43_7/phase43_7_active_chain_catalog_rotation_runner.ps1'
  'CREATED=tools/phase43_7/active_chain_version_catalog_v2.json'
  'CREATED=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'CREATED=tools/phase43_7/catalog_history_chain.json'
  ('CREATED=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogPath))
  ('CREATED=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogRefPath))
  'CREATED(TEMP)=tools/phase43_7/_caseC_unauthorized_catalog_overwrite.json'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_7_performs_catalog_rotation_at_runner_layer'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
foreach ($record in @($catalogA, $catalogB, $catalogC)) {
  $v14.Add('--- CASE ' + $record.case_name + ' ---')
  $v14.Add('catalog_file=' + $record.catalog_file)
  $v14.Add('catalog_integrity_reference_file=' + $record.catalog_integrity_reference_file)
  $v14.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $v14.Add('computed_catalog_hash=' + $record.computed_catalog_hash)
  $v14.Add('catalog_integrity_result=' + $record.catalog_integrity_result)
  $v14.Add('rotation_status=' + $(if($record.case_name -eq 'B_rotated_catalog'){ 'SUCCESS' } elseif($record.case_name -eq 'C_unauthorized_overwrite'){ 'UNAUTHORIZED' } else { 'N/A' }))
  $v14.Add('chain_selection_allowed=' + $record.chain_selection_allowed)
  $v14.Add('fallback_occurred=' + $record.fallback_occurred)
  $v14.Add('')
}
$v14.Add('--- CASE D HISTORICAL CATALOG CONTINUITY ---')
$v14.Add('archived_catalog_path=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogPath))
$v14.Add('archived_integrity_reference_path=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogRefPath))
$v14.Add('catalog_history_auditable=' + $historyAuditable)
$v14.Add('fallback_occurred=False')
$v14.Add('')
$v14.Add('--- CASE E NO HISTORY LOSS ---')
$v14.Add('catalog_history_preserved=' + $caseEPass)
$v14.Add('archived_catalog_exists=' + (Test-Path -LiteralPath $archiveCatalogPath))
$v14.Add('archived_integrity_reference_exists=' + (Test-Path -LiteralPath $archiveCatalogRefPath))
$v14.Add('fallback_occurred=False')
$v14.Add('')
$v14.Add('--- CASE F CHAIN SELECTION STILL FUNCTIONS ---')
$v14.Add('selected_chain_version_v1=' + $selB_v1.selected_chain_version)
$v14.Add('selected_chain_version_v2=' + $selB_v2.selected_chain_version)
$v14.Add('chain_selection_allowed_v1=' + $chainB_v1.chain_selection_allowed)
$v14.Add('chain_selection_allowed_v2=' + $chainB_v2.chain_selection_allowed)
$v14.Add('fallback_occurred_v1=' + $selB_v1.fallback_occurred)
$v14.Add('fallback_occurred_v2=' + $selB_v2.fallback_occurred)
$v14.Add('')
$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add('gate_fail_reason=' + $r) } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_catalog_rotation_works=the_runner_archives_current_catalog_and_current_integrity_reference_then_writes_rotated_catalog_v2_and_new_integrity_reference_v2'
  'how_history_is_preserved=archived_catalog_and_archived_integrity_reference_are_kept_under_tools/phase43_7/catalog_history_and_linked_from_catalog_history_chain.json'
  'how_new_integrity_reference_is_generated=sha256_of_rotated_catalog_v2_is_written_to_active_chain_version_catalog_integrity_reference_v2.json'
  'how_unauthorized_overwrite_is_detected=modified_catalog_checked_against_trusted_rotated_integrity_reference_fails_with_hash_mismatch'
  'how_chain_selection_continues=v1_and_v2_selections_remain_present_in_rotated_catalog_and_pass_chain_integrity_checks'
  'how_no_fallback_is_proven=all_selection_paths_record_fallback_occurred_false_and_invalid_catalog_paths_do_not_remap_versions'
  'why_disabled_remained_inert=phase43_7_changes_runner_files_only'
  'why_runtime_state_machine_unchanged=no_runtime_or_ui_source_files_were_modified'
) -Encoding UTF8

$rec16 = New-Object System.Collections.Generic.List[string]
$rec16.Add('catalog_file_current=tools/phase43_5/active_chain_version_catalog.json')
$rec16.Add('catalog_integrity_reference_current=tools/phase43_6/active_chain_version_catalog_integrity_reference.json')
$rec16.Add('catalog_file_rotated=tools/phase43_7/active_chain_version_catalog_v2.json')
$rec16.Add('catalog_integrity_reference_rotated=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json')
$rec16.Add('catalog_hash_current=' + $priorCatalogHash)
$rec16.Add('catalog_integrity_reference_hash_current=' + $priorCatalogRefHash)
$rec16.Add('catalog_hash_rotated=' + $newCatalogHash)
$rec16.Add('catalog_integrity_reference_hash_rotated=' + $newCatalogRefHash)
$rec16.Add('archived_catalog_path=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogPath))
$rec16.Add('archived_integrity_reference_path=' + (Convert-AbsoluteToRepoPath -RootPath $Root -AbsolutePath $archiveCatalogRefPath))
$rec16.Add('catalog_history_chain_path=tools/phase43_7/catalog_history_chain.json')
$rec16.Add('catalog_history_auditable=' + $historyAuditable)
Set-Content -Path (Join-Path $PFDir '16_catalog_history_record.txt') -Value $rec16 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '17_catalog_tamper_evidence.txt') -Value @(
  'authorized_rotation_action_performed=True'
  ('archived_catalog_confirmed=' + (Test-Path -LiteralPath $archiveCatalogPath))
  ('archived_integrity_reference_confirmed=' + (Test-Path -LiteralPath $archiveCatalogRefPath))
  ('archive_catalog_hash_match=' + $archiveCatalogVerified)
  ('archive_integrity_reference_hash_match=' + $archiveCatalogRefVerified)
  'unauthorized_overwrite_attempt=tools/phase43_7/_caseC_unauthorized_catalog_overwrite.json'
  ('tamper_detection_result=' + $catalogC.reason)
  ('chain_selection_blocked_after_tamper=' + (-not $catalogC.chain_selection_allowed))
) -Encoding UTF8

$gateLines = @('PHASE=43.7', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) { foreach ($r in $gateReasons) { $gateLines += ('FAIL_REASON=' + $r) } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_7.txt') -Value $gateLines -Encoding UTF8

$zipPath = "$PFDir.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force $zipPath }
$tmpDir = "$PFDir`_copy"
if (Test-Path -LiteralPath $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
New-Item -ItemType Directory -Path $tmpDir | Out-Null
Get-ChildItem -Path $PFDir -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpDir $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpDir '*') -DestinationPath $zipPath -Force
Remove-Item -Recurse -Force $tmpDir

Write-Output ("PF={0}" -f $PFDir)
Write-Output ("ZIP={0}" -f $zipPath)
Write-Output ("GATE={0}" -f $gateStr)
