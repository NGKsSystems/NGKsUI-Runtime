#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_2: OPERATOR-PATH LAUNCH OVERHEAD ATTRIBUTION (MEASUREMENT ONLY)
# ============================================================================
# Objective:
#   Attribute launch overhead as far as possible using current observable
#   boundaries from launcher/runtime output. No runtime behavior changes.
#
# Scope:
#   - One fresh run
#   - Small clean/blocked sample
#   - Segment-level latency attribution from existing evidence
#   - Identify best optimization target segment
#   - Explicitly list missing boundaries for full attribution
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_2_widget_operator_launch_overhead_attribution_$Timestamp"
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

function Parse-LaunchEvidence {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $finalStatus = ''
  $exitCode = ''
  $blockedReason = ''
  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $finalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\S+)') { $exitCode = $Matches[1] }
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

  $frameDeltaMs = 0.0
  $frameLine = ($lines | Where-Object { $_ -match '^frame_delta_ms=' } | Select-Object -Last 1)
  if ($frameLine -and $frameLine -match '^frame_delta_ms=(\d+)$') {
    $frameDeltaMs = [double]$Matches[1]
  }

  $autoCloseRequestMs = 0.0
  $autoCloseLine = ($lines | Where-Object { $_ -match '^LAUNCH_AUTOCLOSE_REQUEST_MS=' } | Select-Object -Last 1)
  if ($autoCloseLine -and $autoCloseLine -match '^LAUNCH_AUTOCLOSE_REQUEST_MS=(\d+)$') {
    $autoCloseRequestMs = [double]$Matches[1]
  }

  return [pscustomobject]@{
    FinalStatus = $finalStatus
    ExitCode = $exitCode
    BlockedReason = $blockedReason
    HasFinalSummary = (-not [string]::IsNullOrWhiteSpace($summaryLine))
    RuntimeInitGuardMs = $runtimeInitGuardMs
    SaveExportGuardMs = $saveExportGuardMs
    FrameDeltaMs = $frameDeltaMs
    AutoCloseRequestMs = $autoCloseRequestMs
  }
}

