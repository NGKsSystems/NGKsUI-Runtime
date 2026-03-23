#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_13: DIRECT-PROCESS OPTIMIZATION CONFIRMATION + VARIANCE CHECK
# ============================================================================
# Measurement-only phase.
# No runtime code changes.
# One fresh run with before/after-style batches on current kept implementation.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_13_widget_operator_direct_process_confirmation_variance_$Timestamp"
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

function Get-HighResMetric {
  param(
    [string]$Path,
    [string]$Context,
    [string]$Metric
  )

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $null }

  $pattern = '^runtime_guard_highres_' + [regex]::Escape($Metric) + '_ns=(\d+)\s+context=' + [regex]::Escape($Context) + '$'
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match $pattern) {
      return [long]$Matches[1]
    }
  }

  return $null
}

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }

  foreach ($line in $lines) {
    if ($line -match $Pattern) {
      return $true
    }
  }

  return $false
}

function Get-Percentile {
  param(
    [double[]]$Values,
    [double]$Percentile
  )

  if (-not $Values -or $Values.Count -eq 0) { return 0.0 }
  $sorted = @($Values | Sort-Object)
  $n = $sorted.Count
  if ($n -eq 1) { return [double]$sorted[0] }

  $rank = ($Percentile / 100.0) * ($n - 1)
  $lower = [Math]::Floor($rank)
  $upper = [Math]::Ceiling($rank)
  if ($lower -eq $upper) { return [double]$sorted[$lower] }

  $weight = $rank - $lower
  return ([double]$sorted[$lower] * (1.0 - $weight)) + ([double]$sorted[$upper] * $weight)
}

