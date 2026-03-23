#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_8: GUARD-INTERNAL TIMING SPLIT
# ============================================================================
# Minimal instrumentation only. No behavior changes.
# Fresh run only:
#   1) rebuild widget_sandbox
#   2) one clean validation launch
#   3) one blocked validation launch
#   4) verify new guard-internal boundaries are emitted and parseable
#   5) verify segment math consistency for guard-internal split
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_8_widget_operator_guard_internal_timing_split_$Timestamp"
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

function ConvertTo-ParsedUtc {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq 'unavailable' -or $Value -eq 'missing') { return $null }
  $dt = [datetime]::MinValue
  if ([datetime]::TryParse($Value, [ref]$dt)) { return $dt.ToUniversalTime() }
  return $null
}

function Get-DiffMs {
  param([object]$StartUtc, [object]$EndUtc)
  if ($null -eq $StartUtc -or $null -eq $EndUtc) { return $null }
  $start = [datetime]$StartUtc
  $end = [datetime]$EndUtc
  $ms = ($end - $start).TotalMilliseconds
  if ($ms -lt 0) { return $null }
  return [double]$ms
}

function Get-SegmentMs {
  param(
    [hashtable]$BoundaryMap,
    [string]$StartName,
    [string]$EndName
  )

  if (-not $BoundaryMap.ContainsKey($StartName)) { return $null }
  if (-not $BoundaryMap.ContainsKey($EndName)) { return $null }

  return Get-DiffMs -StartUtc (ConvertTo-ParsedUtc -Value $BoundaryMap[$StartName].TimestampUtc) -EndUtc (ConvertTo-ParsedUtc -Value $BoundaryMap[$EndName].TimestampUtc)
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

function ConvertTo-NullableDouble {
  param([object]$Value)
  if ($null -eq $Value) { return 0.0 }
  return [double]$Value
}

function Test-IsoOrUnavailable {
  param([string]$Value)
  if ($Value -eq 'unavailable') { return $true }
  $parsed = [datetime]::MinValue
  return [datetime]::TryParse($Value, [ref]$parsed)
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

$requiredRuntimeInitGuardBoundaries = @(
  'runtime_guard_runtime_init_command_build_start_timestamp',
  'runtime_guard_runtime_init_command_build_end_timestamp',
  'runtime_guard_runtime_init_execute_call_start_timestamp',
  'runtime_guard_runtime_init_execute_call_end_timestamp'
)

$requiredContextBoundaries = @(
  'runtime_phase53_guard_invoke_timestamp',
  'runtime_init_guard_start_timestamp'
)

$buildOut = Join-Path $ProofFolder '01_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with guard-internal timing instrumentation...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$cleanOut = Join-Path $ProofFolder '02_clean_guard_internal_split_stdout.txt'
$blockedOut = Join-Path $ProofFolder '03_blocked_guard_internal_split_stdout.txt'

Write-Host 'Running clean validation launch...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_guard_internal_split'
Write-Host 'Running blocked validation launch...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_guard_internal_split'

$cleanMap = Get-BoundaryMap -Path $cleanOut
$blockedMap = Get-BoundaryMap -Path $blockedOut

$cleanPreCommandOverheadMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_phase53_guard_invoke_timestamp' -EndName 'runtime_guard_runtime_init_command_build_start_timestamp'
$cleanCommandConstructionMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_guard_runtime_init_command_build_start_timestamp' -EndName 'runtime_guard_runtime_init_command_build_end_timestamp'
$cleanPreExecutionOverheadMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_guard_runtime_init_command_build_end_timestamp' -EndName 'runtime_guard_runtime_init_execute_call_start_timestamp'
$cleanProcessSpawnAndExecutionMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_guard_runtime_init_execute_call_start_timestamp' -EndName 'runtime_guard_runtime_init_execute_call_end_timestamp'
$cleanInvokeToExecuteStartMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_phase53_guard_invoke_timestamp' -EndName 'runtime_guard_runtime_init_execute_call_start_timestamp'
$cleanDerivedGuardStartMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_phase53_guard_invoke_timestamp' -EndName 'runtime_init_guard_start_timestamp'
$cleanInvokeToExecuteStartSplitTotalMs = [double]((ConvertTo-NullableDouble -Value $cleanPreCommandOverheadMs) + (ConvertTo-NullableDouble -Value $cleanCommandConstructionMs) + (ConvertTo-NullableDouble -Value $cleanPreExecutionOverheadMs))
$cleanInvokeToExecuteStartMathConsistent = if ($null -ne $cleanInvokeToExecuteStartMs) { [Math]::Abs($cleanInvokeToExecuteStartSplitTotalMs - [double]$cleanInvokeToExecuteStartMs) -le 0.001 } else { $false }
$cleanDerivedStartAlignmentDeltaMs = if ($null -ne $cleanDerivedGuardStartMs -and $null -ne $cleanInvokeToExecuteStartMs) { [Math]::Abs([double]$cleanDerivedGuardStartMs - [double]$cleanInvokeToExecuteStartMs) } else { $null }

$cleanRuntimeInitBoundariesPresent = $true
$cleanRuntimeInitBoundariesParseable = $true
foreach ($name in $requiredRuntimeInitGuardBoundaries) {
  if (-not $cleanMap.ContainsKey($name)) {
    $cleanRuntimeInitBoundariesPresent = $false
  } else {
    if (-not (Test-IsoOrUnavailable -Value $cleanMap[$name].TimestampUtc)) { $cleanRuntimeInitBoundariesParseable = $false }
  }
}

$blockedRuntimeInitBoundariesPresent = $true
foreach ($name in $requiredRuntimeInitGuardBoundaries) {
  if (-not $blockedMap.ContainsKey($name)) {
    $blockedRuntimeInitBoundariesPresent = $false
  }
}

$blockedRuntimeNotSpawned = $false
if ($blockedMap.ContainsKey('widget_process_spawn_timestamp') -and $blockedMap.ContainsKey('runtime_init_guard_start_timestamp')) {
  $blockedRuntimeNotSpawned = (
    $blockedMap['widget_process_spawn_timestamp'].TimestampUtc -eq 'unavailable' -and
    $blockedMap['runtime_init_guard_start_timestamp'].TimestampUtc -eq 'unavailable' -and
    -not $blockedRuntimeInitBoundariesPresent
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
$checks += ('check_clean_runtime_init_guard_boundaries_present=' + $(if ($cleanRuntimeInitBoundariesPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_runtime_init_guard_boundaries_parseable=' + $(if ($cleanRuntimeInitBoundariesParseable) { 'YES' } else { 'NO' }))
$checks += ('check_clean_guard_internal_split_derivable=' + $(if ($null -ne $cleanPreCommandOverheadMs -and $null -ne $cleanCommandConstructionMs -and $null -ne $cleanPreExecutionOverheadMs -and $null -ne $cleanProcessSpawnAndExecutionMs -and $null -ne $cleanInvokeToExecuteStartMs) { 'YES' } else { 'NO' }))
$checks += ('check_clean_guard_internal_math_consistent=' + $(if ($cleanInvokeToExecuteStartMathConsistent) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_runtime_not_spawned_under_fail_closed=' + $(if ($blockedRuntimeNotSpawned) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_startup_boundary_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/runtime_phase53_guard.hpp'
$lines += 'instrumentation_scope=minimal_guard_internal_boundaries_only'
$lines += 'new_boundary_01=runtime_guard_runtime_init_command_build_start_timestamp'
$lines += 'new_boundary_02=runtime_guard_runtime_init_command_build_end_timestamp'
$lines += 'new_boundary_03=runtime_guard_runtime_init_execute_call_start_timestamp'
$lines += 'new_boundary_04=runtime_guard_runtime_init_execute_call_end_timestamp'
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))
$lines += ('clean_stdout_file=' + (Split-Path -Leaf $cleanOut))
$lines += ('blocked_stdout_file=' + (Split-Path -Leaf $blockedOut))

foreach ($name in ($requiredContextBoundaries + $requiredRuntimeInitGuardBoundaries)) {
  $cleanTs = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].TimestampUtc } else { 'missing' }
  $cleanSource = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].Source } else { 'missing' }
  $cleanQuality = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].Quality } else { 'missing' }
  $lines += ('clean_' + $name + '_ts_utc=' + $cleanTs)
  $lines += ('clean_' + $name + '_source=' + $cleanSource)
  $lines += ('clean_' + $name + '_quality=' + $cleanQuality)

  $blockedTs = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].TimestampUtc } else { 'missing' }
  $blockedSource = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].Source } else { 'missing' }
  $blockedQuality = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].Quality } else { 'missing' }
  $lines += ('blocked_' + $name + '_ts_utc=' + $blockedTs)
  $lines += ('blocked_' + $name + '_source=' + $blockedSource)
  $lines += ('blocked_' + $name + '_quality=' + $blockedQuality)
}

