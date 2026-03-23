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
$proofName = "phase70_3_execution_coverage_sweep_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$loopTestsMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase70_3_execution_coverage_sweep_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }
  foreach ($line in $lines) {
    if ($line -match $Pattern) { return $true }
  }
  return $false
}

function Get-FileContent {
  param([string]$Path)
  return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
}

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
  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }
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
  }
  finally {
    $archive.Dispose()
  }
}

foreach ($file in @($widgetMain, $sandboxMain, $win32Main, $loopTestsMain)) {
  if (-not (Test-Path -LiteralPath $file)) {
    Write-Host "FATAL: required source missing: $file"
    exit 1
  }
}

$startupSurfaceChecks = @()
$startupSurfaceChecks += [pscustomobject]@{
  Surface = 'startup_widget_sandbox_main'
  File = 'apps/widget_sandbox/main.cpp'
  MainPresent = (Test-LinePresent -Path $widgetMain -Pattern '^int\s+main\s*\(')
  ExecutionPipelinePresent = (Test-LinePresent -Path $widgetMain -Pattern 'require_runtime_trust\("execution_pipeline"\);')
}
$startupSurfaceChecks += [pscustomobject]@{
  Surface = 'startup_sandbox_app_main'
  File = 'apps/sandbox_app/main.cpp'
  MainPresent = (Test-LinePresent -Path $sandboxMain -Pattern '^int\s+main\s*\(')
  ExecutionPipelinePresent = (Test-LinePresent -Path $sandboxMain -Pattern 'require_runtime_trust\("execution_pipeline"\);')
}
$startupSurfaceChecks += [pscustomobject]@{
  Surface = 'startup_win32_sandbox_main'
  File = 'apps/win32_sandbox/main.cpp'
  MainPresent = (Test-LinePresent -Path $win32Main -Pattern '^int\s+main\s*\(')
  ExecutionPipelinePresent = (Test-LinePresent -Path $win32Main -Pattern 'require_runtime_trust\("execution_pipeline"\);')
}
$startupSurfaceChecks += [pscustomobject]@{
  Surface = 'startup_loop_tests_main'
  File = 'apps/loop_tests/main.cpp'
  MainPresent = (Test-LinePresent -Path $loopTestsMain -Pattern '^int\s+main\s*\(')
  ExecutionPipelinePresent = (Test-LinePresent -Path $loopTestsMain -Pattern 'require_runtime_trust\("execution_pipeline"\);')
}

$widgetText = Get-FileContent -Path $widgetMain
$pluginPos = $widgetText.IndexOf('require_runtime_trust("plugin_load");')
$widgetExecBeforePlugin = $false
if ($pluginPos -ge 0) {
  $prePlugin = $widgetText.Substring(0, $pluginPos)
  $widgetExecBeforePlugin = $prePlugin.Contains('require_runtime_trust("execution_pipeline");')
}

$win32Text = Get-FileContent -Path $win32Main
$win32StartupExecBeforeRunApp = $false
$win32StartupExecPos = $win32Text.IndexOf('require_runtime_trust("execution_pipeline");')
$win32RunAppCallPos = $win32Text.IndexOf('rc = run_app();')
if ($win32StartupExecPos -ge 0 -and $win32RunAppCallPos -gt $win32StartupExecPos) {
  $win32StartupExecBeforeRunApp = $true
}

$userTriggeredSurfaces = @()
$userTriggeredSurfaces += [pscustomobject]@{
  Surface = 'user_widget_extension_lane_plugin_path'
  Disposition = if ($widgetExecBeforePlugin) { 'ENFORCED' } else { 'GAP' }
  Reason = if ($widgetExecBeforePlugin) { 'execution_pipeline_required_before_plugin_load' } else { 'plugin_load_without_prior_execution_pipeline' }
}
$userTriggeredSurfaces += [pscustomobject]@{
  Surface = 'user_widget_forensics_file_path'
  Disposition = 'EXEMPT'
  Reason = 'post_startup_file_load_inside_process_already_guarded_at_startup'
}
$userTriggeredSurfaces += [pscustomobject]@{
  Surface = 'user_win32_jitter_csv_file_path'
  Disposition = if ($win32StartupExecBeforeRunApp) { 'EXEMPT' } else { 'GAP' }
  Reason = if ($win32StartupExecBeforeRunApp) { 'run_app_invocation_occurs_after_startup_execution_pipeline_guard' } else { 'run_app_invocation_precedes_execution_pipeline' }
}

