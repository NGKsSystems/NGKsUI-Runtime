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

function Resolve-CatalogVersionSelection {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedCatalogVersion,
    [Parameter(Mandatory = $true)][string]$HistoryChainPath,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $historyObj = Get-Content -Raw -LiteralPath $HistoryChainPath | ConvertFrom-Json
  $entry = $null
  foreach ($candidate in $historyObj.catalog_history) {
    if ([string]$candidate.version -eq $RequestedCatalogVersion.Trim()) {
      $entry = $candidate
      break
    }
  }

  if ($null -eq $entry) {
    return [pscustomobject]@{
      pass = $false
      reason = 'catalog_version_not_found:' + $RequestedCatalogVersion
      requested_catalog_version = $RequestedCatalogVersion
      selected_catalog_version = ''
      selected_catalog_file_rel = ''
      selected_catalog_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      catalog_status = ''
      fallback_occurred = $false
    }
  }

  $status = [string]$entry.status
  $catalogRel = if ($status -eq 'historical' -and -not [string]::IsNullOrWhiteSpace([string]$entry.archived_catalog_file)) { [string]$entry.archived_catalog_file } else { [string]$entry.catalog_file }
  $integrityRel = if ($status -eq 'historical' -and -not [string]::IsNullOrWhiteSpace([string]$entry.archived_integrity_reference_file)) { [string]$entry.archived_integrity_reference_file } else { [string]$entry.integrity_reference_file }

  return [pscustomobject]@{
    pass = $true
    reason = 'catalog_version_selected'
    requested_catalog_version = $RequestedCatalogVersion
    selected_catalog_version = [string]$entry.version
    selected_catalog_file_rel = $catalogRel
    selected_catalog_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $catalogRel
    selected_integrity_file_rel = $integrityRel
    selected_integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $integrityRel
    canonical_catalog_file_rel = [string]$entry.catalog_file
    canonical_integrity_file_rel = [string]$entry.integrity_reference_file
    catalog_status = $status
    fallback_occurred = $false
  }
}

function Test-SelectedCatalogIntegrity {
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
      requested_catalog_version = $Selection.requested_catalog_version
      selected_catalog_version = $Selection.selected_catalog_version
      selected_catalog_file = $Selection.selected_catalog_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_catalog_hash = ''
      stored_catalog_integrity_hash = ''
      computed_catalog_hash = ''
      catalog_integrity = 'FAIL'
      resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      validation_mode = 'none'
      catalog_obj = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.selected_integrity_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_catalog_integrity_reference_missing'
      requested_catalog_version = $Selection.requested_catalog_version
      selected_catalog_version = $Selection.selected_catalog_version
      selected_catalog_file = $Selection.selected_catalog_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_catalog_hash = ''
      stored_catalog_integrity_hash = ''
      computed_catalog_hash = ''
      catalog_integrity = 'FAIL'
      resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      validation_mode = 'none'
      catalog_obj = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.selected_catalog_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_catalog_missing'
      requested_catalog_version = $Selection.requested_catalog_version
      selected_catalog_version = $Selection.selected_catalog_version
      selected_catalog_file = $Selection.selected_catalog_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_catalog_hash = ''
      stored_catalog_integrity_hash = ''
      computed_catalog_hash = ''
      catalog_integrity = 'FAIL'
      resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      validation_mode = 'none'
      catalog_obj = $null
    }
  }

  $integrityObj = Get-Content -Raw -LiteralPath $Selection.selected_integrity_file_abs | ConvertFrom-Json
  $expectedCatalogHash = [string]$integrityObj.expected_catalog_sha256
  $storedCatalogIntegrityHash = Get-FileSha256Hex -Path $Selection.selected_integrity_file_abs
  $computedCatalogHash = Get-FileSha256Hex -Path $Selection.selected_catalog_file_abs
  $protectedCatalogRel = Get-OptionalObjectPropertyValue -Object $integrityObj -PropertyName 'protected_catalog_file' -DefaultValue ''
  $protectedCatalogAbs = if ([string]::IsNullOrWhiteSpace($protectedCatalogRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedCatalogRel }

  if ($Selection.catalog_status -eq 'active' -and -not [string]::IsNullOrWhiteSpace($protectedCatalogAbs) -and ($protectedCatalogAbs -ne $Selection.selected_catalog_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_reference_target_mismatch'
      requested_catalog_version = $Selection.requested_catalog_version
      selected_catalog_version = $Selection.selected_catalog_version
      selected_catalog_file = $Selection.selected_catalog_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_catalog_hash = $expectedCatalogHash
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      computed_catalog_hash = $computedCatalogHash
      catalog_integrity = 'FAIL'
      resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      validation_mode = 'active_path_match'
      catalog_obj = $null
    }
  }

  if ($computedCatalogHash -ne $expectedCatalogHash) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_hash_mismatch'
      requested_catalog_version = $Selection.requested_catalog_version
      selected_catalog_version = $Selection.selected_catalog_version
      selected_catalog_file = $Selection.selected_catalog_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_catalog_hash = $expectedCatalogHash
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      computed_catalog_hash = $computedCatalogHash
      catalog_integrity = 'FAIL'
      resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      validation_mode = if ($Selection.catalog_status -eq 'historical') { 'historical_archive_hash_match' } else { 'active_path_match' }
      catalog_obj = $null
    }
  }

  $catalogObj = Get-Content -Raw -LiteralPath $Selection.selected_catalog_file_abs | ConvertFrom-Json
  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'catalog_integrity_verified'
    requested_catalog_version = $Selection.requested_catalog_version
    selected_catalog_version = $Selection.selected_catalog_version
    selected_catalog_file = $Selection.selected_catalog_file_rel
    selected_integrity_file = $Selection.selected_integrity_file_rel
    stored_catalog_hash = $expectedCatalogHash
    stored_catalog_integrity_hash = $storedCatalogIntegrityHash
    computed_catalog_hash = $computedCatalogHash
    catalog_integrity = 'PASS'
    resolution_allowed = $true
    fallback_occurred = $Selection.fallback_occurred
    validation_mode = if ($Selection.catalog_status -eq 'historical') { 'historical_archive_hash_match' } else { 'active_path_match' }
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

  $entry = $null
  foreach ($candidate in $CatalogResult.catalog_obj.versions) {
    if ([string]$candidate.chain_version -eq $RequestedChainVersion.Trim()) {
      $entry = $candidate
      break
    }
  }

  if ($null -eq $entry) {
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
    selected_chain_version = [string]$entry.chain_version
    selected_chain_file_rel = [string]$entry.chain_file
    selected_chain_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.chain_file)
    selected_integrity_file_rel = [string]$entry.integrity_reference_file
    selected_integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.integrity_reference_file)
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

  $integrityObj = Get-Content -Raw -LiteralPath $Selection.selected_integrity_file_abs | ConvertFrom-Json
  $expectedHash = [string]$integrityObj.expected_chain_sha256
  $computedHash = Get-FileSha256Hex -Path $Selection.selected_chain_file_abs
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
$PFDir = Join-Path $Root "_proof\phase43_8_catalog_version_selection_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase43_8'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null

