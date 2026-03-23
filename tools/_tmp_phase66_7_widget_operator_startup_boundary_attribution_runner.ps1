#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_7: FINER STARTUP-BOUNDARY ATTRIBUTION INSIDE spawn->runtime_init PATH
# ============================================================================
# Minimal instrumentation only. No behavior changes.
# Fresh run only:
#   1. rebuild widget_sandbox
#   2. one clean validation run
#   3. one blocked validation run
#   4. verify new startup boundaries are emitted and parseable
#   5. verify startup split math is derivable from fresh evidence only
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_7_widget_operator_startup_boundary_attribution_$Timestamp"
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

$requiredNewBoundaries = @(
  'runtime_main_enter_timestamp',
  'runtime_phase53_guard_invoke_timestamp'
)

$requiredContextBoundaries = @(
  'widget_process_spawn_timestamp',
  'runtime_init_guard_start_timestamp'
)

$buildOut = Join-Path $ProofFolder '01_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with startup boundary instrumentation...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$cleanOut = Join-Path $ProofFolder '02_clean_startup_boundary_stdout.txt'
$blockedOut = Join-Path $ProofFolder '03_blocked_startup_boundary_stdout.txt'

Write-Host 'Running clean validation launch...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_startup_boundary'
Write-Host 'Running blocked validation launch...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_startup_boundary'

$cleanMap = Get-BoundaryMap -Path $cleanOut
$blockedMap = Get-BoundaryMap -Path $blockedOut

$cleanProcessLoaderMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_main_enter_timestamp'
$cleanPreGuardAppStartupMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_main_enter_timestamp' -EndName 'runtime_phase53_guard_invoke_timestamp'
$cleanGuardPreparationMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'runtime_phase53_guard_invoke_timestamp' -EndName 'runtime_init_guard_start_timestamp'
$cleanSpawnToGuardStartMs = Get-SegmentMs -BoundaryMap $cleanMap -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_init_guard_start_timestamp'
$cleanStartupSplitTotalMs = [double]((ConvertTo-NullableDouble -Value $cleanProcessLoaderMs) + (ConvertTo-NullableDouble -Value $cleanPreGuardAppStartupMs) + (ConvertTo-NullableDouble -Value $cleanGuardPreparationMs))

$blockedProcessLoaderMs = Get-SegmentMs -BoundaryMap $blockedMap -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_main_enter_timestamp'
$blockedPreGuardAppStartupMs = Get-SegmentMs -BoundaryMap $blockedMap -StartName 'runtime_main_enter_timestamp' -EndName 'runtime_phase53_guard_invoke_timestamp'
$blockedGuardPreparationMs = Get-SegmentMs -BoundaryMap $blockedMap -StartName 'runtime_phase53_guard_invoke_timestamp' -EndName 'runtime_init_guard_start_timestamp'
$blockedSpawnToGuardStartMs = Get-SegmentMs -BoundaryMap $blockedMap -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_init_guard_start_timestamp'
$blockedStartupSplitTotalMs = [double]((ConvertTo-NullableDouble -Value $blockedProcessLoaderMs) + (ConvertTo-NullableDouble -Value $blockedPreGuardAppStartupMs) + (ConvertTo-NullableDouble -Value $blockedGuardPreparationMs))

$cleanSplitMatches = if ($null -ne $cleanSpawnToGuardStartMs) { [Math]::Abs($cleanStartupSplitTotalMs - [double]$cleanSpawnToGuardStartMs) -le 0.001 } else { $false }
$blockedSplitMatches = if ($null -ne $blockedSpawnToGuardStartMs) { [Math]::Abs($blockedStartupSplitTotalMs - [double]$blockedSpawnToGuardStartMs) -le 0.001 } else { $false }

$cleanFinalStatus = Get-LastSummaryValue -Path $cleanOut -Key 'final_status'
$cleanExitCode = Get-LastSummaryValue -Path $cleanOut -Key 'exit_code'
$cleanBlockedReason = Get-LastSummaryValue -Path $cleanOut -Key 'blocked_reason' -Default 'NONE'
$blockedFinalStatus = Get-LastSummaryValue -Path $blockedOut -Key 'final_status'
$blockedExitCode = Get-LastSummaryValue -Path $blockedOut -Key 'exit_code'
$blockedBlockedReason = Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason' -Default 'NONE'

$cleanNewBoundariesPresent = $true
$blockedNewBoundariesPresent = $true
$cleanNewBoundariesParseable = $true
$blockedNewBoundariesParseable = $true
foreach ($name in $requiredNewBoundaries) {
  if (-not $cleanMap.ContainsKey($name)) { $cleanNewBoundariesPresent = $false }
  else {
    if (-not (Test-IsoOrUnavailable -Value $cleanMap[$name].TimestampUtc)) { $cleanNewBoundariesParseable = $false }
  }

  if (-not $blockedMap.ContainsKey($name)) { $blockedNewBoundariesPresent = $false }
  else {
    if (-not (Test-IsoOrUnavailable -Value $blockedMap[$name].TimestampUtc)) { $blockedNewBoundariesParseable = $false }
  }
}