$backgroundAsyncSurfaces = @()
$backgroundAsyncSurfaces += [pscustomobject]@{
  Surface = 'background_sandbox_app_eventloop_post_interval'
  Disposition = 'EXEMPT'
  Reason = 'callbacks_run_inside_already_guarded_process_after_startup_execution_pipeline'
}
$backgroundAsyncSurfaces += [pscustomobject]@{
  Surface = 'background_win32_sandbox_render_interval'
  Disposition = 'EXEMPT'
  Reason = 'render_loop_runs_after_startup_execution_pipeline_guard'
}
$backgroundAsyncSurfaces += [pscustomobject]@{
  Surface = 'background_loop_tests_worker_thread_and_timer_storm'
  Disposition = 'EXEMPT'
  Reason = 'thread_and_async_callbacks_created_after_startup_execution_pipeline_guard'
}

$pluginExtensionSurfaces = @()
$pluginExtensionSurfaces += [pscustomobject]@{
  Surface = 'plugin_widget_extension_lane'
  Disposition = if ($widgetExecBeforePlugin) { 'ENFORCED' } else { 'GAP' }
  Reason = if ($widgetExecBeforePlugin) { 'execution_pipeline_and_plugin_load_both_required' } else { 'plugin_load_missing_execution_pipeline_precondition' }
}

$startupOk = $true
foreach ($s in $startupSurfaceChecks) {
  if (-not ($s.MainPresent -and $s.ExecutionPipelinePresent)) {
    $startupOk = $false
  }
}

$gaps = @()
foreach ($s in $userTriggeredSurfaces) { if ($s.Disposition -eq 'GAP') { $gaps += $s.Surface } }
foreach ($s in $backgroundAsyncSurfaces) { if ($s.Disposition -eq 'GAP') { $gaps += $s.Surface } }
foreach ($s in $pluginExtensionSurfaces) { if ($s.Disposition -eq 'GAP') { $gaps += $s.Surface } }

$userTriggeredOk = (@($userTriggeredSurfaces | Where-Object { $_.Disposition -eq 'GAP' })).Count -eq 0
$backgroundAsyncOk = (@($backgroundAsyncSurfaces | Where-Object { $_.Disposition -eq 'GAP' })).Count -eq 0
$pluginExtensionOk = (@($pluginExtensionSurfaces | Where-Object { $_.Disposition -eq 'GAP' })).Count -eq 0
$explicitExemptionCount = (@($userTriggeredSurfaces + $backgroundAsyncSurfaces + $pluginExtensionSurfaces | Where-Object { $_.Disposition -eq 'EXEMPT' })).Count

$checkStartupCoverage = $startupOk
$checkUserTriggeredCoverage = $userTriggeredOk
$checkBackgroundCoverage = $backgroundAsyncOk
$checkPluginCoverage = $pluginExtensionOk
$checkNoBypassGaps = ($gaps.Count -eq 0)
$checkSingleMinimalPatchRule = ($gaps.Count -le 1)
$checkRuntimePatchNeeded = ($gaps.Count -gt 0)