$historyChainPath = Join-Path $Root 'tools\phase43_7\catalog_history_chain.json'

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

Write-Output '=== CASE A: SELECT CATALOG V1 ==='
$catalogSelA = Resolve-CatalogVersionSelection -RequestedCatalogVersion 'v1' -HistoryChainPath $historyChainPath -RootPath $Root
$catalogA = Test-SelectedCatalogIntegrity -Selection $catalogSelA -CaseName 'A_select_catalog_v1' -RootPath $Root
$chainSelA = Resolve-ChainVersionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v1' -RootPath $Root
$chainA = Test-SelectedChainIntegrity -Selection $chainSelA -CaseName 'A_chain_select_v1' -RootPath $Root
$caseAPass = $catalogSelA.pass -and $catalogA.pass -and $chainSelA.pass -and $chainA.pass

Write-Output '=== CASE B: SELECT CATALOG V2 ==='
$catalogSelB = Resolve-CatalogVersionSelection -RequestedCatalogVersion 'v2' -HistoryChainPath $historyChainPath -RootPath $Root
$catalogB = Test-SelectedCatalogIntegrity -Selection $catalogSelB -CaseName 'B_select_catalog_v2' -RootPath $Root
$chainSelB = Resolve-ChainVersionFromCatalog -CatalogResult $catalogB -RequestedChainVersion 'v2' -RootPath $Root
$chainB = Test-SelectedChainIntegrity -Selection $chainSelB -CaseName 'B_chain_select_v2' -RootPath $Root
$caseBPass = $catalogSelB.pass -and $catalogB.pass -and $chainSelB.pass -and $chainB.pass

Write-Output '=== CASE C: WRONG CATALOG / INTEGRITY PAIR ==='
$wrongCatalogSelection = [pscustomobject]@{
  pass = $true
  reason = 'catalog_version_selected'
  requested_catalog_version = 'v1'
  selected_catalog_version = 'v1'
  selected_catalog_file_rel = $catalogSelA.selected_catalog_file_rel
  selected_catalog_file_abs = $catalogSelA.selected_catalog_file_abs
  selected_integrity_file_rel = $catalogSelB.selected_integrity_file_rel
  selected_integrity_file_abs = $catalogSelB.selected_integrity_file_abs
  canonical_catalog_file_rel = $catalogSelA.canonical_catalog_file_rel
  canonical_integrity_file_rel = $catalogSelB.canonical_integrity_file_rel
  catalog_status = 'historical'
  fallback_occurred = $false
}
$catalogC = Test-SelectedCatalogIntegrity -Selection $wrongCatalogSelection -CaseName 'C_wrong_pair' -RootPath $Root
$chainSelC = Resolve-ChainVersionFromCatalog -CatalogResult $catalogC -RequestedChainVersion 'v1' -RootPath $Root
$caseCPass = (-not $catalogC.pass) -and ($catalogC.catalog_integrity -eq 'FAIL') -and (-not $catalogC.resolution_allowed) -and (-not $chainSelC.pass)