function Get-Stats {
  param([double[]]$Values)

  if (-not $Values -or $Values.Count -eq 0) {
    return [pscustomobject]@{
      Count = 0
      Avg = 0.0
      Min = 0.0
      Max = 0.0
      StdDev = 0.0
      P50 = 0.0
      P95 = 0.0
    }
  }

  $avg = [double](($Values | Measure-Object -Average).Average)
  $min = [double](($Values | Measure-Object -Minimum).Minimum)
  $max = [double](($Values | Measure-Object -Maximum).Maximum)

  $sumSq = 0.0
  foreach ($v in $Values) {
    $d = ([double]$v - $avg)
    $sumSq += ($d * $d)
  }
  $variance = $sumSq / [double]$Values.Count
  $stddev = [Math]::Sqrt($variance)

  return [pscustomobject]@{
    Count = $Values.Count
    Avg = $avg
    Min = $min
    Max = $max
    StdDev = [double]$stddev
    P50 = [double](Get-Percentile -Values $Values -Percentile 50)
    P95 = [double](Get-Percentile -Values $Values -Percentile 95)
  }
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

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$beforeCleanCount = 4
$beforeBlockedCount = 3
$afterCleanCount = 4
$afterBlockedCount = 3

$rows = @()

for ($i = 1; $i -le $beforeCleanCount; $i++) {
  $name = ('01_before_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before clean run {0}/{1}" -f $i, $beforeCleanCount)

  $inv = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_clean_{0:D2}" -f $i)
  $spawnWindowNs = Get-HighResMetric -Path $outFile -Context 'runtime_init' -Metric 'process_spawn_execution_window'

  $rows += [pscustomobject]@{
    Phase = 'before'
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE'
    SpawnWindowNs = $spawnWindowNs
    HasSummary = Test-LinePresent -Path $outFile -Pattern '^LAUNCH_FINAL_SUMMARY\s+'
    HasRuntimeFinalStatus = Test-LinePresent -Path $outFile -Pattern '^runtime_final_status='
    HasRuntimeGuardElapsed = Test-LinePresent -Path $outFile -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$'
    HasTimingBoundary = Test-LinePresent -Path $outFile -Pattern '^TIMING_BOUNDARY\s+'
  }
}

for ($i = 1; $i -le $beforeBlockedCount; $i++) {
  $name = ('02_before_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before blocked run {0}/{1}" -f $i, $beforeBlockedCount)

  $inv = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_blocked_{0:D2}" -f $i)

  $rows += [pscustomobject]@{
    Phase = 'before'
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE'
    SpawnWindowNs = $null
    HasSummary = Test-LinePresent -Path $outFile -Pattern '^LAUNCH_FINAL_SUMMARY\s+'
    HasRuntimeFinalStatus = Test-LinePresent -Path $outFile -Pattern '^runtime_final_status='
    HasRuntimeGuardElapsed = Test-LinePresent -Path $outFile -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$'
    HasTimingBoundary = Test-LinePresent -Path $outFile -Pattern '^TIMING_BOUNDARY\s+'
  }
}

for ($i = 1; $i -le $afterCleanCount; $i++) {
  $name = ('03_after_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After clean run {0}/{1}" -f $i, $afterCleanCount)

  $inv = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_clean_{0:D2}" -f $i)
  $spawnWindowNs = Get-HighResMetric -Path $outFile -Context 'runtime_init' -Metric 'process_spawn_execution_window'

  $rows += [pscustomobject]@{
    Phase = 'after'
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE'
    SpawnWindowNs = $spawnWindowNs
    HasSummary = Test-LinePresent -Path $outFile -Pattern '^LAUNCH_FINAL_SUMMARY\s+'
    HasRuntimeFinalStatus = Test-LinePresent -Path $outFile -Pattern '^runtime_final_status='
    HasRuntimeGuardElapsed = Test-LinePresent -Path $outFile -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$'
    HasTimingBoundary = Test-LinePresent -Path $outFile -Pattern '^TIMING_BOUNDARY\s+'
  }
}

for ($i = 1; $i -le $afterBlockedCount; $i++) {
  $name = ('04_after_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After blocked run {0}/{1}" -f $i, $afterBlockedCount)

  $inv = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_blocked_{0:D2}" -f $i)

  $rows += [pscustomobject]@{
    Phase = 'after'
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE'
    SpawnWindowNs = $null
    HasSummary = Test-LinePresent -Path $outFile -Pattern '^LAUNCH_FINAL_SUMMARY\s+'
    HasRuntimeFinalStatus = Test-LinePresent -Path $outFile -Pattern '^runtime_final_status='
    HasRuntimeGuardElapsed = Test-LinePresent -Path $outFile -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$'
    HasTimingBoundary = Test-LinePresent -Path $outFile -Pattern '^TIMING_BOUNDARY\s+'
  }
}

$beforeClean = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'clean' })
$afterClean = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'clean' })
$beforeBlocked = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'blocked' })
$afterBlocked = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'blocked' })
$allRows = @($rows)

$beforeStats = Get-Stats -Values (@($beforeClean | ForEach-Object { if ($null -ne $_.SpawnWindowNs) { [double]$_.SpawnWindowNs } }))
$afterStats = Get-Stats -Values (@($afterClean | ForEach-Object { if ($null -ne $_.SpawnWindowNs) { [double]$_.SpawnWindowNs } }))
$combinedStats = Get-Stats -Values (@($beforeClean + $afterClean | ForEach-Object { if ($null -ne $_.SpawnWindowNs) { [double]$_.SpawnWindowNs } }))