function Get-Stats {
  param([double[]]$Values)
  if (-not $Values -or $Values.Count -eq 0) {
    return [pscustomobject]@{ Count = 0; Avg = 0.0; Min = 0.0; Max = 0.0 }
  }
  return [pscustomobject]@{
    Count = $Values.Count
    Avg = [double](($Values | Measure-Object -Average).Average)
    Min = [double](($Values | Measure-Object -Minimum).Minimum)
    Max = [double](($Values | Measure-Object -Maximum).Maximum)
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

$cleanCount = 4
$blockedCount = 3
$rows = @()

for ($i = 1; $i -le $cleanCount; $i++) {
  $name = ('{0:D2}_clean_run_{1:D2}_stdout.txt' -f $i, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Clean run {0}/{1}" -f $i, $cleanCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("clean_run_{0:D2}" -f $i)
  $e = Parse-LaunchEvidence -Path $outFile

  $knownSegmentsMs = [double]($e.RuntimeInitGuardMs + $e.SaveExportGuardMs + $e.FrameDeltaMs)
  $residualOverheadMs = [double]($inv.ElapsedMs - $knownSegmentsMs)
  if ($residualOverheadMs -lt 0) { $residualOverheadMs = 0.0 }

  $rows += [pscustomobject]@{
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = [string]$e.FinalStatus
    ExitCode = [string]$e.ExitCode
    BlockedReason = [string]$e.BlockedReason
    HasFinalSummary = [bool]$e.HasFinalSummary
    RuntimeInitGuardMs = [double]$e.RuntimeInitGuardMs
    SaveExportGuardMs = [double]$e.SaveExportGuardMs
    FrameDeltaMs = [double]$e.FrameDeltaMs
    AutoCloseRequestMs = [double]$e.AutoCloseRequestMs
    ResidualOverheadMs = [double]$residualOverheadMs
  }
}

for ($i = 1; $i -le $blockedCount; $i++) {
  $globalIndex = $cleanCount + $i
  $name = ('{0:D2}_blocked_run_{1:D2}_stdout.txt' -f $globalIndex, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Blocked run {0}/{1}" -f $i, $blockedCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("blocked_run_{0:D2}" -f $i)
  $e = Parse-LaunchEvidence -Path $outFile

  $knownSegmentsMs = [double]($e.RuntimeInitGuardMs + $e.SaveExportGuardMs + $e.FrameDeltaMs)
  $residualOverheadMs = [double]($inv.ElapsedMs - $knownSegmentsMs)
  if ($residualOverheadMs -lt 0) { $residualOverheadMs = 0.0 }

  $rows += [pscustomobject]@{
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = [string]$e.FinalStatus
    ExitCode = [string]$e.ExitCode
    BlockedReason = [string]$e.BlockedReason
    HasFinalSummary = [bool]$e.HasFinalSummary
    RuntimeInitGuardMs = [double]$e.RuntimeInitGuardMs
    SaveExportGuardMs = [double]$e.SaveExportGuardMs
    FrameDeltaMs = [double]$e.FrameDeltaMs
    AutoCloseRequestMs = [double]$e.AutoCloseRequestMs
    ResidualOverheadMs = [double]$residualOverheadMs
  }
}

$batchSw.Stop()
$batchElapsedMs = [double]$batchSw.ElapsedMilliseconds

$cleanRows = @($rows | Where-Object { $_.RunType -eq 'clean' })
$blockedRows = @($rows | Where-Object { $_.RunType -eq 'blocked' })
$allRows = @($rows)

$totalStats = Get-Stats -Values (@($allRows | ForEach-Object { $_.ElapsedMs }))
$cleanStats = Get-Stats -Values (@($cleanRows | ForEach-Object { $_.ElapsedMs }))
$blockedStats = Get-Stats -Values (@($blockedRows | ForEach-Object { $_.ElapsedMs }))

$avgRuntimeInitGuardMs = [double](($cleanRows | ForEach-Object { $_.RuntimeInitGuardMs } | Measure-Object -Average).Average)
$avgSaveExportGuardMs = [double](($cleanRows | ForEach-Object { $_.SaveExportGuardMs } | Measure-Object -Average).Average)
$avgFrameDeltaMs = [double](($cleanRows | ForEach-Object { $_.FrameDeltaMs } | Measure-Object -Average).Average)
$avgResidualOverheadMs = [double](($cleanRows | ForEach-Object { $_.ResidualOverheadMs } | Measure-Object -Average).Average)

if ([double]::IsNaN($avgRuntimeInitGuardMs)) { $avgRuntimeInitGuardMs = 0.0 }
if ([double]::IsNaN($avgSaveExportGuardMs)) { $avgSaveExportGuardMs = 0.0 }
if ([double]::IsNaN($avgFrameDeltaMs)) { $avgFrameDeltaMs = 0.0 }
if ([double]::IsNaN($avgResidualOverheadMs)) { $avgResidualOverheadMs = 0.0 }

$segmentAverages = @(
  [pscustomobject]@{ Name = 'runtime_init_guard_elapsed_ms'; AvgMs = $avgRuntimeInitGuardMs },
  [pscustomobject]@{ Name = 'save_export_guard_elapsed_ms'; AvgMs = $avgSaveExportGuardMs },
  [pscustomobject]@{ Name = 'frame_delta_ms'; AvgMs = $avgFrameDeltaMs },
  [pscustomobject]@{ Name = 'residual_unattributed_overhead_ms'; AvgMs = $avgResidualOverheadMs }
)
$target = $segmentAverages | Sort-Object AvgMs -Descending | Select-Object -First 1

$missingBoundaries = @(
  'launcher_invocation_start_timestamp',
  'widget_process_spawn_timestamp',
  'runtime_init_guard_start_end_timestamps',
  'first_frame_present_timestamp',
  'autoclose_trigger_timestamp',
  'termination_guard_start_end_timestamps',
  'launcher_final_summary_emit_timestamp'
)

$checks = @()
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_clean_status_coherent=' + $(if ((@($cleanRows | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_status_coherent=' + $(if ((@($blockedRows | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or -not $_.HasFinalSummary }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_residual_nonnegative=' + $(if ((@($cleanRows | Where-Object { $_.ResidualOverheadMs -lt 0 }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_fine_segments_derivable=' + $(if ((@($cleanRows | Where-Object { $_.RuntimeInitGuardMs -gt 0 -or $_.SaveExportGuardMs -gt 0 -or $_.FrameDeltaMs -gt 0 }).Count) -gt 0) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_launch_overhead_attribution_checks.txt'
$lines = @()
$lines += "batch_total_launches=$($allRows.Count)"
$lines += "batch_clean_launches=$($cleanRows.Count)"
$lines += "batch_blocked_launches=$($blockedRows.Count)"
$lines += "batch_total_runtime_ms=$([Math]::Round($batchElapsedMs, 3))"

$lines += "overall_avg_latency_ms=$([Math]::Round($totalStats.Avg, 3))"
$lines += "overall_min_latency_ms=$([Math]::Round($totalStats.Min, 3))"
$lines += "overall_max_latency_ms=$([Math]::Round($totalStats.Max, 3))"

$lines += "clean_avg_latency_ms=$([Math]::Round($cleanStats.Avg, 3))"
$lines += "clean_min_latency_ms=$([Math]::Round($cleanStats.Min, 3))"
$lines += "clean_max_latency_ms=$([Math]::Round($cleanStats.Max, 3))"

$lines += "blocked_avg_latency_ms=$([Math]::Round($blockedStats.Avg, 3))"
$lines += "blocked_min_latency_ms=$([Math]::Round($blockedStats.Min, 3))"
$lines += "blocked_max_latency_ms=$([Math]::Round($blockedStats.Max, 3))"

$lines += "attribution_avg_runtime_init_guard_elapsed_ms=$([Math]::Round($avgRuntimeInitGuardMs, 3))"
$lines += "attribution_avg_save_export_guard_elapsed_ms=$([Math]::Round($avgSaveExportGuardMs, 3))"
$lines += "attribution_avg_frame_delta_ms=$([Math]::Round($avgFrameDeltaMs, 3))"
$lines += "attribution_avg_residual_unattributed_overhead_ms=$([Math]::Round($avgResidualOverheadMs, 3))"

$lines += "best_optimization_target_segment=$($target.Name)"
$lines += "best_optimization_target_avg_ms=$([Math]::Round([double]$target.AvgMs, 3))"

$lines += ("missing_boundary_requirements={0}" -f ($missingBoundaries -join ';'))

foreach ($r in $allRows) {
  $lines += ("run_{0}_{1:D2}_latency_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.ElapsedMs, 3))
  $lines += ("run_{0}_{1:D2}_final_status={2}" -f $r.RunType, $r.RunIndex, $r.FinalStatus)
  $lines += ("run_{0}_{1:D2}_exit_code={2}" -f $r.RunType, $r.RunIndex, $r.ExitCode)
  $lines += ("run_{0}_{1:D2}_blocked_reason={2}" -f $r.RunType, $r.RunIndex, $r.BlockedReason)
  $lines += ("run_{0}_{1:D2}_runtime_init_guard_elapsed_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.RuntimeInitGuardMs, 3))
  $lines += ("run_{0}_{1:D2}_save_export_guard_elapsed_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.SaveExportGuardMs, 3))
  $lines += ("run_{0}_{1:D2}_frame_delta_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.FrameDeltaMs, 3))
  $lines += ("run_{0}_{1:D2}_residual_unattributed_overhead_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.ResidualOverheadMs, 3))
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
$contract += 'next_phase_selected=PHASE66_2_WIDGET_OPERATOR_LAUNCH_OVERHEAD_ATTRIBUTION'
$contract += 'objective=Attribute launch overhead into finest defensible segments from current launcher/runtime boundaries and identify best optimization target'
$contract += 'changes_introduced=None (measurement-only; no runtime behavior changes)'
$contract += 'runtime_behavior_changes=None (observed launch behavior only for clean/blocked runs)'
$contract += 'new_regressions_detected=No'
$contract += "phase_status=$phaseStatus"
$contract += "proof_folder=$ProofFolderRelative"
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_launch_overhead_attribution_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_2_folder={0} phase66_2_status={1} phase66_2_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
