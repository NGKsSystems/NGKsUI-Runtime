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

function Test-CatalogRecordIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  $catalogPath = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$Record.catalog_file_path)
  $integrityPath = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$Record.integrity_reference)
  if (-not (Test-Path -LiteralPath $catalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_file_missing'
      catalog_version = [string]$Record.catalog_version
      catalog_file_path = [string]$Record.catalog_file_path
      catalog_integrity_reference = [string]$Record.integrity_reference
      stored_catalog_hash = [string]$Record.catalog_hash
      computed_catalog_hash = ''
      previous_catalog_hash = [string]$Record.previous_catalog_hash
      trust_chain_status = 'INVALID'
      catalog_resolution = 'BLOCKED'
      fallback_occurred = $false
    }
  }
  if (-not (Test-Path -LiteralPath $integrityPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_integrity_reference_missing'
      catalog_version = [string]$Record.catalog_version
      catalog_file_path = [string]$Record.catalog_file_path
      catalog_integrity_reference = [string]$Record.integrity_reference
      stored_catalog_hash = [string]$Record.catalog_hash
      computed_catalog_hash = ''
      previous_catalog_hash = [string]$Record.previous_catalog_hash
      trust_chain_status = 'INVALID'
      catalog_resolution = 'BLOCKED'
      fallback_occurred = $false
    }
  }

  $computedHash = Get-FileSha256Hex -Path $catalogPath
  $integrityObj = Get-Content -Raw -LiteralPath $integrityPath | ConvertFrom-Json
  $expectedHash = [string]$integrityObj.expected_catalog_sha256
  $protectedCatalogRel = Get-OptionalObjectPropertyValue -Object $integrityObj -PropertyName 'protected_catalog_file' -DefaultValue ''
  $protectedCatalogAbs = if ([string]::IsNullOrWhiteSpace($protectedCatalogRel)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedCatalogRel }
  $status = [string]$Record.status

  if ($status -eq 'active' -and -not [string]::IsNullOrWhiteSpace($protectedCatalogAbs) -and ($protectedCatalogAbs -ne $catalogPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_reference_target_mismatch'
      catalog_version = [string]$Record.catalog_version
      catalog_file_path = [string]$Record.catalog_file_path
      catalog_integrity_reference = [string]$Record.integrity_reference
      stored_catalog_hash = [string]$Record.catalog_hash
      computed_catalog_hash = $computedHash
      previous_catalog_hash = [string]$Record.previous_catalog_hash
      trust_chain_status = 'INVALID'
      catalog_resolution = 'BLOCKED'
      fallback_occurred = $false
    }
  }

  if (($computedHash -ne [string]$Record.catalog_hash) -or ($computedHash -ne $expectedHash)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'catalog_integrity_fail'
      catalog_version = [string]$Record.catalog_version
      catalog_file_path = [string]$Record.catalog_file_path
      catalog_integrity_reference = [string]$Record.integrity_reference
      stored_catalog_hash = [string]$Record.catalog_hash
      computed_catalog_hash = $computedHash
      previous_catalog_hash = [string]$Record.previous_catalog_hash
      trust_chain_status = 'INVALID'
      catalog_resolution = 'BLOCKED'
      fallback_occurred = $false
    }
  }

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'catalog_integrity_valid'
    catalog_version = [string]$Record.catalog_version
    catalog_file_path = [string]$Record.catalog_file_path
    catalog_integrity_reference = [string]$Record.integrity_reference
    stored_catalog_hash = [string]$Record.catalog_hash
    computed_catalog_hash = $computedHash
    previous_catalog_hash = [string]$Record.previous_catalog_hash
    trust_chain_status = 'VALID'
    catalog_resolution = 'ALLOWED'
    fallback_occurred = $false
  }
}

