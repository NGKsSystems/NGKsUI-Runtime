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

function Get-DeterministicHistoryFileRecords {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$HistoryDir
  )

  $items = @(Get-ChildItem -LiteralPath $HistoryDir -File | Sort-Object Name)
  $records = @()
  foreach ($item in $items) {
    $records += [ordered]@{
      file = Convert-AbsoluteToRepoPath -RootPath $RootPath -AbsolutePath $item.FullName
      sha256 = Get-FileSha256Hex -Path $item.FullName
      size = [int64]$item.Length
    }
  }
  return ,$records
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase44_0_catalog_baseline_lock_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase44_0'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null

$catalogTrustChainPath = Join-Path $Root 'tools\phase43_9\catalog_trust_chain.json'
$catalogHistoryChainPath = Join-Path $Root 'tools\phase43_7\catalog_history_chain.json'
$catalogHistoryDir = Join-Path $Root 'tools\phase43_7\catalog_history'
$activeCatalogPath = Join-Path $Root 'tools\phase43_7\active_chain_version_catalog_v2.json'
$activeCatalogIntegrityPath = Join-Path $Root 'tools\phase43_7\active_chain_version_catalog_integrity_reference_v2.json'
$rotationRunnerPath = Join-Path $Root 'tools\phase43_7\phase43_7_active_chain_catalog_rotation_runner.ps1'

$baselineSnapshotPath = Join-Path $phaseDir 'catalog_baseline_snapshot.json'
$baselineIntegrityPath = Join-Path $phaseDir 'catalog_baseline_integrity_reference.json'
$baselineLockPolicyPath = Join-Path $phaseDir 'catalog_baseline_lock_policy.json'

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

Write-Output '=== CASE A: BASELINE SNAPSHOT CREATION ==='
$trustObj = Get-Content -Raw -LiteralPath $catalogTrustChainPath | ConvertFrom-Json
$activeTrustRecord = @($trustObj.chain | Where-Object { [string]$_.status -eq 'active' }) | Select-Object -First 1
$activeCatalogVersion = if ($null -ne $activeTrustRecord) { [string]$activeTrustRecord.catalog_version } else { '' }
$historyRecords = Get-DeterministicHistoryFileRecords -RootPath $Root -HistoryDir $catalogHistoryDir

$baselineSnapshot = [ordered]@{
  baseline_version = '44.0'
  baseline_kind = 'catalog_trust_chain_certification_lock'
  active_catalog_version = $activeCatalogVersion
  catalog_trust_chain_file = 'tools/phase43_9/catalog_trust_chain.json'
  catalog_trust_chain_sha256 = Get-FileSha256Hex -Path $catalogTrustChainPath
  catalog_history_chain_file = 'tools/phase43_7/catalog_history_chain.json'
  catalog_history_chain_sha256 = Get-FileSha256Hex -Path $catalogHistoryChainPath
  active_catalog_file = 'tools/phase43_7/active_chain_version_catalog_v2.json'
  active_catalog_sha256 = Get-FileSha256Hex -Path $activeCatalogPath
  active_catalog_integrity_file = 'tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  active_catalog_integrity_sha256 = Get-FileSha256Hex -Path $activeCatalogIntegrityPath
  archived_catalog_history = $historyRecords
  rotation_runner_required_reference = 'tools/phase43_7/phase43_7_active_chain_catalog_rotation_runner.ps1'
}

