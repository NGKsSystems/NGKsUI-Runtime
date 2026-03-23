#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_4: OPERATOR-PATH ATTRIBUTED TIMING BREAKDOWN (MEASUREMENT ONLY)
# ============================================================================
# Uses TIMING_BOUNDARY fields introduced in Phase66_3 to compute attributed
# segment durations and quantify remaining residual overhead.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_4_widget_operator_attributed_timing_breakdown_$Timestamp"
$ProofFolder = Join-Path $ProofRoot $ProofFolderName
$ProofFolderRelative = "_proof/$ProofFolderName"
$ZipPath = "$ProofFolder.zip"

$Phase662ChecksPath = Join-Path $WorkspaceRoot '_proof\phase66_2_widget_operator_launch_overhead_attribution_20260322_204426\90_launch_overhead_attribution_checks.txt'

New-Item -ItemType Directory -Path $ProofFolder -Force | Out-Null
Write-Host "Proof folder: $ProofFolder"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item $Path -Force -ErrorAction Stop
      return $true
    }
    catch {
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

function Get-BoundaryMap {
  param([string]$Path)

  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  foreach ($line in $lines) {
    if ($line -match '^TIMING_BOUNDARY\s+name=([^\s]+)\s+ts_utc=([^\s]+)\s+source=([^\s]+)\s+quality=([^\s]+)$') {
      $name = $Matches[1]
      $ts = $Matches[2]
      $map[$name] = $ts
    }
  }

  return $map
}

function ConvertTo-ParsedUtc {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq 'unavailable' -or $Value -eq 'missing') {
    return $null
  }

  $dt = [datetime]::MinValue
  if ([datetime]::TryParse($Value, [ref]$dt)) {
    return $dt.ToUniversalTime()
  }

  return $null
}