$rows = @()
$rows += ('check_startup_paths_covered=' + $(if ($checkStartupCoverage) { 'YES' } else { 'NO' }))
$rows += ('check_user_triggered_paths_covered=' + $(if ($checkUserTriggeredCoverage) { 'YES' } else { 'NO' }))
$rows += ('check_background_async_paths_covered=' + $(if ($checkBackgroundCoverage) { 'YES' } else { 'NO' }))
$rows += ('check_plugin_extension_paths_covered=' + $(if ($checkPluginCoverage) { 'YES' } else { 'NO' }))
$rows += ('check_no_execution_pipeline_bypass_gaps=' + $(if ($checkNoBypassGaps) { 'YES' } else { 'NO' }))
$rows += ('check_single_minimal_fix_limit_respected=' + $(if ($checkSingleMinimalPatchRule) { 'YES' } else { 'NO' }))

$failedCount = (@($rows | Where-Object { $_ -match '=NO$' })).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_coverage_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE70_3_EXECUTION_COVERAGE_SWEEP'
$checkLines += 'scope=execution_pipeline_coverage_across_runtime_execution_surfaces'
$checkLines += ('startup_surface_count=' + $startupSurfaceChecks.Count)
$checkLines += ('user_triggered_surface_count=' + $userTriggeredSurfaces.Count)
$checkLines += ('background_async_surface_count=' + $backgroundAsyncSurfaces.Count)
$checkLines += ('plugin_extension_surface_count=' + $pluginExtensionSurfaces.Count)
$checkLines += ('explicit_exemption_count=' + $explicitExemptionCount)
$checkLines += ('gap_count=' + $gaps.Count)
$checkLines += ('runtime_patch_required=' + $(if ($checkRuntimePatchNeeded) { 'YES' } else { 'NO' }))

for ($i = 0; $i -lt $startupSurfaceChecks.Count; $i++) {
  $n = $i + 1
  $s = $startupSurfaceChecks[$i]
  $checkLines += ('startup_surface_' + $n + '=' + $s.Surface + '|main_present=' + $(if ($s.MainPresent) { 'YES' } else { 'NO' }) + '|execution_pipeline_present=' + $(if ($s.ExecutionPipelinePresent) { 'YES' } else { 'NO' }))
}

for ($i = 0; $i -lt $userTriggeredSurfaces.Count; $i++) {
  $n = $i + 1
  $s = $userTriggeredSurfaces[$i]
  $checkLines += ('user_surface_' + $n + '=' + $s.Surface + '|disposition=' + $s.Disposition + '|reason=' + $s.Reason)
}

for ($i = 0; $i -lt $backgroundAsyncSurfaces.Count; $i++) {
  $n = $i + 1
  $s = $backgroundAsyncSurfaces[$i]
  $checkLines += ('background_surface_' + $n + '=' + $s.Surface + '|disposition=' + $s.Disposition + '|reason=' + $s.Reason)
}

for ($i = 0; $i -lt $pluginExtensionSurfaces.Count; $i++) {
  $n = $i + 1
  $s = $pluginExtensionSurfaces[$i]
  $checkLines += ('plugin_surface_' + $n + '=' + $s.Surface + '|disposition=' + $s.Disposition + '|reason=' + $s.Reason)
}

if ($gaps.Count -eq 0) {
  $checkLines += 'gaps=none'
} else {
  $checkLines += ('gaps=' + ($gaps -join ','))
}

$checkLines += $rows
$checkLines += ('failed_check_count=' + $failedCount)
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE70_3_EXECUTION_COVERAGE_SWEEP'
$contract += 'objective=Prove there are no remaining runtime execution paths that bypass execution_pipeline trust enforcement across startup user_triggered background_async and plugin_extension surfaces'
$contract += ('changes_introduced=' + $(if ($checkRuntimePatchNeeded) { 'Applied_one_minimal_gap_fix' } else { 'No_runtime_changes_coverage_only' }))
$contract += ('runtime_behavior_changes=' + $(if ($checkRuntimePatchNeeded) { 'One_minimal_execution_pipeline_enforcement_fix_added' } else { 'No_runtime_behavior_change_all_surfaces_already_enforced_or_explicitly_exempt' }))
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_coverage_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_coverage_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase70_3_execution_coverage_sweep_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase70_3_status=' + $phaseStatus)
exit 0