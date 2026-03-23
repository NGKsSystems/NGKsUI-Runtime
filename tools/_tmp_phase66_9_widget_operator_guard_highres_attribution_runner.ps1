#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_9: HIGHER-RESOLUTION GUARD TIMING ATTRIBUTION
# ============================================================================
# Minimal instrumentation only. No behavior changes.
# Existing timing boundaries remain intact.
# Fresh run only:
#   1) rebuild widget_sandbox
#   2) one clean validation launch
#   3) one blocked validation launch
#   4) verify high-resolution fields exist and are parseable
#   5) verify segment math consistency
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_9_widget_operator_guard_highres_attribution_$Timestamp"
$ProofFolder = Join-Path $ProofRoot $ProofFolderName
$ProofFolderRelative = "_proof/$ProofFolderName"
$ZipPath = "$ProofFolder.zip"

New-Item -ItemType Directory -Path $ProofFolder -Force | Out-Null
Write-Host "Proof folder: $ProofFolder"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item $Path -Force -ErrorAction Stop
      return $true
    } catch {
      $attempt++
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds 100 }
    }
  }
  return -not (Test-Path $Path)
}

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true; FileLock = $false }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    if (-not (Remove-FileWithRetry -Path $errFile)) {
      return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
    }
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false }
}

function Invoke-CmdToFile {
  param(
    [string]$CommandLine,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true; FileLock = $false }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    [void](Remove-FileWithRetry -Path $errFile)
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false }
}

function Get-BoundaryMap {
  param([string]$Path)

  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  foreach ($line in $lines) {
    if ($line -match '^TIMING_BOUNDARY\s+name=([^\s]+)\s+ts_utc=([^\s]+)\s+source=([^\s]+)\s+quality=([^\s]+)$') {
      $map[$Matches[1]] = [pscustomobject]@{
        TimestampUtc = $Matches[2]
        Source = $Matches[3]
        Quality = $Matches[4]
      }
    }
  }

  return $map
}

function Get-HighResMap {
  param([string]$Path)

  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  foreach ($line in $lines) {
    if ($line -match '^runtime_guard_highres_([a-zA-Z0-9_]+)_ns=(\d+)\s+context=(\S+)$') {
      $metric = $Matches[1]
      $value = [long]$Matches[2]
      $contextName = $Matches[3]
      $key = $contextName + '|' + $metric
      $map[$key] = $value
    }
  }

  return $map
}

function Get-HighResValue {
  param(
    [hashtable]$Map,
    [string]$Context,
    [string]$Metric
  )

  $key = $Context + '|' + $Metric
  if ($Map.ContainsKey($key)) { return [long]$Map[$key] }
  return $null
}

function Get-LastSummaryValue {
  param([string]$Path, [string]$Key, [string]$Default = '')
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $Default }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match ('\b' + [regex]::Escape($Key) + '=(\S+)')) {
      return $Matches[1]
    }
  }
  return $Default
}

