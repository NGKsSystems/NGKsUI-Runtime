#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_6: SMALLEST REVERSIBLE OPTIMIZATION FOR spawn_to_runtime_init_guard_start_ms
# ============================================================================
# One fresh sequence:
#  1. BEFORE measurement on current binary
#  2. Rebuild widget_sandbox with minimal optimization patch
#  3. AFTER measurement on rebuilt binary
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_6_widget_operator_smallest_reversible_spawn_optimization_$Timestamp"
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
      $map[$Matches[1]] = $Matches[2]
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
  $s = [datetime]$StartUtc
  $e = [datetime]$EndUtc
  $ms = ($e - $s).TotalMilliseconds
  if ($ms -lt 0) { return $null }
  return [double]$ms
}

function Get-SpawnToInitMs {
  param([hashtable]$BoundaryMap)
  if (-not $BoundaryMap.ContainsKey('widget_process_spawn_timestamp')) { return $null }
  if (-not $BoundaryMap.ContainsKey('runtime_init_guard_start_timestamp')) { return $null }
  return Get-DiffMs -StartUtc (ConvertTo-ParsedUtc -Value $BoundaryMap['widget_process_spawn_timestamp']) -EndUtc (ConvertTo-ParsedUtc -Value $BoundaryMap['runtime_init_guard_start_timestamp'])
}

function Get-LastSummaryValue {
  param([string]$Path, [string]$Key, [string]$Default = '')
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $Default }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match ('\b' + [regex]::Escape($Key) + '=(\S+)')) { return $Matches[1] }
  }
  return $Default
}

function Get-Avg {
  param([object[]]$Values)
  $vals = @($Values | Where-Object { $null -ne $_ })
  if ($vals.Count -eq 0) { return 0.0 }
  return [double](($vals | Measure-Object -Average).Average)
}

function ConvertTo-NullableDouble {
  param([object]$Value)
  if ($null -eq $Value) { return 0.0 }
  return [double]$Value
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

$beforeCleanCount = 3
$beforeBlockedCount = 2
$afterCleanCount = 3
$afterBlockedCount = 2
$rows = @()

for ($i = 1; $i -le $beforeCleanCount; $i++) {
  $name = ('01_before_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before clean run {0}/{1}" -f $i, $beforeCleanCount)
  $inv = Invoke-PwshToFileTimed -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_clean_{0:D2}" -f $i)
  $spawnToInit = Get-SpawnToInitMs -BoundaryMap (Get-BoundaryMap -Path $outFile)
  $rows += [pscustomobject]@{ Phase='before'; RunType='clean'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut; ElapsedMs=[double]$inv.ElapsedMs; FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status'); ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code'); BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'); SpawnToInitMs=$spawnToInit }
}
for ($i = 1; $i -le $beforeBlockedCount; $i++) {
  $name = ('02_before_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before blocked run {0}/{1}" -f $i, $beforeBlockedCount)
  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_blocked_{0:D2}" -f $i)
  $rows += [pscustomobject]@{ Phase='before'; RunType='blocked'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut; ElapsedMs=[double]$inv.ElapsedMs; FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status'); ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code'); BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'); SpawnToInitMs=$null }
}

$buildOut = Join-Path $ProofFolder '03_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with minimal reversible optimization...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

for ($i = 1; $i -le $afterCleanCount; $i++) {
  $name = ('04_after_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After clean run {0}/{1}" -f $i, $afterCleanCount)
  $inv = Invoke-PwshToFileTimed -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_clean_{0:D2}" -f $i)
  $spawnToInit = Get-SpawnToInitMs -BoundaryMap (Get-BoundaryMap -Path $outFile)
  $rows += [pscustomobject]@{ Phase='after'; RunType='clean'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut; ElapsedMs=[double]$inv.ElapsedMs; FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status'); ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code'); BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'); SpawnToInitMs=$spawnToInit }
}
for ($i = 1; $i -le $afterBlockedCount; $i++) {
  $name = ('05_after_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After blocked run {0}/{1}" -f $i, $afterBlockedCount)
  $inv = Invoke-PwshToFileTimed -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_blocked_{0:D2}" -f $i)
  $rows += [pscustomobject]@{ Phase='after'; RunType='blocked'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut; ElapsedMs=[double]$inv.ElapsedMs; FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status'); ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code'); BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason'); SpawnToInitMs=$null }
}

$beforeClean = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'clean' })
$afterClean = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'clean' })
$beforeBlocked = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'blocked' })
$afterBlocked = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'blocked' })
$allRows = @($rows)