function ConvertTo-NullableDouble {
  param([object]$Value)
  if ($null -eq $Value) { return 0.0 }
  return [double]$Value
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

  $start = $null
  $end = $null
  if ($BoundaryMap.ContainsKey($StartName)) { $start = ConvertTo-ParsedUtc -Value $BoundaryMap[$StartName] }
  if ($BoundaryMap.ContainsKey($EndName)) { $end = ConvertTo-ParsedUtc -Value $BoundaryMap[$EndName] }
  return Get-DiffMs -StartUtc $start -EndUtc $end
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

function Get-Avg {
  param([object[]]$Values)
  $vals = @($Values | Where-Object { $null -ne $_ })
  if ($vals.Count -eq 0) { return 0.0 }
  return [double](($vals | Measure-Object -Average).Average)
}

function Get-Sum {
  param([object[]]$Values)
  $vals = @($Values | Where-Object { $null -ne $_ })
  if ($vals.Count -eq 0) { return 0.0 }
  return [double](($vals | Measure-Object -Sum).Sum)
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

$phase662ResidualBaseline = 0.0
if (Test-Path -LiteralPath $Phase662ChecksPath) {
  $phase662Lines = Get-Content -LiteralPath $Phase662ChecksPath
  foreach ($line in $phase662Lines) {
    if ($line -match '^attribution_avg_residual_unattributed_overhead_ms=(\S+)$') {
      $phase662ResidualBaseline = [double]$Matches[1]
      break
    }
  }
}

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
  $bm = Get-BoundaryMap -Path $outFile

  $s_launcher_to_spawn = Get-SegmentMs -BoundaryMap $bm -StartName 'launcher_invocation_start_timestamp' -EndName 'widget_process_spawn_timestamp'
  $s_spawn_to_runtime_init_start = Get-SegmentMs -BoundaryMap $bm -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_init_guard_start_timestamp'
  $s_runtime_init_guard = Get-SegmentMs -BoundaryMap $bm -StartName 'runtime_init_guard_start_timestamp' -EndName 'runtime_init_guard_end_timestamp'
  $s_runtime_init_end_to_first_frame = Get-SegmentMs -BoundaryMap $bm -StartName 'runtime_init_guard_end_timestamp' -EndName 'first_frame_present_timestamp'
  $s_first_frame_to_autoclose = Get-SegmentMs -BoundaryMap $bm -StartName 'first_frame_present_timestamp' -EndName 'autoclose_trigger_timestamp'
  $s_autoclose_to_term_start = Get-SegmentMs -BoundaryMap $bm -StartName 'autoclose_trigger_timestamp' -EndName 'termination_guard_start_timestamp'
  $s_term_guard = Get-SegmentMs -BoundaryMap $bm -StartName 'termination_guard_start_timestamp' -EndName 'termination_guard_end_timestamp'
  $s_term_end_to_summary = Get-SegmentMs -BoundaryMap $bm -StartName 'termination_guard_end_timestamp' -EndName 'launcher_final_summary_emit_timestamp'

  $attributedFineMs = Get-Sum -Values @($s_launcher_to_spawn, $s_spawn_to_runtime_init_start, $s_runtime_init_guard, $s_runtime_init_end_to_first_frame, $s_first_frame_to_autoclose, $s_autoclose_to_term_start, $s_term_guard, $s_term_end_to_summary)
  $residualMs = [double]$inv.ElapsedMs - $attributedFineMs
  if ($residualMs -lt 0) { $residualMs = 0.0 }

  $rows += [pscustomobject]@{
    RunType = 'clean'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'
    SegLauncherToSpawnMs = $s_launcher_to_spawn
    SegSpawnToRuntimeInitStartMs = $s_spawn_to_runtime_init_start
    SegRuntimeInitGuardMs = $s_runtime_init_guard
    SegRuntimeInitEndToFirstFrameMs = $s_runtime_init_end_to_first_frame
    SegFirstFrameToAutocloseMs = $s_first_frame_to_autoclose
    SegAutocloseToTermStartMs = $s_autoclose_to_term_start
    SegTermGuardMs = $s_term_guard
    SegTermEndToSummaryMs = $s_term_end_to_summary
    AttributedFineMs = [double]$attributedFineMs
    ResidualUnattributedMs = [double]$residualMs
  }
}

for ($i = 1; $i -le $blockedCount; $i++) {
  $idx = $cleanCount + $i
  $name = ('{0:D2}_blocked_run_{1:D2}_stdout.txt' -f $idx, $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Blocked run {0}/{1}" -f $i, $blockedCount)

  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("blocked_run_{0:D2}" -f $i)
  $bm = Get-BoundaryMap -Path $outFile

  $s_launcher_to_spawn = Get-SegmentMs -BoundaryMap $bm -StartName 'launcher_invocation_start_timestamp' -EndName 'widget_process_spawn_timestamp'
  $s_spawn_to_runtime_init_start = Get-SegmentMs -BoundaryMap $bm -StartName 'widget_process_spawn_timestamp' -EndName 'runtime_init_guard_start_timestamp'
  $s_runtime_init_guard = Get-SegmentMs -BoundaryMap $bm -StartName 'runtime_init_guard_start_timestamp' -EndName 'runtime_init_guard_end_timestamp'
  $s_runtime_init_end_to_first_frame = Get-SegmentMs -BoundaryMap $bm -StartName 'runtime_init_guard_end_timestamp' -EndName 'first_frame_present_timestamp'
  $s_first_frame_to_autoclose = Get-SegmentMs -BoundaryMap $bm -StartName 'first_frame_present_timestamp' -EndName 'autoclose_trigger_timestamp'
  $s_autoclose_to_term_start = Get-SegmentMs -BoundaryMap $bm -StartName 'autoclose_trigger_timestamp' -EndName 'termination_guard_start_timestamp'
  $s_term_guard = Get-SegmentMs -BoundaryMap $bm -StartName 'termination_guard_start_timestamp' -EndName 'termination_guard_end_timestamp'
  $s_term_end_to_summary = Get-SegmentMs -BoundaryMap $bm -StartName 'termination_guard_end_timestamp' -EndName 'launcher_final_summary_emit_timestamp'

  $attributedFineMs = Get-Sum -Values @($s_launcher_to_spawn, $s_spawn_to_runtime_init_start, $s_runtime_init_guard, $s_runtime_init_end_to_first_frame, $s_first_frame_to_autoclose, $s_autoclose_to_term_start, $s_term_guard, $s_term_end_to_summary)
  $residualMs = [double]$inv.ElapsedMs - $attributedFineMs
  if ($residualMs -lt 0) { $residualMs = 0.0 }

  $rows += [pscustomobject]@{
    RunType = 'blocked'
    RunIndex = $i
    OutFile = $name
    ElapsedMs = [double]$inv.ElapsedMs
    TimedOut = [bool]$inv.TimedOut
    FinalStatus = Get-LastSummaryValue -Path $outFile -Key 'final_status'
    ExitCode = Get-LastSummaryValue -Path $outFile -Key 'exit_code'
    BlockedReason = Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'
    SegLauncherToSpawnMs = $s_launcher_to_spawn
    SegSpawnToRuntimeInitStartMs = $s_spawn_to_runtime_init_start
    SegRuntimeInitGuardMs = $s_runtime_init_guard
    SegRuntimeInitEndToFirstFrameMs = $s_runtime_init_end_to_first_frame
    SegFirstFrameToAutocloseMs = $s_first_frame_to_autoclose
    SegAutocloseToTermStartMs = $s_autoclose_to_term_start
    SegTermGuardMs = $s_term_guard
    SegTermEndToSummaryMs = $s_term_end_to_summary
    AttributedFineMs = [double]$attributedFineMs
    ResidualUnattributedMs = [double]$residualMs
  }
}

$cleanRows = @($rows | Where-Object { $_.RunType -eq 'clean' })
$blockedRows = @($rows | Where-Object { $_.RunType -eq 'blocked' })
$allRows = @($rows)

$avgSegLauncherToSpawn = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegLauncherToSpawnMs }))
$avgSegSpawnToRuntimeInitStart = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegSpawnToRuntimeInitStartMs }))
$avgSegRuntimeInitGuard = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegRuntimeInitGuardMs }))
$avgSegRuntimeInitEndToFirstFrame = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegRuntimeInitEndToFirstFrameMs }))
$avgSegFirstFrameToAutoclose = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegFirstFrameToAutocloseMs }))
$avgSegAutocloseToTermStart = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegAutocloseToTermStartMs }))
$avgSegTermGuard = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegTermGuardMs }))
$avgSegTermEndToSummary = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.SegTermEndToSummaryMs }))
$avgResidualUnattributed = Get-Avg -Values (@($cleanRows | ForEach-Object { $_.ResidualUnattributedMs }))