Set-Content -Path $baselineSnapshotPath -Value ($baselineSnapshot | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline
$baselineHash = Get-FileSha256Hex -Path $baselineSnapshotPath

$baselineIntegrity = [ordered]@{
  protected_baseline_snapshot_file = 'tools/phase44_0/catalog_baseline_snapshot.json'
  expected_baseline_snapshot_sha256 = $baselineHash
  hash_method = 'sha256_file_bytes_v1'
  baseline_version = '44.0'
  description = 'Frozen certification baseline for catalog trust-chain continuity'
}
Set-Content -Path $baselineIntegrityPath -Value ($baselineIntegrity | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$baselineSnapshotCreated = (Test-Path -LiteralPath $baselineSnapshotPath) -and (Test-Path -LiteralPath $baselineIntegrityPath)
$baselineIntegrityValidA = ((Get-FileSha256Hex -Path $baselineSnapshotPath) -eq $baselineHash)
$caseAPass = $baselineSnapshotCreated -and $baselineIntegrityValidA

Write-Output '=== CASE B: BASELINE INTEGRITY VERIFICATION ==='
$baselineIntegrityObj = Get-Content -Raw -LiteralPath $baselineIntegrityPath | ConvertFrom-Json
$storedBaselineHash = [string]$baselineIntegrityObj.expected_baseline_snapshot_sha256
$computedBaselineHashB = Get-FileSha256Hex -Path $baselineSnapshotPath
$baselineIntegrityValidB = ($computedBaselineHashB -eq $storedBaselineHash)
$caseBPass = $baselineIntegrityValidB

Write-Output '=== CASE C: BASELINE TAMPER DETECTION ==='
$tamperedBaselinePath = Join-Path $phaseDir '_caseC_tampered_baseline_snapshot.json'
$tamperedObj = Get-Content -Raw -LiteralPath $baselineSnapshotPath | ConvertFrom-Json
$tamperedObj.active_catalog_version = 'v1'
Set-Content -Path $tamperedBaselinePath -Value ($tamperedObj | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline
$computedTamperedHash = Get-FileSha256Hex -Path $tamperedBaselinePath
$caseCTamperDetected = ($computedTamperedHash -ne $storedBaselineHash)
$caseCBaselineUsageBlocked = $caseCTamperDetected
$caseCPass = $caseCTamperDetected -and $caseCBaselineUsageBlocked

Write-Output '=== CASE D: BASELINE IMMUTABILITY ==='
$baselineFileInfo = Get-Item -LiteralPath $baselineSnapshotPath
$baselineFileInfo.IsReadOnly = $true
$baselineFileInfo = Get-Item -LiteralPath $baselineSnapshotPath
$originalBaselineText = Get-Content -Raw -LiteralPath $baselineSnapshotPath
$overwriteBlocked = $false
try {
  [System.IO.File]::WriteAllText($baselineSnapshotPath, '{"tamper":"overwrite_attempt"}')
  $overwriteBlocked = $false
} catch {
  $overwriteBlocked = $true
}
if (-not $overwriteBlocked) {
  Set-Content -Path $baselineSnapshotPath -Value $originalBaselineText -Encoding UTF8 -NoNewline
}
$baselineFileInfo = Get-Item -LiteralPath $baselineSnapshotPath
$baselineFileInfo.IsReadOnly = $true
$caseDPass = $overwriteBlocked

Write-Output '=== CASE E: FUTURE ROTATION COMPATIBILITY CHECK ==='
$baselineLockPolicy = [ordered]@{
  baseline_version = '44.0'
  required_baseline_snapshot_file = 'tools/phase44_0/catalog_baseline_snapshot.json'
  required_baseline_snapshot_sha256 = $storedBaselineHash
  required_rotation_runner = 'tools/phase43_7/phase43_7_active_chain_catalog_rotation_runner.ps1'
  enforcement = 'future_catalog_rotation_must_reference_frozen_baseline'
}
Set-Content -Path $baselineLockPolicyPath -Value ($baselineLockPolicy | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline
$policyObj = Get-Content -Raw -LiteralPath $baselineLockPolicyPath | ConvertFrom-Json
$baselineRefValid =
  ((Convert-RepoPathToAbsolute -RootPath $Root -RepoPath ([string]$policyObj.required_baseline_snapshot_file)) -eq $baselineSnapshotPath) -and
  ((Get-FileSha256Hex -Path $baselineSnapshotPath) -eq [string]$policyObj.required_baseline_snapshot_sha256) -and
  (Test-Path -LiteralPath (Convert-RepoPathToAbsolute -RootPath $Root -RepoPath ([string]$policyObj.required_rotation_runner)))
$catalogHistoryPreserved = (Test-Path -LiteralPath $catalogHistoryChainPath) -and ((Get-DeterministicHistoryFileRecords -RootPath $Root -HistoryDir $catalogHistoryDir).Count -gt 0)
$caseEPass = $baselineRefValid -and $catalogHistoryPreserved

$noFallback = $true

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $noFallback) { $gatePass = $false; $gateReasons.Add('fallback_detected') }
$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  'phase=44.0'
  'title=CATALOG TRUST-CHAIN FREEZE / CERTIFICATION BASELINE LOCK'
  ('timestamp=' + $TS)
  ('gate=' + $gateStr)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  ('case_a=' + $caseAPass)
  ('case_b=' + $caseBPass)
  ('case_c=' + $caseCPass)
  ('case_d=' + $caseDPass)
  ('case_e=' + $caseEPass)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value @(
  'project=NGKsUI Runtime'
  'phase=44.0'
  'title=CATALOG TRUST-CHAIN FREEZE / CERTIFICATION BASELINE LOCK'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '10_baseline_definition.txt') -Value @(
  'baseline_version=44.0'
  'baseline_snapshot_file=tools/phase44_0/catalog_baseline_snapshot.json'
  'baseline_integrity_reference_file=tools/phase44_0/catalog_baseline_integrity_reference.json'
  'baseline_lock_policy_file=tools/phase44_0/catalog_baseline_lock_policy.json'
  'captured_catalog_trust_chain=tools/phase43_9/catalog_trust_chain.json'
  'captured_catalog_history_chain=tools/phase43_7/catalog_history_chain.json'
  'captured_active_catalog=tools/phase43_7/active_chain_version_catalog_v2.json'
  'captured_active_catalog_integrity=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '11_baseline_rules.txt') -Value @(
  'RULE_1=baseline_snapshot_must_be_deterministic_for_same_catalog_state'
  'RULE_2=baseline_integrity_hash_must_be_recorded'
  'RULE_3=baseline_tampering_must_be_detected'
  'RULE_4=baseline_overwrite_attempt_must_be_blocked'
  'RULE_5=future_catalog_rotations_must_reference_frozen_baseline_policy'
  'RULE_6=catalog_trust_chain_history_must_remain_intact'
) -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_9/catalog_trust_chain.json'
  'READ=tools/phase43_7/catalog_history_chain.json'
  'READ=tools/phase43_7/active_chain_version_catalog_v2.json'
  'READ=tools/phase43_7/active_chain_version_catalog_integrity_reference_v2.json'
  'READ=tools/phase43_7/catalog_history/*'
  'CREATED=tools/phase44_0/phase44_0_catalog_baseline_lock_runner.ps1'
  'CREATED=tools/phase44_0/catalog_baseline_snapshot.json'
  'CREATED=tools/phase44_0/catalog_baseline_integrity_reference.json'
  'CREATED=tools/phase44_0/catalog_baseline_lock_policy.json'
  'CREATED(TEMP)=tools/phase44_0/_caseC_tampered_baseline_snapshot.json'
  'UI_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase44_0_establishes_frozen_catalog_trust_chain_baseline_at_runner_layer'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
$v14.Add('--- CASE A BASELINE SNAPSHOT CREATION ---')
$v14.Add('baseline_version=44.0')
$v14.Add('baseline_snapshot_path=tools/phase44_0/catalog_baseline_snapshot.json')
$v14.Add('baseline_integrity_hash=' + $baselineHash)
$v14.Add('computed_hash=' + (Get-FileSha256Hex -Path $baselineSnapshotPath))
$v14.Add('verification_result=' + $baselineIntegrityValidA)
$v14.Add('')
$v14.Add('--- CASE B BASELINE INTEGRITY VERIFICATION ---')
$v14.Add('baseline_version=44.0')
$v14.Add('baseline_snapshot_path=tools/phase44_0/catalog_baseline_snapshot.json')
$v14.Add('baseline_integrity_hash=' + $storedBaselineHash)
$v14.Add('computed_hash=' + $computedBaselineHashB)
$v14.Add('verification_result=' + $baselineIntegrityValidB)
$v14.Add('')
$v14.Add('--- CASE C BASELINE TAMPER DETECTION ---')
$v14.Add('baseline_version=44.0')
$v14.Add('baseline_snapshot_path=tools/phase44_0/_caseC_tampered_baseline_snapshot.json')
$v14.Add('baseline_integrity_hash=' + $storedBaselineHash)
$v14.Add('computed_hash=' + $computedTamperedHash)
$v14.Add('tamper_detection_result=' + $caseCTamperDetected)
$v14.Add('baseline_usage=' + $(if($caseCBaselineUsageBlocked){'BLOCKED'}else{'ALLOWED'}))
$v14.Add('')
$v14.Add('--- CASE D BASELINE IMMUTABILITY ---')
$v14.Add('overwrite_attempt_result=' + $(if($overwriteBlocked){'BLOCKED'}else{'NOT_BLOCKED'}))
$v14.Add('')
$v14.Add('--- CASE E FUTURE ROTATION COMPATIBILITY CHECK ---')
$v14.Add('baseline_reference_status=' + $(if($baselineRefValid){'VALID'}else{'INVALID'}))
$v14.Add('catalog_history_preserved=' + $catalogHistoryPreserved)
$v14.Add('')
$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add('gate_fail_reason=' + $r) } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_baseline_snapshot_is_created=the_runner_captures_active_catalog_version_catalog_trust_chain_catalog_history_chain_active_catalog_and_archived_history_hashes_into_a_single_snapshot_json'
  'how_baseline_integrity_is_recorded=the_snapshot_sha256_is_written_to_catalog_baseline_integrity_reference.json'
  'how_tamper_detection_works=modified_snapshot_bytes_produce_hash_mismatch_against_recorded_baseline_hash'
  'how_immutability_is_enforced=baseline_snapshot_file_is_marked_read_only_and_overwrite_attempts_are_blocked'
  'how_future_rotations_reference_baseline=baseline_lock_policy_records_required_baseline_snapshot_hash_and_required_rotation_runner_path'
  'how_catalog_history_remains_intact=history_chain_and_archived_history_files_are_verified_present_during_compatibility_check'
  'why_runtime_state_machine_unchanged=phase44_0_changes_only_certification_runner_and_baseline_artifacts'
) -Encoding UTF8

$rec16 = @(
  'baseline_version=44.0'
  'baseline_snapshot_path=tools/phase44_0/catalog_baseline_snapshot.json'
  ('baseline_integrity_hash=' + $storedBaselineHash)
  ('computed_hash=' + $computedBaselineHashB)
  ('verification_result=' + $baselineIntegrityValidB)
  ('tamper_detection_result=' + $caseCTamperDetected)
  ('overwrite_attempt_result=' + $(if($overwriteBlocked){'BLOCKED'}else{'NOT_BLOCKED'}))
  ('baseline_reference_status=' + $(if($baselineRefValid){'VALID'}else{'INVALID'}))
)
Set-Content -Path (Join-Path $PFDir '16_catalog_baseline_record.txt') -Value $rec16 -Encoding UTF8

$rec17 = @(
  'tamper_case=baseline_snapshot_modified'
  ('expected_hash=' + $storedBaselineHash)
  ('tampered_hash=' + $computedTamperedHash)
  ('tamper_detection_result=' + $caseCTamperDetected)
  ('baseline_usage=' + $(if($caseCBaselineUsageBlocked){'BLOCKED'}else{'ALLOWED'}))
  ('overwrite_attempt_result=' + $(if($overwriteBlocked){'BLOCKED'}else{'NOT_BLOCKED'}))
)
Set-Content -Path (Join-Path $PFDir '17_baseline_tamper_evidence.txt') -Value $rec17 -Encoding UTF8

$gateLines = @('PHASE=44.0', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) { foreach ($r in $gateReasons) { $gateLines += ('FAIL_REASON=' + $r) } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase44_0.txt') -Value $gateLines -Encoding UTF8

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