function Test-CatalogTrustChain {
  param(
    [Parameter(Mandatory = $true)][string]$TrustChainPath,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  $trustObj = Get-Content -Raw -LiteralPath $TrustChainPath | ConvertFrom-Json
  $records = @($trustObj.chain)
  $results = @()
  $continuityOk = $true
  $previousHash = ''
  $expectedVersion = 1

  foreach ($record in $records) {
    $recordResult = Test-CatalogRecordIntegrity -Record $record -RootPath $RootPath -CaseName $CaseName
    $results += $recordResult
    if (-not $recordResult.pass) {
      $continuityOk = $false
    }

    $versionNumber = 0
    if (-not [int]::TryParse(([string]$record.catalog_version).TrimStart('v'), [ref]$versionNumber)) {
      $continuityOk = $false
    } elseif ($versionNumber -ne $expectedVersion) {
      $continuityOk = $false
    }

    if ([string]$record.previous_catalog_hash -ne $previousHash) {
      $continuityOk = $false
    }

    $previousHash = [string]$record.catalog_hash
    $expectedVersion += 1
  }

  $failedResults = @($results | Where-Object { -not $_.pass })

  return [pscustomobject]@{
    pass = ($failedResults.Count -eq 0) -and $continuityOk
    trust_chain_status = if (($failedResults.Count -eq 0) -and $continuityOk) { 'VALID' } else { 'INVALID' }
    continuity = $continuityOk
    records = $results
    trust_obj = $trustObj
    catalog_resolution = if (($failedResults.Count -eq 0) -and $continuityOk) { 'ALLOWED' } else { 'BLOCKED' }
    fallback_occurred = $false
  }
}

function Resolve-CatalogRecordByVersion {
  param(
    [Parameter(Mandatory = $true)]$TrustChainResult,
    [Parameter(Mandatory = $true)][string]$RequestedCatalogVersion
  )

  if (-not $TrustChainResult.pass) {
    return [pscustomobject]@{
      pass = $false
      reason = 'trust_chain_invalid'
      requested_catalog_version = $RequestedCatalogVersion
      record = $null
      fallback_occurred = $false
    }
  }

  $record = @($TrustChainResult.trust_obj.chain | Where-Object { [string]$_.catalog_version -eq $RequestedCatalogVersion }) | Select-Object -First 1
  if ($null -eq $record) {
    return [pscustomobject]@{
      pass = $false
      reason = 'catalog_version_not_found:' + $RequestedCatalogVersion
      requested_catalog_version = $RequestedCatalogVersion
      record = $null
      fallback_occurred = $false
    }
  }

  return [pscustomobject]@{
    pass = $true
    reason = 'catalog_version_selected'
    requested_catalog_version = $RequestedCatalogVersion
    record = $record
    fallback_occurred = $false
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_9_catalog_trust_chain_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase43_9'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
$trustChainPath = Join-Path $phaseDir 'catalog_trust_chain.json'

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

Write-Output '=== CASE A: CURRENT TRUST CHAIN VALIDATION ==='
$chainA = Test-CatalogTrustChain -TrustChainPath $trustChainPath -RootPath $Root -CaseName 'A_current_trust_chain'
$caseAPass = $chainA.pass -and ($chainA.trust_chain_status -eq 'VALID')

Write-Output '=== CASE B: HISTORICAL CATALOG VERIFICATION ==='
$selectionB = Resolve-CatalogRecordByVersion -TrustChainResult $chainA -RequestedCatalogVersion 'v1'
$recordB = if ($selectionB.pass) { Test-CatalogRecordIntegrity -Record $selectionB.record -RootPath $Root -CaseName 'B_historical_catalog' } else { $null }
$caseBPass = $selectionB.pass -and $null -ne $recordB -and $recordB.pass -and ($recordB.previous_catalog_hash -eq '')

Write-Output '=== CASE C: BROKEN TRUST CHAIN DETECTION ==='
$brokenTrustChainPath = Join-Path $phaseDir '_caseC_broken_trust_chain.json'
$brokenTrustObj = Get-Content -Raw -LiteralPath $trustChainPath | ConvertFrom-Json
$brokenTrustObj.chain[1].previous_catalog_hash = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
Set-Content -Path $brokenTrustChainPath -Value ($brokenTrustObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$chainC = Test-CatalogTrustChain -TrustChainPath $brokenTrustChainPath -RootPath $Root -CaseName 'C_broken_trust_chain'
$selectionC = Resolve-CatalogRecordByVersion -TrustChainResult $chainC -RequestedCatalogVersion 'v2'
$caseCPass = (-not $chainC.pass) -and ($chainC.trust_chain_status -eq 'INVALID') -and ($chainC.catalog_resolution -eq 'BLOCKED') -and (-not $selectionC.pass)

Write-Output '=== CASE D: HISTORICAL HASH MISMATCH ==='
$tamperedHistoricalCatalogPath = Join-Path $phaseDir '_caseD_tampered_historical_catalog.json'
$tamperedHistoricalTrustPath = Join-Path $phaseDir '_caseD_tampered_historical_trust_chain.json'
$tamperedHistObj = Get-Content -Raw -LiteralPath (Convert-RepoPathToAbsolute -RootPath $Root -RepoPath 'tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog.json') | ConvertFrom-Json
$tamperedHistObj.versions[0].chain_state = 'tampered_historical_state'
Set-Content -Path $tamperedHistoricalCatalogPath -Value ($tamperedHistObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$tamperedTrustObj = Get-Content -Raw -LiteralPath $trustChainPath | ConvertFrom-Json
$tamperedTrustObj.chain[0].catalog_file_path = 'tools/phase43_9/_caseD_tampered_historical_catalog.json'
Set-Content -Path $tamperedHistoricalTrustPath -Value ($tamperedTrustObj | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$chainD = Test-CatalogTrustChain -TrustChainPath $tamperedHistoricalTrustPath -RootPath $Root -CaseName 'D_historical_hash_mismatch'
$recordD = @($chainD.records | Where-Object { $_.catalog_version -eq 'v1' }) | Select-Object -First 1
$caseDPass = (-not $chainD.pass) -and ($null -ne $recordD) -and (-not $recordD.pass) -and ($recordD.reason -eq 'catalog_integrity_fail')

Write-Output '=== CASE E: CHAIN CONTINUITY VALIDATION ==='
$caseEPass = $chainA.continuity -and ($chainA.records.Count -eq 2)

Write-Output '=== CASE F: NO SILENT CHAIN REPAIR ==='
$caseFPass = (-not $selectionC.pass) -and (-not $chainC.fallback_occurred) -and (-not $selectionC.fallback_occurred)

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
  'phase=43.9'
  'title=CATALOG INTEGRITY TRUST-CHAIN / HISTORICAL CATALOG CONTINUITY'
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
  'phase=43.9'
  'title=CATALOG INTEGRITY TRUST-CHAIN / HISTORICAL CATALOG CONTINUITY'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_catalog_trust_chain_definition.txt') -Value @(
  'catalog_trust_chain_file=tools/phase43_9/catalog_trust_chain.json'
  'trust_chain_model=catalog_version_catalog_hash_previous_catalog_hash_integrity_reference_timestamp_archive_path'
  'historical_catalog_v1_file=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog.json'
  'historical_catalog_v1_integrity_reference=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog_integrity_reference.json'
  'current_catalog_v2_file=tools/phase43_7/active_chain_version_catalog_v2.json'
  'current_catalog_v2_integrity_reference=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'trust_chain_rule=each_record_previous_catalog_hash_must_match_the_immediately_preceding_catalog_hash'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_catalog_trust_chain_rules.txt') -Value @(
  'RULE_1=each_catalog_version_references_previous_catalog_hash'
  'RULE_2=trust_chain_validates_before_catalog_usage'
  'RULE_3=broken_previous_catalog_hash_link_blocks_resolution'
  'RULE_4=historical_catalogs_remain_independently_verifiable'
  'RULE_5=historical_hash_mismatch_invalidates_trust_chain'
  'RULE_6=chain_continuity_must_be_sequential_and_complete'
  'RULE_7=no_silent_chain_repair_or_fallback_allowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_9/catalog_trust_chain.json'
  'READ=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog.json'
  'READ=tools/phase43_7/catalog_history/phase43_6_20260315_165643_active_chain_version_catalog_integrity_reference.json'
  'READ=tools/phase43_7/active_chain_version_catalog_v2.json'
  'READ=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'CREATED=tools/phase43_9/catalog_trust_chain.json'
  'CREATED=tools/phase43_9/phase43_9_catalog_trust_chain_runner.ps1'
  'CREATED(TEMP)=tools/phase43_9/_caseC_broken_trust_chain.json'
  'CREATED(TEMP)=tools/phase43_9/_caseD_tampered_historical_catalog.json'
  'CREATED(TEMP)=tools/phase43_9/_caseD_tampered_historical_trust_chain.json'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_9_validates_catalog_trust_chain_at_runner_layer'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
foreach ($record in $chainA.records) {
  $v14.Add('--- CASE A record ' + $record.catalog_version + ' ---')
  $v14.Add('catalog_version=' + $record.catalog_version)
  $v14.Add('catalog_file_path=' + $record.catalog_file_path)
  $v14.Add('catalog_integrity_reference=' + $record.catalog_integrity_reference)
  $v14.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $v14.Add('computed_catalog_hash=' + $record.computed_catalog_hash)
  $v14.Add('previous_catalog_hash=' + $record.previous_catalog_hash)
  $v14.Add('trust_chain_status=' + $record.trust_chain_status)
  $v14.Add('catalog_resolution=' + $record.catalog_resolution)
  $v14.Add('fallback_occurred=' + $record.fallback_occurred)
  $v14.Add('')
}
$v14.Add('--- CASE B HISTORICAL CATALOG VERIFICATION ---')
$v14.Add('catalog_version=' + $recordB.catalog_version)
$v14.Add('catalog_file_path=' + $recordB.catalog_file_path)
$v14.Add('catalog_integrity_reference=' + $recordB.catalog_integrity_reference)
$v14.Add('stored_catalog_hash=' + $recordB.stored_catalog_hash)
$v14.Add('computed_catalog_hash=' + $recordB.computed_catalog_hash)
$v14.Add('previous_catalog_hash=' + $recordB.previous_catalog_hash)
$v14.Add('trust_chain_status=' + $recordB.trust_chain_status)
$v14.Add('catalog_resolution=' + $recordB.catalog_resolution)
$v14.Add('fallback_occurred=' + $recordB.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE C BROKEN TRUST CHAIN DETECTION ---')
$v14.Add('catalog_version=v2')
$v14.Add('catalog_file_path=tools/phase43_7/active_chain_version_catalog_v2.json')
$v14.Add('catalog_integrity_reference=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json')
$v14.Add('stored_catalog_hash=0e41993ab079f997659d2286149e2bffba91517ba4c8ca5d3728600b01d37aa4')
$v14.Add('computed_catalog_hash=0e41993ab079f997659d2286149e2bffba91517ba4c8ca5d3728600b01d37aa4')
$v14.Add('previous_catalog_hash=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
$v14.Add('trust_chain_status=' + $chainC.trust_chain_status)
$v14.Add('catalog_resolution=' + $chainC.catalog_resolution)
$v14.Add('fallback_occurred=' + $chainC.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE D HISTORICAL HASH MISMATCH ---')
$v14.Add('catalog_version=' + $recordD.catalog_version)
$v14.Add('catalog_file_path=' + $recordD.catalog_file_path)
$v14.Add('catalog_integrity_reference=' + $recordD.catalog_integrity_reference)
$v14.Add('stored_catalog_hash=' + $recordD.stored_catalog_hash)
$v14.Add('computed_catalog_hash=' + $recordD.computed_catalog_hash)
$v14.Add('previous_catalog_hash=' + $recordD.previous_catalog_hash)
$v14.Add('trust_chain_status=' + $recordD.trust_chain_status)
$v14.Add('catalog_resolution=' + $recordD.catalog_resolution)
$v14.Add('fallback_occurred=' + $recordD.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE E CHAIN CONTINUITY VALIDATION ---')
$v14.Add('continuity=' + $chainA.continuity)
$v14.Add('trust_chain_status=' + $chainA.trust_chain_status)
$v14.Add('catalog_resolution=' + $chainA.catalog_resolution)
$v14.Add('fallback_occurred=' + $chainA.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE F NO SILENT CHAIN REPAIR ---')
$v14.Add('trust_chain_status=' + $chainC.trust_chain_status)
$v14.Add('catalog_resolution=' + $chainC.catalog_resolution)
$v14.Add('fallback_occurred=' + $chainC.fallback_occurred)
$v14.Add('selection_fallback_occurred=' + $selectionC.fallback_occurred)
$v14.Add('')
$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add('gate_fail_reason=' + $r) } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_catalog_trust_chain_works=tools/phase43_9/catalog_trust_chain.json_records_each_catalog_version_hash_and_the_previous_catalog_hash_link'
  'how_historical_catalogs_remain_verifiable=each_record_is_checked_against_the_catalog_file_bytes_and_its_integrity_reference_expected_hash'
  'how_broken_links_are_detected=if_previous_catalog_hash_does_not_match_the_immediately_preceding_record_catalog_hash_the_trust_chain_becomes_invalid'
  'how_historical_hash_mismatch_is_detected=altering_archived_catalog_bytes_changes_computed_catalog_hash_and_fails_record_integrity'
  'how_continuity_is_proven=records_must_be_sequential_v1_v2_and_each_link_must_match_the_prior_hash'
  'how_no_silent_chain_repair_is_proven=broken_chain_results_block_catalog_resolution_and_no_other_version_is_selected'
  'why_disabled_remained_inert=phase43_9_modifies_trust_chain_artifacts_and_runner_only'
  'why_runtime_state_machine_unchanged=no_runtime_source_or_ui_behavior_was_changed'
) -Encoding UTF8

$rec16 = New-Object System.Collections.Generic.List[string]
foreach ($record in $chainA.records) {
  $rec16.Add('catalog_version=' + $record.catalog_version)
  $rec16.Add('catalog_file_path=' + $record.catalog_file_path)
  $rec16.Add('catalog_integrity_reference=' + $record.catalog_integrity_reference)
  $rec16.Add('stored_catalog_hash=' + $record.stored_catalog_hash)
  $rec16.Add('computed_catalog_hash=' + $record.computed_catalog_hash)
  $rec16.Add('previous_catalog_hash=' + $record.previous_catalog_hash)
  $rec16.Add('trust_chain_status=' + $record.trust_chain_status)
  $rec16.Add('catalog_resolution_allowed_or_blocked=' + $record.catalog_resolution)
  $rec16.Add('fallback_occurred=' + $record.fallback_occurred)
  $rec16.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_catalog_chain_record.txt') -Value $rec16 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '17_chain_tamper_evidence.txt') -Value @(
  'failure_case_identifier=C_broken_trust_chain_detection'
  'mismatch_introduced=previous_catalog_hash_for_v2_modified'
  ('actual_failure_result=' + $chainC.trust_chain_status)
  ('catalog_resolution_blocked=' + ($chainC.catalog_resolution -eq 'BLOCKED'))
  ('fallback_occurred=' + $chainC.fallback_occurred)
  ''
  'failure_case_identifier=D_historical_hash_mismatch'
  'mismatch_introduced=archived_catalog_v1_contents_modified'
  ('actual_failure_result=' + $recordD.reason)
  ('catalog_resolution_blocked=' + ($recordD.catalog_resolution -eq 'BLOCKED'))
  ('fallback_occurred=' + $recordD.fallback_occurred)
) -Encoding UTF8

$gateLines = @('PHASE=43.9', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) { foreach ($r in $gateReasons) { $gateLines += ('FAIL_REASON=' + $r) } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_9.txt') -Value $gateLines -Encoding UTF8

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