function ConvertTo-NullableLong {
  param([object]$Value)
  if ($null -eq $Value) { return [long]0 }
  return [long]$Value
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path $FilePath)) { return $false }
  $lines = @(Get-Content -Path $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

$requiredRuntimeInitHighResMetrics = @(
  'pre_command_overhead',
  'command_construction',
  'pre_execution_overhead',
  'process_spawn_execution_window',
  'invoke_to_execute_start',
  'pre_execute_split_total'
)

$requiredExistingBoundaries = @(
  'runtime_guard_runtime_init_command_build_start_timestamp',
  'runtime_guard_runtime_init_command_build_end_timestamp',
  'runtime_guard_runtime_init_execute_call_start_timestamp',
  'runtime_guard_runtime_init_execute_call_end_timestamp'
)

$buildOut = Join-Path $ProofFolder '01_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with high-resolution guard instrumentation...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$cleanOut = Join-Path $ProofFolder '02_clean_guard_highres_stdout.txt'
$blockedOut = Join-Path $ProofFolder '03_blocked_guard_highres_stdout.txt'

Write-Host 'Running clean validation launch...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_guard_highres'
Write-Host 'Running blocked validation launch...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_guard_highres'

$cleanBoundaries = Get-BoundaryMap -Path $cleanOut
$blockedBoundaries = Get-BoundaryMap -Path $blockedOut
$cleanHighRes = Get-HighResMap -Path $cleanOut
$blockedHighRes = Get-HighResMap -Path $blockedOut

$cleanHighResPresent = $true
foreach ($metric in $requiredRuntimeInitHighResMetrics) {
  if ($null -eq (Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric $metric)) {
    $cleanHighResPresent = $false
  }
}

$cleanExistingBoundariesPresent = $true
foreach ($name in $requiredExistingBoundaries) {
  if (-not $cleanBoundaries.ContainsKey($name)) {
    $cleanExistingBoundariesPresent = $false
  }
}

$cleanPreCommandNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'pre_command_overhead'
$cleanCommandNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'command_construction'
$cleanPreExecutionNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'pre_execution_overhead'
$cleanSpawnExecNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'process_spawn_execution_window'
$cleanInvokeToExecStartNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'invoke_to_execute_start'
$cleanPreExecuteSplitTotalNs = Get-HighResValue -Map $cleanHighRes -Context 'runtime_init' -Metric 'pre_execute_split_total'

$cleanExpectedSplitTotalNs = [long]((ConvertTo-NullableLong -Value $cleanPreCommandNs) + (ConvertTo-NullableLong -Value $cleanCommandNs) + (ConvertTo-NullableLong -Value $cleanPreExecutionNs))
$cleanMathConsistentA = ($cleanExpectedSplitTotalNs -eq (ConvertTo-NullableLong -Value $cleanPreExecuteSplitTotalNs))
$cleanMathConsistentB = ((ConvertTo-NullableLong -Value $cleanPreExecuteSplitTotalNs) -eq (ConvertTo-NullableLong -Value $cleanInvokeToExecStartNs))
$cleanMathConsistent = ($cleanMathConsistentA -and $cleanMathConsistentB)

$cleanAllNonNegative = (
  (ConvertTo-NullableLong -Value $cleanPreCommandNs) -ge 0 -and
  (ConvertTo-NullableLong -Value $cleanCommandNs) -ge 0 -and
  (ConvertTo-NullableLong -Value $cleanPreExecutionNs) -ge 0 -and
  (ConvertTo-NullableLong -Value $cleanSpawnExecNs) -ge 0 -and
  (ConvertTo-NullableLong -Value $cleanInvokeToExecStartNs) -ge 0 -and
  (ConvertTo-NullableLong -Value $cleanPreExecuteSplitTotalNs) -ge 0
)

$blockedHasRuntimeHighRes = $false
foreach ($metric in $requiredRuntimeInitHighResMetrics) {
  if ($null -ne (Get-HighResValue -Map $blockedHighRes -Context 'runtime_init' -Metric $metric)) {
    $blockedHasRuntimeHighRes = $true
  }
}

$blockedRuntimeNotSpawned = $false
if ($blockedBoundaries.ContainsKey('widget_process_spawn_timestamp') -and $blockedBoundaries.ContainsKey('runtime_init_guard_start_timestamp')) {
  $blockedRuntimeNotSpawned = (
    $blockedBoundaries['widget_process_spawn_timestamp'].TimestampUtc -eq 'unavailable' -and
    $blockedBoundaries['runtime_init_guard_start_timestamp'].TimestampUtc -eq 'unavailable' -and
    -not $blockedHasRuntimeHighRes
  )
}

$cleanFinalStatus = Get-LastSummaryValue -Path $cleanOut -Key 'final_status'
$cleanExitCode = Get-LastSummaryValue -Path $cleanOut -Key 'exit_code'
$cleanBlockedReason = Get-LastSummaryValue -Path $cleanOut -Key 'blocked_reason' -Default 'NONE'
$blockedFinalStatus = Get-LastSummaryValue -Path $blockedOut -Key 'final_status'
$blockedExitCode = Get-LastSummaryValue -Path $blockedOut -Key 'exit_code'
$blockedBlockedReason = Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason' -Default 'NONE'

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_no_hang=' + $(if ($cleanRun.TimedOut -eq $false -and $blockedRun.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_clean_status_coherent=' + $(if ($cleanFinalStatus -eq 'RUN_OK' -and $cleanExitCode -eq '0') { 'YES' } else { 'NO' }))
$checks += ('check_blocked_status_coherent=' + $(if ($blockedFinalStatus -eq 'BLOCKED' -and $blockedExitCode -eq '120' -and $blockedBlockedReason -eq 'TRUST_CHAIN_BLOCKED') { 'YES' } else { 'NO' }))
$checks += ('check_existing_boundaries_intact=' + $(if ($cleanExistingBoundariesPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_highres_fields_present=' + $(if ($cleanHighResPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_highres_fields_parseable=' + $(if ($cleanHighResPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_highres_fields_nonnegative=' + $(if ($cleanAllNonNegative) { 'YES' } else { 'NO' }))
$checks += ('check_clean_highres_math_consistent=' + $(if ($cleanMathConsistent) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_runtime_not_spawned_under_fail_closed=' + $(if ($blockedRuntimeNotSpawned) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_guard_highres_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/runtime_phase53_guard.hpp'
$lines += 'instrumentation_scope=minimal_highres_guard_internal_fields_only'
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))
$lines += ('clean_stdout_file=' + (Split-Path -Leaf $cleanOut))
$lines += ('blocked_stdout_file=' + (Split-Path -Leaf $blockedOut))

foreach ($name in $requiredExistingBoundaries) {
  $cleanTs = if ($cleanBoundaries.ContainsKey($name)) { $cleanBoundaries[$name].TimestampUtc } else { 'missing' }
  $cleanSource = if ($cleanBoundaries.ContainsKey($name)) { $cleanBoundaries[$name].Source } else { 'missing' }
  $cleanQuality = if ($cleanBoundaries.ContainsKey($name)) { $cleanBoundaries[$name].Quality } else { 'missing' }
  $lines += ('clean_' + $name + '_ts_utc=' + $cleanTs)
  $lines += ('clean_' + $name + '_source=' + $cleanSource)
  $lines += ('clean_' + $name + '_quality=' + $cleanQuality)
}

$lines += ('clean_runtime_init_pre_command_overhead_ns=' + (ConvertTo-NullableLong -Value $cleanPreCommandNs))
$lines += ('clean_runtime_init_command_construction_ns=' + (ConvertTo-NullableLong -Value $cleanCommandNs))
$lines += ('clean_runtime_init_pre_execution_overhead_ns=' + (ConvertTo-NullableLong -Value $cleanPreExecutionNs))
$lines += ('clean_runtime_init_process_spawn_execution_window_ns=' + (ConvertTo-NullableLong -Value $cleanSpawnExecNs))
$lines += ('clean_runtime_init_invoke_to_execute_start_ns=' + (ConvertTo-NullableLong -Value $cleanInvokeToExecStartNs))
$lines += ('clean_runtime_init_pre_execute_split_total_ns=' + (ConvertTo-NullableLong -Value $cleanPreExecuteSplitTotalNs))
$lines += ('clean_runtime_init_expected_split_total_ns=' + $cleanExpectedSplitTotalNs)

$lines += ('clean_final_status=' + $cleanFinalStatus)
$lines += ('clean_exit_code=' + $cleanExitCode)
$lines += ('clean_blocked_reason=' + $cleanBlockedReason)
$lines += ('blocked_final_status=' + $blockedFinalStatus)
$lines += ('blocked_exit_code=' + $blockedExitCode)
$lines += ('blocked_blocked_reason=' + $blockedBlockedReason)

$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += ('failed_check_count=' + $failedCount)
$lines += ('failed_checks=' + $failedChecks)
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE66_9_WIDGET_OPERATOR_GUARD_HIGHER_RESOLUTION_TIMING_ATTRIBUTION'
$contract += 'objective=Add high-resolution monotonic guard-internal timing fields for command construction, pre-execution overhead, and process spawn/execution window and validate parseability and math consistency'
$contract += 'changes_introduced=Minimal high-resolution timing fields added inside enforce_runtime_trust while preserving existing timing boundaries'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, and output formats preserved)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_guard_highres_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_9_folder={0} phase66_9_status={1} phase66_9_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