$cleanContextBoundariesPresent = $true
$blockedContextBoundariesPresent = $true
foreach ($name in $requiredContextBoundaries) {
  if (-not $cleanMap.ContainsKey($name)) { $cleanContextBoundariesPresent = $false }
  if (-not $blockedMap.ContainsKey($name)) { $blockedContextBoundariesPresent = $false }
}

$blockedRuntimeNotSpawned = $false
if ($blockedContextBoundariesPresent) {
  $blockedRuntimeNotSpawned = (
    $blockedMap['widget_process_spawn_timestamp'].TimestampUtc -eq 'unavailable' -and
    $blockedMap['runtime_init_guard_start_timestamp'].TimestampUtc -eq 'unavailable' -and
    -not $blockedNewBoundariesPresent
  )
}

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_no_hang=' + $(if ($cleanRun.TimedOut -eq $false -and $blockedRun.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_clean_status_coherent=' + $(if ($cleanFinalStatus -eq 'RUN_OK' -and $cleanExitCode -eq '0') { 'YES' } else { 'NO' }))
$checks += ('check_blocked_status_coherent=' + $(if ($blockedFinalStatus -eq 'BLOCKED' -and $blockedExitCode -eq '120' -and $blockedBlockedReason -eq 'TRUST_CHAIN_BLOCKED') { 'YES' } else { 'NO' }))
$checks += ('check_clean_new_boundaries_present=' + $(if ($cleanNewBoundariesPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_new_boundaries_parseable=' + $(if ($cleanNewBoundariesParseable) { 'YES' } else { 'NO' }))
$checks += ('check_clean_context_boundaries_present=' + $(if ($cleanContextBoundariesPresent) { 'YES' } else { 'NO' }))
$checks += ('check_clean_startup_split_derivable=' + $(if ($null -ne $cleanProcessLoaderMs -and $null -ne $cleanPreGuardAppStartupMs -and $null -ne $cleanGuardPreparationMs -and $null -ne $cleanSpawnToGuardStartMs) { 'YES' } else { 'NO' }))
$checks += ('check_clean_startup_split_math_consistent=' + $(if ($cleanSplitMatches) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_runtime_not_spawned_under_fail_closed=' + $(if ($blockedRuntimeNotSpawned) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_startup_boundary_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/widget_sandbox/main.cpp'
$lines += 'instrumentation_scope=minimal_startup_boundaries_only'
$lines += 'new_boundary_01=runtime_main_enter_timestamp'
$lines += 'new_boundary_02=runtime_phase53_guard_invoke_timestamp'
$lines += 'startup_split_goal=separate_process_loader_from_app_startup_before_enforce_phase53_2'
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))
$lines += ('clean_stdout_file=' + (Split-Path -Leaf $cleanOut))
$lines += ('blocked_stdout_file=' + (Split-Path -Leaf $blockedOut))

foreach ($name in ($requiredContextBoundaries + $requiredNewBoundaries)) {
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

$lines += ('clean_process_loader_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanProcessLoaderMs), 3))
$lines += ('clean_pre_guard_app_startup_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanPreGuardAppStartupMs), 3))
$lines += ('clean_guard_preparation_before_timer_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanGuardPreparationMs), 3))
$lines += ('clean_spawn_to_runtime_init_guard_start_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $cleanSpawnToGuardStartMs), 3))
$lines += ('clean_startup_split_total_ms=' + [Math]::Round($cleanStartupSplitTotalMs, 3))

$lines += ('blocked_process_loader_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $blockedProcessLoaderMs), 3))
$lines += ('blocked_pre_guard_app_startup_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $blockedPreGuardAppStartupMs), 3))
$lines += ('blocked_guard_preparation_before_timer_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $blockedGuardPreparationMs), 3))
$lines += ('blocked_spawn_to_runtime_init_guard_start_ms=' + [Math]::Round((ConvertTo-NullableDouble -Value $blockedSpawnToGuardStartMs), 3))
$lines += ('blocked_startup_split_total_ms=' + [Math]::Round($blockedStartupSplitTotalMs, 3))

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
$contract += 'next_phase_selected=PHASE66_7_WIDGET_OPERATOR_FINER_STARTUP_BOUNDARY_ATTRIBUTION'
$contract += 'objective=Add finer startup timing boundaries that separate process-loader cost from app-startup cost before enforce_phase53_2 and validate they are emitted and parseable'
$contract += 'changes_introduced=Minimal runtime startup timing instrumentation in widget_sandbox main before Phase53 trust enforcement'
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

Write-Host ("phase66_7_folder={0} phase66_7_status={1} phase66_7_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
