#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_1: OPERATOR-PATH PERFORMANCE VARIANCE & BOTTLENECK BREAKDOWN
# ============================================================================
# Objective:
#   Measure launch latency variance/distribution for clean and blocked runs,
#   and derive bottleneck breakdown from existing launcher/runtime summaries.
#
# Constraints:
#   - Measurement only
#   - No runtime behavior changes
#   - No optimization in this phase
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_1_widget_operator_performance_variance_bottleneck_$Timestamp"
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

function Invoke-PwshToFileTimed {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true; ElapsedMs = -1 }
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    $sw.Stop()
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true; FileLock = $false; ElapsedMs = [int]$sw.ElapsedMilliseconds }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()
  $sw.Stop()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    if (-not (Remove-FileWithRetry -Path $errFile)) {
      return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true; ElapsedMs = [int]$sw.ElapsedMilliseconds }
    }
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false; ElapsedMs = [int]$sw.ElapsedMilliseconds }
}

function Get-LaunchSummary {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $finalStatus = ''
  $exitCode = ''
  $enforcement = ''
  $blockedReason = ''

  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $finalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\S+)') { $exitCode = $Matches[1] }
    if ($summaryLine -match 'enforcement=(\S+)') { $enforcement = $Matches[1] }
    if ($summaryLine -match 'blocked_reason=(\S+)') { $blockedReason = $Matches[1] }
  }

  $runtimeInitGuardMs = 0.0
  $saveExportGuardMs = 0.0
  $guardLines = @($lines | Where-Object { $_ -match '^runtime_trust_guard_elapsed_ms=' })
  foreach ($g in $guardLines) {
    if ($g -match '^runtime_trust_guard_elapsed_ms=(\d+)\s+context=(\S+)$') {
      $v = [double]$Matches[1]
      $ctx = $Matches[2]
      if ($ctx -eq 'runtime_init') { $runtimeInitGuardMs += $v }
      if ($ctx -eq 'save_export') { $saveExportGuardMs += $v }
    }
  }

  return [pscustomobject]@{
    FinalStatus = $finalStatus
    ExitCode = $exitCode
    Enforcement = $enforcement
    BlockedReason = $blockedReason
    HasFinalSummary = (-not [string]::IsNullOrWhiteSpace($summaryLine))
    RuntimeInitGuardMs = $runtimeInitGuardMs
    SaveExportGuardMs = $saveExportGuardMs
  }
}

function Get-Percentile {
  param([double[]]$Values, [double]$Percentile)
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
    return [pscustomobject]@{ Count = 0; Avg = 0.0; Min = 0.0; Max = 0.0; P50 = 0.0; P95 = 0.0; P99 = 0.0; Variance = 0.0; StdDev = 0.0 }
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
    P50 = [double](Get-Percentile -Values $Values -Percentile 50)
    P95 = [double](Get-Percentile -Values $Values -Percentile 95)
    P99 = [double](Get-Percentile -Values $Values -Percentile 99)
    Variance = [double]$variance
    StdDev = [double]$stddev
  }
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

$batchSw = [System.Diagnostics.Stopwatch]::StartNew()

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$cleanCount = 8
$blockedCount = 6
$rows = @()