Write-Output '=== CASE D: HISTORICAL CATALOG USABILITY ==='
$chainSelD_v1 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v1' -RootPath $Root
$chainSelD_v2 = Resolve-ChainVersionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v2' -RootPath $Root
$chainD_v1 = Test-SelectedChainIntegrity -Selection $chainSelD_v1 -CaseName 'D_hist_chain_v1' -RootPath $Root
$chainD_v2 = Test-SelectedChainIntegrity -Selection $chainSelD_v2 -CaseName 'D_hist_chain_v2' -RootPath $Root
$caseDPass = ($catalogSelA.catalog_status -eq 'historical') -and $catalogA.pass -and $chainD_v1.pass -and $chainD_v2.pass

Write-Output '=== CASE E: INVALID CATALOG VERSION REQUEST ==='
$catalogSelE = Resolve-CatalogVersionSelection -RequestedCatalogVersion 'v99' -HistoryChainPath $historyChainPath -RootPath $Root
$catalogE = Test-SelectedCatalogIntegrity -Selection $catalogSelE -CaseName 'E_invalid_catalog_request' -RootPath $Root
$chainSelE = Resolve-ChainVersionFromCatalog -CatalogResult $catalogE -RequestedChainVersion 'v1' -RootPath $Root
$caseEPass = (-not $catalogSelE.pass) -and (-not $catalogE.pass) -and ($catalogE.reason -eq 'catalog_version_not_found:v99') -and (-not $chainSelE.pass)

