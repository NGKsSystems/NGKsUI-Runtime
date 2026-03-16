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

function Test-CatalogIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$CatalogIntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName
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
      stored_catalog_integrity_hash = ''
      catalog_integrity_result = 'FAIL'
      catalog_load_result = 'BLOCKED'
      chain_resolution_allowed = $false
      version_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  $storedCatalogIntegrityHash = Get-FileSha256Hex -Path $CatalogIntegrityRefPath
  $refObj = Get-Content -Raw -LiteralPath $CatalogIntegrityRefPath | ConvertFrom-Json
  $expectedCatalogHash = [string]$refObj.expected_catalog_sha256
  $protectedCatalogRel = [string]$refObj.protected_catalog_file

  if (-not (Test-Path -LiteralPath $CatalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_missing'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = ''
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      catalog_integrity_result = 'FAIL'
      catalog_load_result = 'MISSING'
      chain_resolution_allowed = $false
      version_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  $computedCatalogHash = Get-FileSha256Hex -Path $CatalogPath
  $protectedCatalogAbs = if ([string]::IsNullOrWhiteSpace($protectedCatalogRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $Root -RepoPath $protectedCatalogRel }
  if (-not [string]::IsNullOrWhiteSpace($protectedCatalogAbs) -and ($protectedCatalogAbs -ne $CatalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_reference_target_mismatch'
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = $computedCatalogHash
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      catalog_integrity_result = 'FAIL'
      catalog_load_result = 'BLOCKED'
      chain_resolution_allowed = $false
      version_selection_allowed = $false
      fallback_occurred = $false
      catalog_obj = $null
    }
  }

  if ($computedCatalogHash -ne $expectedCatalogHash) {
    $loadResult = 'BLOCKED'
    try {
      $null = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
    } catch {
      $loadResult = 'FAIL'
    }

    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = if ($loadResult -eq 'FAIL') { 'catalog_hash_mismatch_with_corruption' } else { 'catalog_hash_mismatch' }
      catalog_file = $CatalogPath
      catalog_integrity_reference_file = $CatalogIntegrityRefPath
      stored_catalog_hash = $expectedCatalogHash
      computed_catalog_hash = $computedCatalogHash
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      catalog_integrity_result = 'FAIL'
      catalog_load_result = $loadResult
      chain_resolution_allowed = $false
      version_selection_allowed = $false
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
      stored_catalog_integrity_hash = $storedCatalogIntegrityHash
      catalog_integrity_result = 'FAIL'
      catalog_load_result = 'FAIL'
      chain_resolution_allowed = $false
      version_selection_allowed = $false
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
    stored_catalog_integrity_hash = $storedCatalogIntegrityHash
    catalog_integrity_result = 'PASS'
    catalog_load_result = 'PASS'
    chain_resolution_allowed = $true
    version_selection_allowed = $true
    fallback_occurred = $false
    catalog_obj = $catalogObj
  }
}

function Resolve-ChainVersionSelectionFromCatalog {
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

function Resolve-DefaultChainVersionFromCatalog {
  param(
    [Parameter(Mandatory = $true)]$CatalogResult,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if (-not $CatalogResult.pass) {
    return [pscustomobject]@{
      pass = $false
      reason = 'catalog_not_verified'
      requested_chain_version = '(default)'
      selected_chain_version = ''
      selected_chain_file_rel = ''
      selected_chain_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $currentEntries = @($CatalogResult.catalog_obj.versions | Where-Object { [string]$_.chain_state -eq 'current_rotated' })
  if ($currentEntries.Count -ne 1) {
    return [pscustomobject]@{
      pass = $false
      reason = 'invalid_default_catalog_entry_count:' + $currentEntries.Count
      requested_chain_version = '(default)'
      selected_chain_version = ''
      selected_chain_file_rel = ''
      selected_chain_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $entry = $currentEntries[0]
  return [pscustomobject]@{
    pass = $true
    reason = 'default_chain_version_selected'
    requested_chain_version = '(default)'
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
      chain_resolution_allowed = $false
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
      chain_resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  $intObj = Get-Content -Raw -LiteralPath $Selection.selected_integrity_file_abs | ConvertFrom-Json
  $expectedChainHash = [string]$intObj.expected_chain_sha256
  $protectedChainRel = Get-OptionalObjectPropertyValue -Object $intObj -PropertyName 'protected_chain_file' -DefaultValue ''
  $protectedChainAbs = if ([string]::IsNullOrWhiteSpace($protectedChainRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedChainRel }

  if (-not (Test-Path -LiteralPath $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_missing'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  $computedChainHash = Get-FileSha256Hex -Path $Selection.selected_chain_file_abs
  if (-not [string]::IsNullOrWhiteSpace($protectedChainAbs) -and ($protectedChainAbs -ne $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_reference_target_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_resolution_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
    }
  }

  if ($computedChainHash -ne $expectedChainHash) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'selected_chain_hash_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      chain_resolution_allowed = $false
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
    chain_resolution_allowed = $true
    fallback_occurred = $Selection.fallback_occurred
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_6_active_chain_catalog_integrity_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase43_6'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null

$catalogPath = Join-Path $Root 'tools\phase43_5\active_chain_version_catalog.json'
$catalogIntegrityRefPath = Join-Path $phaseDir 'active_chain_version_catalog_integrity_reference.json'

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

Write-Output '=== CASE A: VALID CATALOG / NORMAL OPERATION ==='
$catalogA = Test-CatalogIntegrity -CatalogPath $catalogPath -CatalogIntegrityRefPath $catalogIntegrityRefPath -CaseName 'A_valid_catalog'
$defaultA = Resolve-DefaultChainVersionFromCatalog -CatalogResult $catalogA -RootPath $Root
$chainA = Test-SelectedChainIntegrity -Selection $defaultA -CaseName 'A_default_resolution' -RootPath $Root
$caseAPass = $catalogA.pass -and $defaultA.pass -and $chainA.pass -and $catalogA.version_selection_allowed -and $chainA.chain_resolution_allowed

Write-Output '=== CASE B: CATALOG TAMPER DETECTION ==='
$tamperedCatalogPath = Join-Path $phaseDir '_caseB_tampered_catalog.json'
$tamperedCatalogObj = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$tamperedCatalogObj.versions[0].chain_state = 'tampered_state'
Set-Content -Path $tamperedCatalogPath -Value ($tamperedCatalogObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$tamperedCatalogRefPath = Join-Path $phaseDir '_caseB_tampered_catalog_integrity_reference.json'
Set-Content -Path $tamperedCatalogRefPath -Value (@{
  protected_catalog_file = 'tools/phase43_6/_caseB_tampered_catalog.json'
  expected_catalog_sha256 = (Get-OptionalObjectPropertyValue -Object (Get-Content -Raw -LiteralPath $catalogIntegrityRefPath | ConvertFrom-Json) -PropertyName 'expected_catalog_sha256' -DefaultValue '')
  created_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  hash_method = 'sha256_file_bytes_v1'
  description = 'Case B tampered catalog integrity reference'
} | ConvertTo-Json -Depth 6) -Encoding UTF8 -NoNewline
$catalogB = Test-CatalogIntegrity -CatalogPath $tamperedCatalogPath -CatalogIntegrityRefPath $tamperedCatalogRefPath -CaseName 'B_tamper'
$defaultB = Resolve-DefaultChainVersionFromCatalog -CatalogResult $catalogB -RootPath $Root
$caseBPass = (-not $catalogB.pass) -and (-not $catalogB.chain_resolution_allowed) -and (-not $catalogB.version_selection_allowed) -and (-not $defaultB.pass)

Write-Output '=== CASE C: CATALOG CORRUPTION ==='
$corruptCatalogPath = Join-Path $phaseDir '_caseC_corrupt_catalog.json'
Set-Content -Path $corruptCatalogPath -Value '{"catalog_name":"broken","versions":[{"chain_version":"v1"}' -Encoding UTF8 -NoNewline
$corruptCatalogRefPath = Join-Path $phaseDir '_caseC_corrupt_catalog_integrity_reference.json'
Set-Content -Path $corruptCatalogRefPath -Value (@{
  protected_catalog_file = 'tools/phase43_6/_caseC_corrupt_catalog.json'
  expected_catalog_sha256 = (Get-OptionalObjectPropertyValue -Object (Get-Content -Raw -LiteralPath $catalogIntegrityRefPath | ConvertFrom-Json) -PropertyName 'expected_catalog_sha256' -DefaultValue '')
  created_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  hash_method = 'sha256_file_bytes_v1'
  description = 'Case C corrupt catalog integrity reference'
} | ConvertTo-Json -Depth 6) -Encoding UTF8 -NoNewline
$catalogC = Test-CatalogIntegrity -CatalogPath $corruptCatalogPath -CatalogIntegrityRefPath $corruptCatalogRefPath -CaseName 'C_corrupt'
$defaultC = Resolve-DefaultChainVersionFromCatalog -CatalogResult $catalogC -RootPath $Root
$caseCPass = (-not $catalogC.pass) -and ($catalogC.catalog_load_result -eq 'FAIL') -and (-not $defaultC.pass)

Write-Output '=== CASE D: MISSING CATALOG ==='
$missingCatalogPath = Join-Path $phaseDir '_caseD_missing_catalog.json'
if (Test-Path -LiteralPath $missingCatalogPath) { Remove-Item -Force $missingCatalogPath }
$catalogD = Test-CatalogIntegrity -CatalogPath $missingCatalogPath -CatalogIntegrityRefPath $catalogIntegrityRefPath -CaseName 'D_missing'
$defaultD = Resolve-DefaultChainVersionFromCatalog -CatalogResult $catalogD -RootPath $Root
$caseDPass = (-not $catalogD.pass) -and ($catalogD.reason -eq 'catalog_missing') -and (-not $defaultD.pass)

Write-Output '=== CASE E: CATALOG / CHAIN MISMATCH ==='
$invalidCatalogPath = Join-Path $phaseDir '_caseE_invalid_reference_catalog.json'
$invalidCatalogObj = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$invalidCatalogObj.versions[1].chain_file = 'tools/phase43_4/does_not_exist_chain.json'
Set-Content -Path $invalidCatalogPath -Value ($invalidCatalogObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$invalidCatalogHash = Get-FileSha256Hex -Path $invalidCatalogPath
$invalidCatalogRefPath = Join-Path $phaseDir '_caseE_invalid_reference_catalog_integrity_reference.json'
Set-Content -Path $invalidCatalogRefPath -Value (@{
  protected_catalog_file = 'tools/phase43_6/_caseE_invalid_reference_catalog.json'
  expected_catalog_sha256 = $invalidCatalogHash
  created_timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  hash_method = 'sha256_file_bytes_v1'
  description = 'Case E invalid-reference catalog integrity reference'
} | ConvertTo-Json -Depth 6) -Encoding UTF8 -NoNewline
$catalogE = Test-CatalogIntegrity -CatalogPath $invalidCatalogPath -CatalogIntegrityRefPath $invalidCatalogRefPath -CaseName 'E_catalog_chain_mismatch'
$defaultE = Resolve-DefaultChainVersionFromCatalog -CatalogResult $catalogE -RootPath $Root
$chainE = Test-SelectedChainIntegrity -Selection $defaultE -CaseName 'E_default_resolution' -RootPath $Root
$caseEPass = $catalogE.pass -and $defaultE.pass -and (-not $chainE.pass) -and ($chainE.reason -eq 'selected_chain_missing' -or $chainE.reason -eq 'selected_chain_reference_target_mismatch') -and (-not $chainE.chain_resolution_allowed)

Write-Output '=== CASE F: HISTORICAL CHAIN SELECTION STILL WORKS ==='
$selectV1 = Resolve-ChainVersionSelectionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v1' -RootPath $Root
$selectV2 = Resolve-ChainVersionSelectionFromCatalog -CatalogResult $catalogA -RequestedChainVersion 'v2' -RootPath $Root
$chainFv1 = Test-SelectedChainIntegrity -Selection $selectV1 -CaseName 'F_select_v1' -RootPath $Root
$chainFv2 = Test-SelectedChainIntegrity -Selection $selectV2 -CaseName 'F_select_v2' -RootPath $Root
$caseFPass = $catalogA.pass -and $selectV1.pass -and $selectV2.pass -and $chainFv1.pass -and $chainFv2.pass

$noFallback =
  (-not $catalogA.fallback_occurred) -and
  (-not $catalogB.fallback_occurred) -and
  (-not $catalogC.fallback_occurred) -and
  (-not $catalogD.fallback_occurred) -and
  (-not $catalogE.fallback_occurred) -and
  (-not $selectV1.fallback_occurred) -and
  (-not $selectV2.fallback_occurred) -and
  (-not $defaultA.fallback_occurred) -and
  (-not $defaultB.fallback_occurred) -and
  (-not $defaultC.fallback_occurred) -and
  (-not $defaultD.fallback_occurred) -and
  (-not $defaultE.fallback_occurred)

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
  'phase=43.6'
  'title=ACTIVE CHAIN VERSION CATALOG INTEGRITY / DEFAULT RESOLUTION ENFORCEMENT'
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
  'phase=43.6'
  'title=ACTIVE CHAIN VERSION CATALOG INTEGRITY / DEFAULT RESOLUTION ENFORCEMENT'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_catalog_integrity_definition.txt') -Value @(
  'catalog_file=tools/phase43_5/active_chain_version_catalog.json'
  'catalog_integrity_reference=tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  'hash_method=sha256_file_bytes_v1'
  'catalog_gates=chain_version_selection_default_chain_resolution_historical_chain_loading'
  'default_chain_resolution_rule=exactly_one_current_rotated_catalog_entry_required_after_catalog_integrity_pass'
  'fallback_to_latest=disallowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_catalog_integrity_rules.txt') -Value @(
  'RULE_1=catalog_integrity_must_be_verified_before_any_chain_selection'
  'RULE_2=catalog_integrity_mismatch_blocks_version_selection_and_chain_resolution'
  'RULE_3=corrupted_catalog_blocks_version_selection_and_chain_resolution'
  'RULE_4=missing_catalog_blocks_version_selection_and_chain_resolution'
  'RULE_5=invalid_catalog_chain_reference_blocks_chain_resolution'
  'RULE_6=historical_chain_versions_remain_usable_only_after_valid_catalog_verification'
  'RULE_7=no_silent_fallback_or_remapping_allowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_5/active_chain_version_catalog.json'
  'READ=tools/phase43_4/policy_history_chain_rotated_v2.json'
  'READ=tools/phase43_4/active_policy_chain_integrity_reference_v2.json'
  'READ=tools/phase43_0/policy_history_chain.json'
  'READ=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'CREATED=tools/phase43_6/active_chain_version_catalog_integrity_reference.json'
  'CREATED=tools/phase43_6/phase43_6_active_chain_catalog_integrity_runner.ps1'
  'CREATED(TEMP)=tools/phase43_6/_caseB_tampered_catalog.json'
  'CREATED(TEMP)=tools/phase43_6/_caseB_tampered_catalog_integrity_reference.json'
  'CREATED(TEMP)=tools/phase43_6/_caseC_corrupt_catalog.json'
  'CREATED(TEMP)=tools/phase43_6/_caseC_corrupt_catalog_integrity_reference.json'
  'CREATED(TEMP)=tools/phase43_6/_caseE_invalid_reference_catalog.json'
  'CREATED(TEMP)=tools/phase43_6/_caseE_invalid_reference_catalog_integrity_reference.json'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_6_validates_catalog_integrity_before_chain_selection_or_default_resolution'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
foreach ($record in @($catalogA, $catalogB, $catalogC, $catalogD, $catalogE)) {
  $v14.Add('--- CASE ' + $record.case_name + ' ---')
  $v14.Add('catalog_file=' + $record.catalog_file)
  $v14.Add('catalog_integrity_reference_file=' + $record.catalog_integrity_reference_file)
  $v14.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $v14.Add('computed_catalog_hash=' + $record.computed_catalog_hash)
  $v14.Add('catalog_integrity_result=' + $record.catalog_integrity_result)
  $v14.Add('catalog_load_result=' + $record.catalog_load_result)
  $v14.Add('chain_resolution_allowed=' + $record.chain_resolution_allowed)
  $v14.Add('version_selection_allowed=' + $record.version_selection_allowed)
  $v14.Add('fallback_occurred=' + $record.fallback_occurred)
  $v14.Add('')
}
$v14.Add('--- CASE A DEFAULT RESOLUTION ---')
$v14.Add('requested_chain_version=' + $defaultA.requested_chain_version)
$v14.Add('selected_chain_version=' + $defaultA.selected_chain_version)
$v14.Add('chain_resolution_allowed=' + $chainA.chain_resolution_allowed)
$v14.Add('fallback_occurred=' + $defaultA.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE E CATALOG / CHAIN MISMATCH ---')
$v14.Add('requested_chain_version=' + $defaultE.requested_chain_version)
$v14.Add('selected_chain_version=' + $defaultE.selected_chain_version)
$v14.Add('selected_chain_file=' + $defaultE.selected_chain_file_rel)
$v14.Add('selected_chain_integrity_reference_file=' + $defaultE.selected_integrity_file_rel)
$v14.Add('chain_resolution_allowed=' + $chainE.chain_resolution_allowed)
$v14.Add('failure_reason=' + $chainE.reason)
$v14.Add('fallback_occurred=' + $defaultE.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE F HISTORICAL CHAIN SELECTION STILL WORKS ---')
$v14.Add('requested_chain_version=v1')
$v14.Add('selected_chain_version=' + $selectV1.selected_chain_version)
$v14.Add('selected_chain_file=' + $selectV1.selected_chain_file_rel)
$v14.Add('chain_resolution_allowed=' + $chainFv1.chain_resolution_allowed)
$v14.Add('fallback_occurred=' + $selectV1.fallback_occurred)
$v14.Add('requested_chain_version=v2')
$v14.Add('selected_chain_version=' + $selectV2.selected_chain_version)
$v14.Add('selected_chain_file=' + $selectV2.selected_chain_file_rel)
$v14.Add('chain_resolution_allowed=' + $chainFv2.chain_resolution_allowed)
$v14.Add('fallback_occurred=' + $selectV2.fallback_occurred)
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
  'how_catalog_integrity_works=the_runner_hashes_tools/phase43_5/active_chain_version_catalog.json_and_compares_it_to_tools/phase43_6/active_chain_version_catalog_integrity_reference.json_before_allowing_any_selection_or_default_resolution'
  'how_default_resolution_is_enforced=default_chain_resolution_requires_a_verified_catalog_and_exactly_one_current_rotated_catalog_entry'
  'how_tamper_is_detected=any_catalog_byte_change_produces_catalog_hash_mismatch_and_blocks_version_selection_and_chain_resolution'
  'how_corruption_is_detected=corrupted_catalog_json_fails_load_after_hash_mismatch_and_blocks_resolution'
  'how_missing_catalog_is_detected=absent_catalog_file_returns_catalog_missing_and_blocks_resolution'
  'how_invalid_catalog_references_are_detected=a_catalog_can_pass_its_own_integrity_but_still_block_chain_resolution_when_the_referenced_chain_file_is_missing_or_mismatched'
  'how_historical_chain_selection_remains_usable=with_valid_catalog_v1_and_v2_can_still_be_selected_and_verified_explicitly'
  'how_no_fallback_is_proven=all_case_records_keep_fallback_occurred_false_and_failed_catalog_cases_do_not_resolve_to_another_chain_version'
  'why_disabled_remained_inert=the_phase_only_adds_runner_side_catalog_integrity_checks'
  'why_baseline_mode_remained_unchanged=the_phase_does_not_modify_runtime_behavior_ui_layout_or_baseline_assets'
) -Encoding UTF8

$rec16 = New-Object System.Collections.Generic.List[string]
foreach ($pair in @(
  [pscustomobject]@{catalog=$catalogA; selection=$defaultA},
  [pscustomobject]@{catalog=$catalogB; selection=$defaultB},
  [pscustomobject]@{catalog=$catalogC; selection=$defaultC},
  [pscustomobject]@{catalog=$catalogD; selection=$defaultD},
  [pscustomobject]@{catalog=$catalogE; selection=$defaultE},
  [pscustomobject]@{catalog=$catalogA; selection=$selectV1},
  [pscustomobject]@{catalog=$catalogA; selection=$selectV2}
)) {
  $rec16.Add('catalog_file=' + $pair.catalog.catalog_file)
  $rec16.Add('catalog_integrity_reference_file=' + $pair.catalog.catalog_integrity_reference_file)
  $rec16.Add('stored_catalog_hash=' + $pair.catalog.stored_catalog_hash)
  $rec16.Add('computed_catalog_hash=' + $pair.catalog.computed_catalog_hash)
  $rec16.Add('catalog_integrity_result=' + $pair.catalog.catalog_integrity_result)
  $rec16.Add('requested_chain_version=' + $pair.selection.requested_chain_version)
  $rec16.Add('selected_chain_version=' + $pair.selection.selected_chain_version)
  $rec16.Add('chain_resolution_allowed=' + $(if($pair.selection.pass -and ($pair.selection.PSObject.Properties['chain_resolution_allowed'])){$pair.selection.chain_resolution_allowed}else{'False'}))
  $rec16.Add('fallback_occurred=' + $pair.selection.fallback_occurred)
  $rec16.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_catalog_reference_record.txt') -Value $rec16 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '17_catalog_tamper_evidence.txt') -Value @(
  'failure_case_identifier=B_catalog_tamper_detection'
  ('catalog_file=' + $catalogB.catalog_file)
  ('catalog_integrity_reference_file=' + $catalogB.catalog_integrity_reference_file)
  'mismatch_introduced=chain_state_modified_in_catalog_without_integrity_reference_update'
  'expected_result=FAIL'
  ('actual_failure_result=' + $catalogB.reason)
  ('version_selection_blocked=' + (-not $catalogB.version_selection_allowed))
  ('chain_resolution_blocked=' + (-not $catalogB.chain_resolution_allowed))
  ('failure_is_correct_and_deterministic=' + $caseBPass)
  ''
  'failure_case_identifier=C_catalog_corruption'
  ('actual_failure_result=' + $catalogC.reason)
  ('chain_resolution_blocked=' + (-not $catalogC.chain_resolution_allowed))
  ''
  'failure_case_identifier=D_missing_catalog'
  ('actual_failure_result=' + $catalogD.reason)
  ('chain_resolution_blocked=' + (-not $catalogD.chain_resolution_allowed))
  ''
  'failure_case_identifier=E_catalog_chain_mismatch'
  ('actual_failure_result=' + $chainE.reason)
  ('chain_resolution_blocked=' + (-not $chainE.chain_resolution_allowed))
) -Encoding UTF8

$gateLines = @('PHASE=43.6', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) {
  foreach ($reason in $gateReasons) {
    $gateLines += ('FAIL_REASON=' + $reason)
  }
}
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_6.txt') -Value $gateLines -Encoding UTF8

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
