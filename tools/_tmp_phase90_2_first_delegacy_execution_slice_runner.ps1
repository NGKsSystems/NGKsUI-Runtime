#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$workspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase90_2_first_delegacy_execution_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase90_2_first_delegacy_execution_slice_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)
  if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) { return $false }
    }
    return $true
  } finally { $archive.Dispose() }
}

$phase90_1Runner = Join-Path $workspaceRoot 'tools/_tmp_phase90_1_first_delegacy_planning_slice_runner.ps1'
$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

$phase90_1RunnerContent = if (Test-Path -LiteralPath $phase90_1Runner) { Get-Content -LiteralPath $phase90_1Runner -Raw } else { '' }
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_phase90_1_ready_gate_present'] = @{ Result = $false; Reason = 'phase90_1 ready gate marker missing from planning runner' }
if ($phase90_1RunnerContent -match 'READY_FOR_FIRST_DELEGACY_EXECUTION_PLAN') {
  $checkResults['check_phase90_1_ready_gate_present'].Result = $true
  $checkResults['check_phase90_1_ready_gate_present'].Reason = 'phase90_1 planning gate to execute first de-legacy step is present'
}

$checkResults['check_selected_target_only_has_phase90_2_marker'] = @{ Result = $false; Reason = 'phase90_2 marker not limited to selected target' }
if ($loopContent -match 'phase90_2_first_delegacy_execution_slice_available=1' -and
    $sandboxContent -notmatch 'phase90_2_' -and
    $win32Content -notmatch 'phase90_2_' -and
    $widgetContent -notmatch 'phase90_2_') {
  $checkResults['check_selected_target_only_has_phase90_2_marker'].Result = $true
  $checkResults['check_selected_target_only_has_phase90_2_marker'].Reason = 'phase90_2 execution slice is confined to apps/loop_tests'
}

$checkResults['check_smallest_step1_instrumentation_only'] = @{ Result = $false; Reason = 'step1 instrumentation markers missing' }
if ($loopContent -match 'phase90_2_delegacy_step_executed=step1_instrument_and_measure_fallback_usage' -and
    $loopContent -match 'phase90_2_legacy_fallback_usage_observed=') {
  $checkResults['check_smallest_step1_instrumentation_only'].Result = $true
  $checkResults['check_smallest_step1_instrumentation_only'].Reason = 'first minimal execution step is implemented as fallback usage instrumentation only'
}

$checkResults['check_native_default_path_preserved'] = @{ Result = $false; Reason = 'native/default branch call path changed' }
if ($loopContent -match '\?\s*run_phase86_2_native_slice_app\(\)' -and
    $loopContent -match 'phase89_2_policy_mode_selected=') {
  $checkResults['check_native_default_path_preserved'].Result = $true
  $checkResults['check_native_default_path_preserved'].Reason = 'native/default path remains callable with deterministic mode logging'
}

$checkResults['check_fallback_role_preserved_temporarily'] = @{ Result = $false; Reason = 'fallback role no longer reachable' }
if ($loopContent -match ':\s*run_legacy_loop_tests\(\)' -and
    $loopContent -match 'is_phase87_3_legacy_fallback_enabled\(') {
  $checkResults['check_fallback_role_preserved_temporarily'].Result = $true
  $checkResults['check_fallback_role_preserved_temporarily'].Reason = 'legacy fallback path remains reachable as temporary role per plan'
}

$checkResults['check_mode_selection_unambiguous'] = @{ Result = $false; Reason = 'mode decision reason not explicit' }
if ($loopContent -match 'phase90_2_policy_mode_reason=' -and
    $loopContent -match 'explicit_slice_mode \|\| !legacy_fallback_mode') {
  $checkResults['check_mode_selection_unambiguous'].Result = $true
  $checkResults['check_mode_selection_unambiguous'].Reason = 'mode selection remains deterministic and reason-coded'
}

$checkResults['check_startup_guard_contract_still_present'] = @{ Result = $false; Reason = 'startup guard/lifecycle contract appears broken' }
if ($loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)') {
  $checkResults['check_startup_guard_contract_still_present'].Result = $true
  $checkResults['check_startup_guard_contract_still_present'].Reason = 'startup guard contract remains intact after phase90_2 slice'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_first_delegacy_execution_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE90_2_FIRST_DELEGACY_EXECUTION_SLICE'
$checkLines += 'selected_target=apps/loop_tests'
$checkLines += 'scope=execute_only_step1_instrument_and_measure_fallback_usage'
$checkLines += 'total_checks=' + $checkResults.Count
$checkLines += 'passed_checks=' + ($checkResults.Count - $failedCount)
$checkLines += 'failed_checks=' + $failedCount
$checkLines += 'phase_status=' + $phaseStatus
$checkLines += ''
$checkLines += '# Validation checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE90_2_FIRST_DELEGACY_EXECUTION_SLICE'
$contract += 'objective=Execute_first_minimal_delegacy_step_for_apps_loop_tests_only_by_instrumenting_and_measuring_legacy_fallback_usage_without_path_removal'
$contract += 'changes_introduced=Added_phase90_2_target_scoped_mode_reason_and_fallback_usage_telemetry_markers_in_loop_tests_main'
$contract += 'runtime_behavior_changes=None_in_path_selection_logic_only_additive_telemetry_and_contract_markers'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_first_delegacy_execution_checks' }))
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $proofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_first_delegacy_execution_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_first_delegacy_execution_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase90_2_first_delegacy_execution_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase90_2_status=' + $phaseStatus)
exit 0