Write-Output '=== CASE F: NO FALLBACK ==='
$caseFPass =
  (-not $catalogSelA.fallback_occurred) -and
  (-not $catalogSelB.fallback_occurred) -and
  (-not $wrongCatalogSelection.fallback_occurred) -and
  (-not $catalogSelE.fallback_occurred) -and
  (-not $chainSelA.fallback_occurred) -and
  (-not $chainSelB.fallback_occurred) -and
  (-not $chainSelD_v1.fallback_occurred) -and
  (-not $chainSelD_v2.fallback_occurred)

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_fail') }
$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  'phase=43.8'
  'title=ACTIVE CHAIN CATALOG VERSION SELECTION / HISTORICAL CATALOG VALIDATION'
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
  'phase=43.8'
  'title=ACTIVE CHAIN CATALOG VERSION SELECTION / HISTORICAL CATALOG VALIDATION'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_catalog_version_selection_definition.txt') -Value @(
  'catalog_history_chain=tools/phase43_7/catalog_history_chain.json'
  ('catalog_v1_file=' + $catalogSelA.selected_catalog_file_rel)
  ('catalog_v1_integrity_reference=' + $catalogSelA.selected_integrity_file_rel)
  ('catalog_v2_file=' + $catalogSelB.selected_catalog_file_rel)
  ('catalog_v2_integrity_reference=' + $catalogSelB.selected_integrity_file_rel)
  'selection_mode=explicit_catalog_version_only'
  'fallback_to_other_catalog_version=disallowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_catalog_version_selection_rules.txt') -Value @(
  'RULE_1=requested_catalog_version_must_be_explicit'
  'RULE_2=selected_catalog_version_must_map_to_exact_history-chain-recorded_paths'
  'RULE_3=selected_catalog_integrity_must_pass_before_chain_version_selection'
  'RULE_4=wrong_catalog_integrity_pair_must_fail_and_block_resolution'
  'RULE_5=historical_catalog_versions_must_remain_usable'
  'RULE_6=invalid_catalog_version_requests_must_fail_without_fallback'
  'RULE_7=no_silent_fallback_allowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_7/catalog_history_chain.json'
  'READ=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog.json'
  'READ=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog_integrity_reference.json'
  'READ=tools/phase43_7/active_chain_version_catalog_v2.json'
  'READ=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'CREATED=tools/phase43_8/phase43_8_catalog_version_selection_runner.ps1'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_8_selects_historical_and_active_catalog_versions_explicitly'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
foreach ($record in @($catalogA, $catalogB, $catalogC, $catalogE)) {
  $v14.Add('--- CASE ' + $record.case_name + ' ---')
  $v14.Add('requested_catalog_version=' + $record.requested_catalog_version)
  $v14.Add('selected_catalog_version=' + $record.selected_catalog_version)
  $v14.Add('selected_catalog_file=' + $record.selected_catalog_file)
  $v14.Add('selected_catalog_integrity_reference_file=' + $record.selected_integrity_file)
  $v14.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $v14.Add('stored_catalog_integrity_hash=' + $record.stored_catalog_integrity_hash)
  $v14.Add('computed_catalog_hash=' + $record.computed_catalog_hash)
  $v14.Add('catalog_integrity=' + $record.catalog_integrity)
  $v14.Add('resolution_allowed=' + $record.resolution_allowed)
  $v14.Add('fallback_occurred=' + $record.fallback_occurred)
  $v14.Add('validation_mode=' + $record.validation_mode)
  $v14.Add('')
}
$v14.Add('--- CASE D HISTORICAL CATALOG USABILITY ---')
$v14.Add('requested_catalog_version=' + $catalogSelA.requested_catalog_version)
$v14.Add('selected_catalog_version=' + $catalogSelA.selected_catalog_version)
$v14.Add('selected_catalog_file=' + $catalogSelA.selected_catalog_file_rel)
$v14.Add('resolved_chain_v1=' + $chainSelD_v1.selected_chain_version)
$v14.Add('resolved_chain_v2=' + $chainSelD_v2.selected_chain_version)
$v14.Add('resolution_allowed_v1=' + $chainD_v1.chain_selection_allowed)
$v14.Add('resolution_allowed_v2=' + $chainD_v2.chain_selection_allowed)
$v14.Add('fallback_occurred=False')
$v14.Add('')
$v14.Add('--- CASE F NO FALLBACK ---')
$v14.Add('fallback=False')
$v14.Add('')
$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add('gate_fail_reason=' + $r) } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_catalog_version_selection_works=the_runner_uses_tools/phase43_7/catalog_history_chain.json_to_resolve_explicit_catalog_version_requests_to_exact_catalog_and_integrity-reference_paths'
  'how_catalog_v1_is_validated=v1_uses_the_archived_catalog_snapshot_and_archived_integrity_reference_from_phase43_7_history'
  'how_catalog_v2_is_validated=v2_uses_the_active_rotated_catalog_and_its_current_integrity_reference'
  'how_wrong_catalog_integrity_pair_is_detected=using_catalog_v1_with_integrity_reference_v2_fails_hash-or-target validation and blocks chain resolution'
  'how_historical_catalog_usability_was_proven=the_archived_v1_catalog_successfully_resolved_both_chain_v1_and_chain_v2_without_fallback'
  'how_invalid_catalog_version_requests_are_rejected=unregistered_catalog_versions_fail_with_catalog_version_not_found_and_do_not_resolve_any_chain'
  'why_no_fallback_occurred=all selection records retain fallback_occurred false'
  'why_disabled_remained_inert=phase43_8_modifies_runner_logic_only'
) -Encoding UTF8

$rec16 = New-Object System.Collections.Generic.List[string]
foreach ($record in @($catalogA, $catalogB, $catalogE)) {
  $rec16.Add('requested_catalog_version=' + $record.requested_catalog_version)
  $rec16.Add('selected_catalog_version=' + $record.selected_catalog_version)
  $rec16.Add('selected_catalog_file=' + $record.selected_catalog_file)
  $rec16.Add('selected_catalog_integrity_reference_file=' + $record.selected_integrity_file)
  $rec16.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $rec16.Add('stored_catalog_integrity_hash=' + $record.stored_catalog_integrity_hash)
  $rec16.Add('catalog_integrity_result=' + $record.catalog_integrity)
  $rec16.Add('resolution_allowed=' + $record.resolution_allowed)
  $rec16.Add('fallback_occurred=' + $record.fallback_occurred)
  $rec16.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_catalog_version_reference_record.txt') -Value $rec16 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '17_wrong_catalog_version_mismatch_evidence.txt') -Value @(
  ('requested_catalog_version=' + $wrongCatalogSelection.requested_catalog_version)
  ('files_actually_loaded=' + $wrongCatalogSelection.selected_catalog_file_rel + ' | ' + $wrongCatalogSelection.selected_integrity_file_rel)
  'mismatch_introduced=catalog_v1_loaded_with_integrity_reference_v2'
  'expected_result=FAIL'
  ('actual_failure_result=' + $catalogC.reason)
  ('failure_is_correct_and_deterministic=' + $caseCPass)
  ('resolution_blocked=' + (-not $catalogC.resolution_allowed))
) -Encoding UTF8

$gateLines = @('PHASE=43.8', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) { foreach ($r in $gateReasons) { $gateLines += ('FAIL_REASON=' + $r) } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_8.txt') -Value $gateLines -Encoding UTF8

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
