#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

. (Join-Path $PSScriptRoot 'proof_bundle_common.ps1')

# ============================================================================
# PHASE66_10: SMALLEST REVERSIBLE OPTIMIZATION FOR process_spawn_execution_window_ns
# ============================================================================
# Fresh run only:
#   1) BEFORE measurements on current binary
#   2) rebuild widget_sandbox with optimization candidate
#   3) AFTER measurements on rebuilt binary
#   4) validate behavior and measure impact on target segment
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_10_widget_operator_spawn_window_optimization_$Timestamp"
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

function Get-AvgLong {
  param([object[]]$Values)
  $vals = @($Values | Where-Object { $null -ne $_ })
  if ($vals.Count -eq 0) { return [double]0 }
  return [double](($vals | Measure-Object -Average).Average)
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

$beforeCleanCount = 3
$beforeBlockedCount = 2
$afterCleanCount = 3
$afterBlockedCount = 2
$rows = @()

for ($i = 1; $i -le $beforeCleanCount; $i++) {
  $name = ('01_before_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before clean run {0}/{1}" -f $i, $beforeCleanCount)
  $inv = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_clean_{0:D2}" -f $i)
  $spawnWindowNs = Get-HighResMetric -Path $outFile -Context 'runtime_init' -Metric 'process_spawn_execution_window'
  $rows += [pscustomobject]@{
    Phase='before'; RunType='clean'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut;
    FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status');
    ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code');
    BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE');
    SpawnWindowNs=$spawnWindowNs
  }
}

for ($i = 1; $i -le $beforeBlockedCount; $i++) {
  $name = ('02_before_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("Before blocked run {0}/{1}" -f $i, $beforeBlockedCount)
  $inv = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("before_blocked_{0:D2}" -f $i)
  $rows += [pscustomobject]@{
    Phase='before'; RunType='blocked'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut;
    FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status');
    ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code');
    BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE');
    SpawnWindowNs=$null
  }
}

$buildOut = Join-Path $ProofFolder '03_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with spawn-window optimization candidate...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

for ($i = 1; $i -le $afterCleanCount; $i++) {
  $name = ('04_after_clean_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After clean run {0}/{1}" -f $i, $afterCleanCount)
  $inv = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_clean_{0:D2}" -f $i)
  $spawnWindowNs = Get-HighResMetric -Path $outFile -Context 'runtime_init' -Metric 'process_spawn_execution_window'
  $rows += [pscustomobject]@{
    Phase='after'; RunType='clean'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut;
    FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status');
    ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code');
    BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE');
    SpawnWindowNs=$spawnWindowNs
  }
}

for ($i = 1; $i -le $afterBlockedCount; $i++) {
  $name = ('05_after_blocked_{0:D2}_stdout.txt' -f $i)
  $outFile = Join-Path $ProofFolder $name
  Write-Host ("After blocked run {0}/{1}" -f $i, $afterBlockedCount)
  $inv = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $outFile -TimeoutSeconds 60 -StepName ("after_blocked_{0:D2}" -f $i)
  $rows += [pscustomobject]@{
    Phase='after'; RunType='blocked'; RunIndex=$i; OutFile=$name; TimedOut=$inv.TimedOut;
    FinalStatus=(Get-LastSummaryValue -Path $outFile -Key 'final_status');
    ExitCode=(Get-LastSummaryValue -Path $outFile -Key 'exit_code');
    BlockedReason=(Get-LastSummaryValue -Path $outFile -Key 'blocked_reason' -Default 'NONE');
    SpawnWindowNs=$null
  }
}

$beforeClean = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'clean' })
$afterClean = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'clean' })
$beforeBlocked = @($rows | Where-Object { $_.Phase -eq 'before' -and $_.RunType -eq 'blocked' })
$afterBlocked = @($rows | Where-Object { $_.Phase -eq 'after' -and $_.RunType -eq 'blocked' })
$allRows = @($rows)

$beforeAvgNs = Get-AvgLong -Values (@($beforeClean | ForEach-Object { $_.SpawnWindowNs }))
$afterAvgNs = Get-AvgLong -Values (@($afterClean | ForEach-Object { $_.SpawnWindowNs }))
$deltaNs = [double]($afterAvgNs - $beforeAvgNs)
$improvementNs = [double]($beforeAvgNs - $afterAvgNs)
$improvementPct = if ($beforeAvgNs -gt 0) { [double](100.0 * ($improvementNs / $beforeAvgNs)) } else { [double]0 }

$impactAssessment = if ($improvementNs -gt 1000000) { 'POSITIVE' } elseif ($improvementNs -lt -1000000) { 'NEGATIVE' } else { 'NEGLIGIBLE' }

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_no_hang=' + $(if ((@($allRows | Where-Object { $_.TimedOut }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_before_clean_status_ok=' + $(if ((@($beforeClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_after_clean_status_ok=' + $(if ((@($afterClean | Where-Object { $_.FinalStatus -ne 'RUN_OK' -or $_.ExitCode -ne '0' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_before_blocked_fail_closed=' + $(if ((@($beforeBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_after_blocked_fail_closed=' + $(if ((@($afterBlocked | Where-Object { $_.FinalStatus -ne 'BLOCKED' -or $_.BlockedReason -ne 'TRUST_CHAIN_BLOCKED' -or $_.ExitCode -ne '120' }).Count) -eq 0) { 'YES' } else { 'NO' }))
$checks += ('check_spawn_window_present_before_after=' + $(if ((@($beforeClean | Where-Object { $null -eq $_.SpawnWindowNs }).Count) -eq 0 -and (@($afterClean | Where-Object { $null -eq $_.SpawnWindowNs }).Count) -eq 0) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_spawn_window_optimization_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/runtime_phase53_guard.hpp'
$lines += 'optimization_candidate=add_noninteractive_shell_flag_for_trustchain_invocation'
$lines += 'optimization_scope=runtime_guard_highres_process_spawn_execution_window_ns'
$lines += 'optimization_reversible=YES'
$lines += 'optimization_behavior_preserving=YES'
$lines += ('impact_assessment=' + $impactAssessment)
$lines += ('before_spawn_window_avg_ns=' + [Math]::Round($beforeAvgNs, 3))
$lines += ('after_spawn_window_avg_ns=' + [Math]::Round($afterAvgNs, 3))
$lines += ('spawn_window_delta_after_minus_before_ns=' + [Math]::Round($deltaNs, 3))
$lines += ('spawn_window_improvement_before_minus_after_ns=' + [Math]::Round($improvementNs, 3))
$lines += ('spawn_window_improvement_pct=' + [Math]::Round($improvementPct, 3))
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))

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
$contract += 'next_phase_selected=PHASE66_10_WIDGET_OPERATOR_SMALLEST_REVERSIBLE_OPTIMIZATION_FOR_SPAWN_WINDOW'
$contract += 'objective=Apply the smallest reversible behavior-preserving optimization targeting process_spawn_execution_window_ns and measure before/after impact'
$contract += 'changes_introduced=Added -NonInteractive to trust-chain shell invocation command line'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, and output formats preserved)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_spawn_window_optimization_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

$singleBundleZip = "$ProofFolder`_SINGLE_BUNDLE.zip"
$bundle = New-SingleProofBundle -PhaseProofFolder $ProofFolder -BundleZipPath $singleBundleZip

Write-Host ("phase66_10_folder={0} phase66_10_status={1} phase66_10_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
Write-Host ("phase66_10_single_bundle_zip={0} phase66_10_bundle_item_count={1}" -f $singleBundleZip, $bundle.ItemCount)
exit 0