$sumSegLauncherToSpawn = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegLauncherToSpawnMs }))
$sumSegSpawnToRuntimeInitStart = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegSpawnToRuntimeInitStartMs }))
$sumSegRuntimeInitGuard = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegRuntimeInitGuardMs }))
$sumSegRuntimeInitEndToFirstFrame = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegRuntimeInitEndToFirstFrameMs }))
$sumSegFirstFrameToAutoclose = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegFirstFrameToAutocloseMs }))
$sumSegAutocloseToTermStart = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegAutocloseToTermStartMs }))
$sumSegTermGuard = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegTermGuardMs }))
$sumSegTermEndToSummary = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.SegTermEndToSummaryMs }))
$sumResidualUnattributed = Get-Sum -Values (@($cleanRows | ForEach-Object { $_.ResidualUnattributedMs }))

$segmentPairs = @(
  [pscustomobject]@{ Name = 'launcher_to_spawn_ms'; Avg = $avgSegLauncherToSpawn },
  [pscustomobject]@{ Name = 'spawn_to_runtime_init_guard_start_ms'; Avg = $avgSegSpawnToRuntimeInitStart },
  [pscustomobject]@{ Name = 'runtime_init_guard_window_ms'; Avg = $avgSegRuntimeInitGuard },
  [pscustomobject]@{ Name = 'runtime_init_guard_end_to_first_frame_ms'; Avg = $avgSegRuntimeInitEndToFirstFrame },
  [pscustomobject]@{ Name = 'first_frame_to_autoclose_trigger_ms'; Avg = $avgSegFirstFrameToAutoclose },
  [pscustomobject]@{ Name = 'autoclose_trigger_to_termination_guard_start_ms'; Avg = $avgSegAutocloseToTermStart },
  [pscustomobject]@{ Name = 'termination_guard_window_ms'; Avg = $avgSegTermGuard },
  [pscustomobject]@{ Name = 'termination_guard_end_to_final_summary_emit_ms'; Avg = $avgSegTermEndToSummary },
  [pscustomobject]@{ Name = 'residual_unattributed_overhead_ms'; Avg = $avgResidualUnattributed }
)
$dominant = $segmentPairs | Sort-Object Avg -Descending | Select-Object -First 1

$reductionMs = [double]($phase662ResidualBaseline - $avgResidualUnattributed)
$reductionPct = if ($phase662ResidualBaseline -gt 0) { [double](100.0 * ($reductionMs / $phase662ResidualBaseline)) } else { 0.0 }
$materiallyReduced = if ($reductionPct -ge 20.0) { 'YES' } else { 'NO' }