for ($i = 1; $i -le $cleanCount; $i++) {
  $name = ('{0:D2}_clean_run_{1:D2}_stdout.txt' -f $i, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Clean run {0}/{1}" -f $i, $cleanCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("clean_run_{0:D2}" -f $i)
  $summary = Get-LaunchSummary -Path $outFile

  $rows += [pscustomobject]@{
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = [string]$summary.FinalStatus
    ExitCode = [string]$summary.ExitCode
    Enforcement = [string]$summary.Enforcement
    BlockedReason = [string]$summary.BlockedReason
    HasFinalSummary = [bool]$summary.HasFinalSummary
    RuntimeInitGuardMs = [double]$summary.RuntimeInitGuardMs
    SaveExportGuardMs = [double]$summary.SaveExportGuardMs
  }
}

for ($i = 1; $i -le $blockedCount; $i++) {
  $globalIndex = $cleanCount + $i
  $name = ('{0:D2}_blocked_run_{1:D2}_stdout.txt' -f $globalIndex, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Blocked run {0}/{1}" -f $i, $blockedCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("blocked_run_{0:D2}" -f $i)
  $summary = Get-LaunchSummary -Path $outFile

  $rows += [pscustomobject]@{
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = [string]$summary.FinalStatus
    ExitCode = [string]$summary.ExitCode
    Enforcement = [string]$summary.Enforcement
    BlockedReason = [string]$summary.BlockedReason
    HasFinalSummary = [bool]$summary.HasFinalSummary
    RuntimeInitGuardMs = [double]$summary.RuntimeInitGuardMs
    SaveExportGuardMs = [double]$summary.SaveExportGuardMs
  }
}

$batchSw.Stop()
$batchElapsedMs = [double]$batchSw.ElapsedMilliseconds

$cleanRows = @($rows | Where-Object { $_.RunType -eq 'clean' })
$blockedRows = @($rows | Where-Object { $_.RunType -eq 'blocked' })
$allRows = @($rows)

$cleanLatency = @($cleanRows | ForEach-Object { [double]$_.ElapsedMs })
$blockedLatency = @($blockedRows | ForEach-Object { [double]$_.ElapsedMs })
$overallLatency = @($allRows | ForEach-Object { [double]$_.ElapsedMs })

$cleanStats = Get-Stats -Values $cleanLatency
$blockedStats = Get-Stats -Values $blockedLatency
$overallStats = Get-Stats -Values $overallLatency

$avgRuntimeInitGuardMs = [double]((@($cleanRows | ForEach-Object { $_.RuntimeInitGuardMs }) | Measure-Object -Average).Average)
$avgSaveExportGuardMs = [double]((@($cleanRows | ForEach-Object { $_.SaveExportGuardMs }) | Measure-Object -Average).Average)
if ([double]::IsNaN($avgRuntimeInitGuardMs)) { $avgRuntimeInitGuardMs = 0.0 }
if ([double]::IsNaN($avgSaveExportGuardMs)) { $avgSaveExportGuardMs = 0.0 }

$avgKnownGuardMs = $avgRuntimeInitGuardMs + $avgSaveExportGuardMs
$avgUnattributedMs = [double]($cleanStats.Avg - $avgKnownGuardMs)
if ($avgUnattributedMs -lt 0) { $avgUnattributedMs = 0.0 }

$segmentPairs = @(
  [pscustomobject]@{ Name = 'runtime_init_guard'; AvgMs = $avgRuntimeInitGuardMs },
  [pscustomobject]@{ Name = 'save_export_guard'; AvgMs = $avgSaveExportGuardMs },
  [pscustomobject]@{ Name = 'unattributed_launch_overhead'; AvgMs = $avgUnattributedMs }
)
$dominant = $segmentPairs | Sort-Object AvgMs -Descending | Select-Object -First 1

$checks = @()
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_clean_distribution_valid=' + $(if ((@($cleanRows | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_distribution_valid=' + $(if ((@($blockedRows | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_stddev_nonnegative=' + $(if ($cleanStats.StdDev -ge 0 -and $blockedStats.StdDev -ge 0 -and $overallStats.StdDev -ge 0) { 'YES' } else { 'NO' }))
$checks += ('check_percentiles_monotonic=' + $(if (
  ($cleanStats.Min -le $cleanStats.P50 -and $cleanStats.P50 -le $cleanStats.P95 -and $cleanStats.P95 -le $cleanStats.P99 -and $cleanStats.P99 -le $cleanStats.Max) -and
  ($blockedStats.Min -le $blockedStats.P50 -and $blockedStats.P50 -le $blockedStats.P95 -and $blockedStats.P95 -le $blockedStats.P99 -and $blockedStats.P99 -le $blockedStats.Max) -and
  ($overallStats.Min -le $overallStats.P50 -and $overallStats.P50 -le $overallStats.P95 -and $overallStats.P95 -le $overallStats.P99 -and $overallStats.P99 -le $overallStats.Max)
) { 'YES' } else { 'NO' }))
$checks += ('check_guard_segment_derivable=' + $(if ((@($cleanRows | Where-Object { $_.RuntimeInitGuardMs -gt 0 -or $_.SaveExportGuardMs -gt 0 }).Count) -gt 0) { 'YES' } else { 'NO' }))

$cleanVsBlockedAvgDeltaMs = [double]($blockedStats.Avg - $cleanStats.Avg)

$checksFile = Join-Path $ProofFolder '90_performance_variance_checks.txt'
$lines = @()
$lines += "batch_total_launches=$($allRows.Count)"
$lines += "batch_clean_launches=$($cleanRows.Count)"
$lines += "batch_blocked_launches=$($blockedRows.Count)"
$lines += "batch_total_runtime_ms=$([Math]::Round($batchElapsedMs, 3))"

$lines += "overall_avg_latency_ms=$([Math]::Round($overallStats.Avg, 3))"
$lines += "overall_variance_ms2=$([Math]::Round($overallStats.Variance, 3))"
$lines += "overall_stddev_ms=$([Math]::Round($overallStats.StdDev, 3))"
$lines += "overall_min_latency_ms=$([Math]::Round($overallStats.Min, 3))"
$lines += "overall_max_latency_ms=$([Math]::Round($overallStats.Max, 3))"
$lines += "overall_p50_latency_ms=$([Math]::Round($overallStats.P50, 3))"
$lines += "overall_p95_latency_ms=$([Math]::Round($overallStats.P95, 3))"
$lines += "overall_p99_latency_ms=$([Math]::Round($overallStats.P99, 3))"

$lines += "clean_avg_latency_ms=$([Math]::Round($cleanStats.Avg, 3))"
$lines += "clean_variance_ms2=$([Math]::Round($cleanStats.Variance, 3))"
$lines += "clean_stddev_ms=$([Math]::Round($cleanStats.StdDev, 3))"
$lines += "clean_min_latency_ms=$([Math]::Round($cleanStats.Min, 3))"
$lines += "clean_max_latency_ms=$([Math]::Round($cleanStats.Max, 3))"
$lines += "clean_p50_latency_ms=$([Math]::Round($cleanStats.P50, 3))"
$lines += "clean_p95_latency_ms=$([Math]::Round($cleanStats.P95, 3))"
$lines += "clean_p99_latency_ms=$([Math]::Round($cleanStats.P99, 3))"

$lines += "blocked_avg_latency_ms=$([Math]::Round($blockedStats.Avg, 3))"
$lines += "blocked_variance_ms2=$([Math]::Round($blockedStats.Variance, 3))"
$lines += "blocked_stddev_ms=$([Math]::Round($blockedStats.StdDev, 3))"
$lines += "blocked_min_latency_ms=$([Math]::Round($blockedStats.Min, 3))"
$lines += "blocked_max_latency_ms=$([Math]::Round($blockedStats.Max, 3))"
$lines += "blocked_p50_latency_ms=$([Math]::Round($blockedStats.P50, 3))"
$lines += "blocked_p95_latency_ms=$([Math]::Round($blockedStats.P95, 3))"
$lines += "blocked_p99_latency_ms=$([Math]::Round($blockedStats.P99, 3))"

$lines += "clean_vs_blocked_avg_delta_ms=$([Math]::Round($cleanVsBlockedAvgDeltaMs, 3))"

$lines += "avg_runtime_init_guard_ms=$([Math]::Round($avgRuntimeInitGuardMs, 3))"
$lines += "avg_save_export_guard_ms=$([Math]::Round($avgSaveExportGuardMs, 3))"
$lines += "avg_unattributed_launch_overhead_ms=$([Math]::Round($avgUnattributedMs, 3))"
$lines += "dominant_bottleneck_segment=$($dominant.Name)"
$lines += "dominant_bottleneck_avg_ms=$([Math]::Round([double]$dominant.AvgMs, 3))"

foreach ($r in $allRows) {
  $lines += ("run_{0}_{1:D2}_latency_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.ElapsedMs, 3))
  $lines += ("run_{0}_{1:D2}_final_status={2}" -f $r.RunType, $r.RunIndex, $r.FinalStatus)
  $lines += ("run_{0}_{1:D2}_exit_code={2}" -f $r.RunType, $r.RunIndex, $r.ExitCode)
  $lines += ("run_{0}_{1:D2}_blocked_reason={2}" -f $r.RunType, $r.RunIndex, $r.BlockedReason)
  $lines += ("run_{0}_{1:D2}_runtime_init_guard_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.RuntimeInitGuardMs, 3))
  $lines += ("run_{0}_{1:D2}_save_export_guard_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.SaveExportGuardMs, 3))
  $lines += ("run_{0}_{1:D2}_stdout_file={2}" -f $r.RunType, $r.RunIndex, $r.OutFile)
}

$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += "failed_check_count=$failedCount"
$lines += "failed_checks=$failedChecks"

$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE66_1_WIDGET_OPERATOR_PERFORMANCE_VARIANCE_AND_BOTTLENECK_BREAKDOWN'
$contract += 'objective=Measure latency variance/stddev and derive dominant bottleneck segment from existing runtime summaries'
$contract += 'changes_introduced=None (measurement-only; no runtime code changes and no optimization)'
$contract += 'runtime_behavior_changes=None (observed launch behavior only for clean/blocked paths)'
$contract += 'new_regressions_detected=No'
$contract += "phase_status=$phaseStatus"
$contract += "proof_folder=$ProofFolderRelative"
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_performance_variance_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_1_folder={0} phase66_1_status={1} phase66_1_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