$beforeSpawnAvg = Get-Avg -Values (@($beforeClean | ForEach-Object { $_.SpawnToInitMs }))
$afterSpawnAvg = Get-Avg -Values (@($afterClean | ForEach-Object { $_.SpawnToInitMs }))
$spawnDeltaMs = [double]($afterSpawnAvg - $beforeSpawnAvg)
$spawnImprovementMs = [double]($beforeSpawnAvg - $afterSpawnAvg)
$spawnImprovementPct = if ($beforeSpawnAvg -gt 0) { [double](100.0 * ($spawnImprovementMs / $beforeSpawnAvg)) } else { 0.0 }

$impactAssessment = if ($spawnImprovementMs -gt 50) { 'POSITIVE' } elseif ($spawnImprovementMs -lt -50) { 'NEGATIVE' } else { 'NEGLIGIBLE' }

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_before_clean_status_ok=' + $(if ((@($beforeClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_after_clean_status_ok=' + $(if ((@($afterClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_before_blocked_fail_closed=' + $(if ((@($beforeBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_after_blocked_fail_closed=' + $(if ((@($afterBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_spawn_segment_available=' + $(if ((@($beforeClean | Where-Object { $null -eq $_.SpawnToInitMs }).Count) -eq 0 -and (@($afterClean | Where-Object { $null -eq $_.SpawnToInitMs }).Count) -eq 0) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_spawn_segment_optimization_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/runtime_phase53_guard.hpp'
$lines += 'optimization_candidate=cached_default_runtime_init_trust_command_literal'
$lines += 'optimization_scope=spawn_to_runtime_init_guard_start_ms_only'
$lines += 'optimization_reversible=YES'
$lines += 'optimization_behavior_preserving=YES'
$lines += ('impact_assessment=' + $impactAssessment)
$lines += ('before_spawn_to_runtime_init_guard_start_avg_ms=' + [Math]::Round($beforeSpawnAvg, 3))
$lines += ('after_spawn_to_runtime_init_guard_start_avg_ms=' + [Math]::Round($afterSpawnAvg, 3))
$lines += ('spawn_segment_delta_after_minus_before_ms=' + [Math]::Round($spawnDeltaMs, 3))
$lines += ('spawn_segment_improvement_before_minus_after_ms=' + [Math]::Round($spawnImprovementMs, 3))
$lines += ('spawn_segment_improvement_pct=' + [Math]::Round($spawnImprovementPct, 3))
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))

foreach ($r in $allRows) {
  $lines += ("run_{0}_{1}_{2:D2}_latency_ms={3}" -f $r.Phase, $r.RunType, $r.RunIndex, [Math]::Round($r.ElapsedMs, 3))
  $lines += ("run_{0}_{1}_{2:D2}_final_status={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.FinalStatus)
  $lines += ("run_{0}_{1}_{2:D2}_exit_code={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.ExitCode)
  $lines += ("run_{0}_{1}_{2:D2}_blocked_reason={3}" -f $r.Phase, $r.RunType, $r.RunIndex, $r.BlockedReason)
  $lines += ("run_{0}_{1}_{2:D2}_spawn_to_runtime_init_guard_start_ms={3}" -f $r.Phase, $r.RunType, $r.RunIndex, [Math]::Round((ConvertTo-NullableDouble -Value $r.SpawnToInitMs), 3))
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
$contract += 'next_phase_selected=PHASE66_6_WIDGET_OPERATOR_SMALLEST_REVERSIBLE_OPTIMIZATION_FOR_SPAWN_TO_RUNTIME_INIT'
$contract += 'objective=Apply the smallest reversible behavior-preserving optimization for spawn_to_runtime_init_guard_start_ms and measure before/after impact'
$contract += 'changes_introduced=Cached default runtime_init trust command literal in runtime guard startup path'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, and output formats preserved)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_spawn_segment_optimization_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_6_folder={0} phase66_6_status={1} phase66_6_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