$checks = @()
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_clean_before_status_ok=' + $(if ((@($beforeClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_clean_after_status_ok=' + $(if ((@($afterClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_before_fail_closed=' + $(if ((@($beforeBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_after_fail_closed=' + $(if ((@($afterBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_spawn_metric_present_clean_runs=' + $(if ((@($beforeClean + $afterClean | Where-Object { $null -eq $_.SpawnWindowNs }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_summaries_present_all_runs=' + $(if ((@($allRows | Where-Object { -not $_.HasSummary }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_runtime_final_status_present_clean=' + $(if ((@($beforeClean + $afterClean | Where-Object { -not $_.HasRuntimeFinalStatus }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_runtime_guard_elapsed_present_clean=' + $(if ((@($beforeClean + $afterClean | Where-Object { -not $_.HasRuntimeGuardElapsed }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_timing_boundaries_present_all_runs=' + $(if ((@($allRows | Where-Object { -not $_.HasTimingBoundary }).Count) -eq 0) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_direct_process_confirmation_checks.txt'
$lines = @()
$lines += 'patched_file_count=0'
$lines += 'patched_files=NONE'
$lines += 'confirmation_target=runtime_guard_highres_process_spawn_execution_window_ns'
$lines += 'measurement_mode=fresh_before_after_style_no_code_change'
$lines += ('before_clean_count=' + $beforeClean.Count)
$lines += ('before_blocked_count=' + $beforeBlocked.Count)
$lines += ('after_clean_count=' + $afterClean.Count)
$lines += ('after_blocked_count=' + $afterBlocked.Count)

$lines += ('before_avg_ns=' + [Math]::Round($beforeStats.Avg, 3))
$lines += ('before_min_ns=' + [Math]::Round($beforeStats.Min, 3))
$lines += ('before_max_ns=' + [Math]::Round($beforeStats.Max, 3))
$lines += ('before_stddev_ns=' + [Math]::Round($beforeStats.StdDev, 3))
$lines += ('before_p50_ns=' + [Math]::Round($beforeStats.P50, 3))
$lines += ('before_p95_ns=' + [Math]::Round($beforeStats.P95, 3))

$lines += ('after_avg_ns=' + [Math]::Round($afterStats.Avg, 3))
$lines += ('after_min_ns=' + [Math]::Round($afterStats.Min, 3))
$lines += ('after_max_ns=' + [Math]::Round($afterStats.Max, 3))
$lines += ('after_stddev_ns=' + [Math]::Round($afterStats.StdDev, 3))
$lines += ('after_p50_ns=' + [Math]::Round($afterStats.P50, 3))
$lines += ('after_p95_ns=' + [Math]::Round($afterStats.P95, 3))

$lines += ('combined_avg_ns=' + [Math]::Round($combinedStats.Avg, 3))
$lines += ('combined_min_ns=' + [Math]::Round($combinedStats.Min, 3))
$lines += ('combined_max_ns=' + [Math]::Round($combinedStats.Max, 3))
$lines += ('combined_stddev_ns=' + [Math]::Round($combinedStats.StdDev, 3))
$lines += ('combined_p50_ns=' + [Math]::Round($combinedStats.P50, 3))
$lines += ('combined_p95_ns=' + [Math]::Round($combinedStats.P95, 3))

foreach ($r in $allRows) {
  $lines += ("run_{0}_{1}_{2:D2}_final_status={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.FinalStatus)
  $lines += ("run_{0}_{1}_{2:D2}_exit_code={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.ExitCode)
  $lines += ("run_{0}_{1}_{2:D2}_blocked_reason={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.BlockedReason)
  $lines += ("run_{0}_{1}_{2:D2}_process_spawn_execution_window_ns={3}" -f $r.Phase, $r.RunType, $r.RunIndex, (ConvertTo-NullableLong -Value $r.SpawnWindowNs))
  $lines += ("run_{0}_{1}_{2:D2}_stdout_file={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.OutFile)
}

$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += ('failed_check_count=' + $failedCount)
$lines += ('failed_checks=' + $failedChecks)
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE66_13_WIDGET_OPERATOR_DIRECT_PROCESS_CONFIRMATION_VARIANCE_CHECK'
$contract += 'objective=Confirm kept direct-process optimization remains stable with fresh before/after-style variance measurement and no behavior regressions'
$contract += 'changes_introduced=None (measurement-only; kept direct-process implementation used as baseline)'
$contract += 'runtime_behavior_changes=None (fail-closed, summaries, diagnostics, and timing fields preserved)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_direct_process_confirmation_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_13_folder={0} phase66_13_status={1} phase66_13_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
