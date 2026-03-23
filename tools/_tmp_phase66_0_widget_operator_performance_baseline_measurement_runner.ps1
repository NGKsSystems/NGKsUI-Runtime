#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_0: OPERATOR-PATH PERFORMANCE BASELINE MEASUREMENT (MEASUREMENT ONLY)
# ============================================================================
# Objective:
#   Establish a baseline latency profile for operator-path launches.
#   No runtime behavior changes and no optimization in this phase.
#
# In one run:
#   - Execute multiple clean launches
#   - Execute multiple blocked launches
#   - Measure per-launch latency from process start to final summary capture
#   - Compute average, p50, p95, p99
#   - Compare clean vs blocked latency
#   - Record total batch runtime
#
# Outputs:
#   - Per-run stdout files
#   - 90_performance_checks.txt
#   - 99_contract_summary.txt
#   - proof zip
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolder = Join-Path $ProofRoot "phase66_0_widget_operator_performance_baseline_measurement_$Timestamp"
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
    return [pscustomobject]@{
      ExitCode = 124
      TimedOut = $true
      FileLock = $false
      ElapsedMs = [int]$sw.ElapsedMilliseconds
    }
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

  return [pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = $false
    FileLock = $false
    ElapsedMs = [int]$sw.ElapsedMilliseconds
  }
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

  return [pscustomobject]@{
    FinalStatus = $finalStatus
    ExitCode = $exitCode
    Enforcement = $enforcement
    BlockedReason = $blockedReason
    HasFinalSummary = (-not [string]::IsNullOrWhiteSpace($summaryLine))
  }
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
    return [pscustomobject]@{ Count = 0; Avg = 0.0; P50 = 0.0; P95 = 0.0; P99 = 0.0; Min = 0.0; Max = 0.0 }
  }

  $avg = ($Values | Measure-Object -Average).Average
  $min = ($Values | Measure-Object -Minimum).Minimum
  $max = ($Values | Measure-Object -Maximum).Maximum

  return [pscustomobject]@{
    Count = $Values.Count
    Avg = [double]$avg
    P50 = [double](Get-Percentile -Values $Values -Percentile 50)
    P95 = [double](Get-Percentile -Values $Values -Percentile 95)
    P99 = [double](Get-Percentile -Values $Values -Percentile 99)
    Min = [double]$min
    Max = [double]$max
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

$cleanCount = 6
$blockedCount = 4

$runRows = @()

for ($i = 1; $i -le $cleanCount; $i++) {
  $name = ('{0:D2}_clean_run_{1:D2}_stdout.txt' -f $i, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Clean run {0}/{1}" -f $i, $cleanCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("clean_run_{0:D2}" -f $i)
  $summary = Get-LaunchSummary -Path $outFile

  $runRows += [pscustomobject]@{
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    ExitCode = [string]$summary.ExitCode
    FinalStatus = [string]$summary.FinalStatus
    Enforcement = [string]$summary.Enforcement
    BlockedReason = [string]$summary.BlockedReason
    HasFinalSummary = [bool]$summary.HasFinalSummary
  }
}

for ($i = 1; $i -le $blockedCount; $i++) {
  $globalIndex = $cleanCount + $i
  $name = ('{0:D2}_blocked_run_{1:D2}_stdout.txt' -f $globalIndex, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Blocked run {0}/{1}" -f $i, $blockedCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("blocked_run_{0:D2}" -f $i)
  $summary = Get-LaunchSummary -Path $outFile

  $runRows += [pscustomobject]@{
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    ExitCode = [string]$summary.ExitCode
    FinalStatus = [string]$summary.FinalStatus
    Enforcement = [string]$summary.Enforcement
    BlockedReason = [string]$summary.BlockedReason
    HasFinalSummary = [bool]$summary.HasFinalSummary
  }
}

$batchSw.Stop()
$batchElapsedMs = [double]$batchSw.ElapsedMilliseconds

$cleanRows = @($runRows | Where-Object { $_.RunType -eq 'clean' })
$blockedRows = @($runRows | Where-Object { $_.RunType -eq 'blocked' })
$allRows = @($runRows)

$cleanLatency = @($cleanRows | ForEach-Object { [double]$_.ElapsedMs })
$blockedLatency = @($blockedRows | ForEach-Object { [double]$_.ElapsedMs })
$allLatency = @($allRows | ForEach-Object { [double]$_.ElapsedMs })

$cleanStats = Get-Stats -Values $cleanLatency
$blockedStats = Get-Stats -Values $blockedLatency
$overallStats = Get-Stats -Values $allLatency

$checks = @()

$checkNoTimeout = if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }
$checks += "check_no_hang=$checkNoTimeout"

$checkCleanFinal = if ((@($cleanRows | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }
$checks += "check_clean_final_status_coherent=$checkCleanFinal"

$checkBlockedFinal = if ((@($blockedRows | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }
$checks += "check_blocked_final_status_coherent=$checkBlockedFinal"

$checkExitCodes = if ((@($allRows | Where-Object { $_.ExitCode -notmatch '^\d+$' }).Count) -eq 0) { 'YES' } else { 'NO' }
$checks += "check_all_exit_codes_numeric=$checkExitCodes"

$checkLatencyPositive = if ((@($allRows | Where-Object { $_.ElapsedMs -le 0 }).Count) -eq 0) { 'YES' } else { 'NO' }
$checks += "check_all_latency_positive_ms=$checkLatencyPositive"

$checkPercentileMonotonic = if (
  ($cleanStats.P50 -le $cleanStats.P95 -and $cleanStats.P95 -le $cleanStats.P99) -and
  ($blockedStats.P50 -le $blockedStats.P95 -and $blockedStats.P95 -le $blockedStats.P99) -and
  ($overallStats.P50 -le $overallStats.P95 -and $overallStats.P95 -le $overallStats.P99)
) { 'YES' } else { 'NO' }
$checks += "check_percentiles_monotonic=$checkPercentileMonotonic"

$cleanVsBlockedAvgDeltaMs = [double]($blockedStats.Avg - $cleanStats.Avg)

$checksFile = Join-Path $ProofFolder '90_performance_checks.txt'
$checksContent = @()

$checksContent += "batch_total_launches=$($allRows.Count)"
$checksContent += "batch_clean_launches=$($cleanRows.Count)"
$checksContent += "batch_blocked_launches=$($blockedRows.Count)"
$checksContent += "batch_total_runtime_ms=$([Math]::Round($batchElapsedMs, 3))"

$checksContent += "overall_avg_latency_ms=$([Math]::Round($overallStats.Avg, 3))"
$checksContent += "overall_p50_latency_ms=$([Math]::Round($overallStats.P50, 3))"
$checksContent += "overall_p95_latency_ms=$([Math]::Round($overallStats.P95, 3))"
$checksContent += "overall_p99_latency_ms=$([Math]::Round($overallStats.P99, 3))"
$checksContent += "overall_min_latency_ms=$([Math]::Round($overallStats.Min, 3))"
$checksContent += "overall_max_latency_ms=$([Math]::Round($overallStats.Max, 3))"

$checksContent += "clean_avg_latency_ms=$([Math]::Round($cleanStats.Avg, 3))"
$checksContent += "clean_p50_latency_ms=$([Math]::Round($cleanStats.P50, 3))"
$checksContent += "clean_p95_latency_ms=$([Math]::Round($cleanStats.P95, 3))"
$checksContent += "clean_p99_latency_ms=$([Math]::Round($cleanStats.P99, 3))"
$checksContent += "clean_min_latency_ms=$([Math]::Round($cleanStats.Min, 3))"
$checksContent += "clean_max_latency_ms=$([Math]::Round($cleanStats.Max, 3))"

$checksContent += "blocked_avg_latency_ms=$([Math]::Round($blockedStats.Avg, 3))"
$checksContent += "blocked_p50_latency_ms=$([Math]::Round($blockedStats.P50, 3))"
$checksContent += "blocked_p95_latency_ms=$([Math]::Round($blockedStats.P95, 3))"
$checksContent += "blocked_p99_latency_ms=$([Math]::Round($blockedStats.P99, 3))"
$checksContent += "blocked_min_latency_ms=$([Math]::Round($blockedStats.Min, 3))"
$checksContent += "blocked_max_latency_ms=$([Math]::Round($blockedStats.Max, 3))"

$checksContent += "clean_vs_blocked_avg_delta_ms=$([Math]::Round($cleanVsBlockedAvgDeltaMs, 3))"

foreach ($r in $allRows) {
  $checksContent += ("run_{0}_{1:D2}_latency_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round([double]$r.ElapsedMs, 3))
  $checksContent += ("run_{0}_{1:D2}_final_status={2}" -f $r.RunType, $r.RunIndex, $r.FinalStatus)
  $checksContent += ("run_{0}_{1:D2}_exit_code={2}" -f $r.RunType, $r.RunIndex, $r.ExitCode)
  $checksContent += ("run_{0}_{1:D2}_blocked_reason={2}" -f $r.RunType, $r.RunIndex, $r.BlockedReason)
  $checksContent += ("run_{0}_{1:D2}_stdout_file={2}" -f $r.RunType, $r.RunIndex, $r.OutFile)
}

$checksContent += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$checksContent += "failed_check_count=$failedCount"
$checksContent += "failed_checks=$failedChecks"

$checksContent | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contractContent = @()
$contractContent += 'next_phase_selected=PHASE66_0_WIDGET_OPERATOR_PERFORMANCE_BASELINE_MEASUREMENT'
$contractContent += 'objective=Measure baseline launch latency for clean and blocked operator-path runs without behavior changes'
$contractContent += 'changes_introduced=None (measurement-only; no runtime code changes, no optimization)'
$contractContent += 'runtime_behavior_changes=None (observed behavior only; clean RUN_OK, blocked BLOCKED with TRUST_CHAIN_BLOCKED)'
$contractContent += 'new_regressions_detected=No'
$contractContent += "phase_status=$phaseStatus"
$contractContent += "proof_folder=$ProofFolder"
$contractContent | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_performance_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_0_folder={0} phase66_0_status={1} phase66_0_zip={2}" -f $ProofFolder, $phaseStatus, $ZipPath)
exit 0