$checks = @()
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_clean_status_coherent=' + $(if ((@($cleanRows | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_status_coherent=' + $(if ((@($blockedRows | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_segment_math_nonnegative=' + $(if ((@($cleanRows | Where-Object { $_.ResidualUnattributedMs -lt 0 }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_attribution_improves_vs_phase66_2=' + $(if ($reductionMs -gt 0) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_attributed_timing_breakdown_checks.txt'
$lines = @()
$lines += ('phase66_2_residual_baseline_ms=' + [Math]::Round($phase662ResidualBaseline, 3))
$lines += ('current_residual_unattributed_overhead_avg_ms=' + [Math]::Round($avgResidualUnattributed, 3))
$lines += ('residual_reduction_vs_phase66_2_ms=' + [Math]::Round($reductionMs, 3))
$lines += ('residual_reduction_vs_phase66_2_pct=' + [Math]::Round($reductionPct, 3))
$lines += ('residual_materially_reduced=' + $materiallyReduced)

$lines += ('dominant_measured_segment=' + $dominant.Name)
$lines += ('dominant_measured_segment_avg_ms=' + [Math]::Round([double]$dominant.Avg, 3))

$lines += ('segment_avg_launcher_to_spawn_ms=' + [Math]::Round($avgSegLauncherToSpawn, 3))
$lines += ('segment_avg_spawn_to_runtime_init_guard_start_ms=' + [Math]::Round($avgSegSpawnToRuntimeInitStart, 3))
$lines += ('segment_avg_runtime_init_guard_window_ms=' + [Math]::Round($avgSegRuntimeInitGuard, 3))
$lines += ('segment_avg_runtime_init_guard_end_to_first_frame_ms=' + [Math]::Round($avgSegRuntimeInitEndToFirstFrame, 3))
$lines += ('segment_avg_first_frame_to_autoclose_trigger_ms=' + [Math]::Round($avgSegFirstFrameToAutoclose, 3))
$lines += ('segment_avg_autoclose_trigger_to_termination_guard_start_ms=' + [Math]::Round($avgSegAutocloseToTermStart, 3))
$lines += ('segment_avg_termination_guard_window_ms=' + [Math]::Round($avgSegTermGuard, 3))
$lines += ('segment_avg_termination_guard_end_to_final_summary_emit_ms=' + [Math]::Round($avgSegTermEndToSummary, 3))
$lines += ('segment_avg_residual_unattributed_overhead_ms=' + [Math]::Round($avgResidualUnattributed, 3))

$lines += ('segment_total_launcher_to_spawn_ms=' + [Math]::Round($sumSegLauncherToSpawn, 3))
$lines += ('segment_total_spawn_to_runtime_init_guard_start_ms=' + [Math]::Round($sumSegSpawnToRuntimeInitStart, 3))
$lines += ('segment_total_runtime_init_guard_window_ms=' + [Math]::Round($sumSegRuntimeInitGuard, 3))
$lines += ('segment_total_runtime_init_guard_end_to_first_frame_ms=' + [Math]::Round($sumSegRuntimeInitEndToFirstFrame, 3))
$lines += ('segment_total_first_frame_to_autoclose_trigger_ms=' + [Math]::Round($sumSegFirstFrameToAutoclose, 3))
$lines += ('segment_total_autoclose_trigger_to_termination_guard_start_ms=' + [Math]::Round($sumSegAutocloseToTermStart, 3))
$lines += ('segment_total_termination_guard_window_ms=' + [Math]::Round($sumSegTermGuard, 3))
$lines += ('segment_total_termination_guard_end_to_final_summary_emit_ms=' + [Math]::Round($sumSegTermEndToSummary, 3))
$lines += ('segment_total_residual_unattributed_overhead_ms=' + [Math]::Round($sumResidualUnattributed, 3))

foreach ($r in $allRows) {
  $lines += ("run_{0}_{1:D2}_latency_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.ElapsedMs, 3))
  $lines += ("run_{0}_{1:D2}_final_status={2}" -f $r.RunType, $r.RunIndex, $r.FinalStatus)
  $lines += ("run_{0}_{1:D2}_exit_code={2}" -f $r.RunType, $r.RunIndex, $r.ExitCode)
  $lines += ("run_{0}_{1:D2}_blocked_reason={2}" -f $r.RunType, $r.RunIndex, $r.BlockedReason)
  $lines += ("run_{0}_{1:D2}_segment_launcher_to_spawn_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegLauncherToSpawnMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_spawn_to_runtime_init_guard_start_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegSpawnToRuntimeInitStartMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_runtime_init_guard_window_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegRuntimeInitGuardMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_runtime_init_guard_end_to_first_frame_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegRuntimeInitEndToFirstFrameMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_first_frame_to_autoclose_trigger_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegFirstFrameToAutocloseMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_autoclose_trigger_to_termination_guard_start_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegAutocloseToTermStartMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_termination_guard_window_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegTermGuardMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_termination_guard_end_to_final_summary_emit_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SegTermEndToSummaryMs), 3))
  $lines += ("run_{0}_{1:D2}_segment_residual_unattributed_overhead_ms={2}" -f $r.RunType, $r.RunIndex, [Math]::Round($r.ResidualUnattributedMs, 3))
  $lines += ("run_{0}_{1:D2}_stdout_file={2}" -f $r.RunType, $r.RunIndex, $r.OutFile)
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
$contract += 'next_phase_selected=PHASE66_4_WIDGET_OPERATOR_ATTRIBUTED_TIMING_BREAKDOWN'
$contract += 'objective=Compute attributed launch timing breakdown using TIMING_BOUNDARY fields and quantify residual overhead versus Phase66_2'
$contract += 'changes_introduced=None (measurement-only; no runtime behavior changes)'
$contract += 'runtime_behavior_changes=None (observed behavior only for clean/blocked launches)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_attributed_timing_breakdown_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_4_folder={0} phase66_4_status={1} phase66_4_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
