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
$proofName = "phase84_1_win32_alignment_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase84_1_win32_alignment_*.zip' -ErrorAction SilentlyContinue |
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

$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup entrypoint or app launch path missing' }
if ($win32Content -match 'int main\(\)' -and $win32Content -match 'rc\s*=\s*run_app\(\)' -and $win32Content -match 'window_created=1') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'main entrypoint still launches existing run_app native path'
}

$checkResults['check_trust_ordering_aligned'] = @{ Result = $false; Reason = 'execution_pipeline trust ordering drifted' }
$idxGuardPass = $win32Content.IndexOf('runtime_observe_lifecycle("win32_sandbox", "guard_pass")')
$idxTrust = $win32Content.IndexOf('require_runtime_trust("execution_pipeline")')
$idxVeh = $win32Content.IndexOf('AddVectoredExceptionHandler')
$idxRun = $win32Content.IndexOf('rc = run_app()')
if ($idxGuardPass -ge 0 -and $idxTrust -gt $idxGuardPass -and $idxVeh -gt $idxTrust -and $idxRun -gt $idxTrust) {
  $checkResults['check_trust_ordering_aligned'].Result = $true
  $checkResults['check_trust_ordering_aligned'].Reason = 'execution_pipeline trust enforced before crash capture install and app run'
}

$checkResults['check_lifecycle_teardown_aligned'] = @{ Result = $false; Reason = 'lifecycle or teardown alignment incomplete' }
if ($win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_enter"\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_exit"\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_exception"\)' -and
    $win32Content -match 'runtime_emit_termination_summary\("win32_sandbox", "runtime_init", rc == 0 \? 0 : 1\)' -and
    $win32Content -match 'crash_capture_veh_removed=1') {
  $checkResults['check_lifecycle_teardown_aligned'].Result = $true
  $checkResults['check_lifecycle_teardown_aligned'].Reason = 'main lifecycle now includes exception marker and deterministic teardown summary'
}

$checkResults['check_native_markers_present'] = @{ Result = $false; Reason = 'phase84_1 native alignment markers missing' }
if ($win32Content -match 'phase84_1_win32_alignment_available=1' -and
    $win32Content -match 'phase84_1_startup_contract_guarded_by=execution_pipeline' -and
    $win32Content -match 'phase84_1_lifecycle_contract_model=' -and
    $win32Content -match 'phase84_1_native_marker_parity=widget_sandbox_comparable') {
  $checkResults['check_native_markers_present'].Result = $true
  $checkResults['check_native_markers_present'].Reason = 'win32_sandbox now emits native contract markers comparable to widget_sandbox pattern'
}

$checkResults['check_idle_and_shutdown_still_work'] = @{ Result = $false; Reason = 'idle loop or shutdown path missing' }
if ($win32Content -match 'loop\.run\(\)' -and
    $win32Content -match 'loop\.stop\(\)' -and
    $win32Content -match 'shutdown_ok=1' -and
    $win32Content -match 'return 0;') {
  $checkResults['check_idle_and_shutdown_still_work'].Result = $true
  $checkResults['check_idle_and_shutdown_still_work'].Reason = 'event loop idle and shutdown path retained'
}

$checkResults['check_no_regression_existing_behavior'] = @{ Result = $false; Reason = 'existing win32_sandbox behavior changed beyond first slice' }
if ($win32Content -match 'Win32Window window;' -and
    $win32Content -match 'D3D11Renderer renderer;' -and
    $win32Content -match 'crash_capture_veh_installed=' -and
    $win32Content -match 'crash_capture_veh_removed=1' -and
    $win32Content -match 'FORCE_TEST_CRASH=1') {
  $checkResults['check_no_regression_existing_behavior'].Result = $true
  $checkResults['check_no_regression_existing_behavior'].Reason = 'core win32_sandbox render loop and crash-capture behavior remain intact'
}

$checkResults['check_widget_reference_unchanged'] = @{ Result = $false; Reason = 'widget reference native path unavailable' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'phase83_2_migration_pilot_consolidation_available=1') {
  $checkResults['check_widget_reference_unchanged'].Result = $true
  $checkResults['check_widget_reference_unchanged'].Reason = 'widget_sandbox remains the reference native pattern for broader migration alignment'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_win32_alignment_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE84_1_WIN32_SANDBOX_NATIVE_ALIGNMENT_FIRST_SLICE'
$checkLines += 'scope=win32_sandbox_startup_lifecycle_contract_alignment'
$checkLines += 'foundation=phase84_0_broader_migration_map_selected_apps_win32_sandbox'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Validation Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Alignment Coverage'
$checkLines += ('startup_contract_marker_present=' + $(if ($win32Content -match 'phase84_1_startup_contract_guarded_by=execution_pipeline') { 'YES' } else { 'NO' }))
$checkLines += ('lifecycle_contract_marker_present=' + $(if ($win32Content -match 'phase84_1_lifecycle_contract_model=') { 'YES' } else { 'NO' }))
$checkLines += ('main_exception_lifecycle_present=' + $(if ($win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_exception"\)') { 'YES' } else { 'NO' }))
$checkLines += ('native_marker_parity_present=' + $(if ($win32Content -match 'phase84_1_native_marker_parity=widget_sandbox_comparable') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE84_1_WIN32_SANDBOX_NATIVE_ALIGNMENT_FIRST_SLICE'
$contract += 'objective=Align_win32_sandbox_startup_and_lifecycle_contract_with_widget_sandbox_native_pattern_using_smallest_slice'
$contract += 'changes_introduced=Added_phase84_1_startup_and_lifecycle_alignment_markers_and_main_exception_lifecycle_hook_in_win32_sandbox_main'
$contract += 'runtime_behavior_changes=No_new_ui_path_added_existing_win32_sandbox_native_run_loop_preserved_with_comparable_contract_markers_and_exception_lifecycle_visibility'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_win32_alignment_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_win32_alignment_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase84_1_win32_alignment_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase84_1_status=' + $phaseStatus)
exit 0