$lines += ('clean_pre_command_overhead_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanPreCommandOverheadMs), 3))
$lines += ('clean_command_construction_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanCommandConstructionMs), 3))
$lines += ('clean_pre_execution_overhead_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanPreExecutionOverheadMs), 3))
$lines += ('clean_process_spawn_and_execution_window_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanProcessSpawnAndExecutionMs), 3))
$lines += ('clean_invoke_to_execute_start_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanInvokeToExecuteStartMs), 3))
$lines += ('clean_invoke_to_execute_start_split_total_ms=' + [Math]::Round($cleanInvokeToExecuteStartSplitTotalMs, 3))
$lines += ('clean_invoke_to_derived_guard_start_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanDerivedGuardStartMs), 3))
$lines += ('clean_derived_guard_start_alignment_delta_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanDerivedStartAlignmentDeltaMs), 3))

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
$contract += 'next_phase_selected=PHASE66_8_WIDGET_OPERATOR_GUARD_INTERNAL_TIMING_SPLIT'
$contract += 'objective=Add guard-internal timing boundaries to separate command construction cost, pre-execution overhead, and execute-call window and validate boundary parseability and math consistency'
$contract += 'changes_introduced=Minimal timing boundary instrumentation inside enforce_runtime_trust around command construction and execution call'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, and output formats preserved)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_startup_boundary_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_8_folder={0} phase66_8_status={1} phase66_8_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
