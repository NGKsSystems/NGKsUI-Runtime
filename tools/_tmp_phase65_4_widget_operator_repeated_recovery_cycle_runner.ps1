Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Remove-FileWithRetry {
  param(
    [string]$Path,
    [int]$MaxAttempts = 5,
    [int]$SleepMs = 120
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $true
  }

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    }
    catch {
      if ($attempt -lt $MaxAttempts) {
        Start-Sleep -Milliseconds $SleepMs
      }
    }
  }

  return (-not (Test-Path -LiteralPath $Path))
}

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName,
    [string]$CommandText
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{
      ExitCode = 125
      TimedOut = $false
      FileLock = $true
      LockedFile = $errFile
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
    }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }

    return [pscustomobject]@{
      ExitCode = 124
      TimedOut = $true
      FileLock = $false
      LockedFile = ''
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
    }
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
      return [pscustomobject]@{
        ExitCode = 125
        TimedOut = $false
        FileLock = $true
        LockedFile = $errFile
        StepName = $StepName
        CommandText = $CommandText
        OutFile = $OutFile
      }
    }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = $false
    FileLock = $false
    LockedFile = ''
    StepName = $StepName
    CommandText = $CommandText
    OutFile = $OutFile
  }
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase65_4_widget_operator_repeated_recovery_cycle_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_4_widget_operator_repeated_recovery_cycle_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_recovery_cycle_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"
$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"

$cycles = 3
$blockedCycleResults = @()
$cleanCycleResults = @()

for ($i = 1; $i -le $cycles; $i++) {
  $blockedOut = Join-Path $pf ('10_cycle' + $i.ToString('00') + '_blocked_stdout.txt')
  $b = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $blockedOut -TimeoutSeconds 60 -StepName ('cycle' + $i + '_blocked') -CommandText $blockedCmd

  $bGenerated = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart
  $bError = [bool](Select-String -Path $blockedOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $bBlocked = [bool](Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
  $bFailClosed = [bool](Select-String -Path $blockedOut -Pattern 'FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
  $bReason = [bool](Select-String -Path $blockedOut -Pattern 'blocked_reason=TRUST_CHAIN_BLOCKED|REASON=env_injection_detected' -ErrorAction SilentlyContinue)
  $bSummary = Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
  $bSummaryExit = -1
  if ($bSummary -and $bSummary.Line -match 'exit_code=(\d+)') {
    $bSummaryExit = [int]$Matches[1]
  }
  $bProcessExitOk = ($bSummaryExit -gt 0)

  $blockedCycleResults += [pscustomobject]@{
    Cycle = $i
    OutFile = $blockedOut
    GeneratedInRun = $bGenerated
    LaunchError = $bError
    FinalBlocked = $bBlocked
    FailClosed = $bFailClosed
    ReasonCoherent = $bReason
    ProcessExitOk = $bProcessExitOk
    SummaryExitCode = $bSummaryExit
    TimedOut = $b.TimedOut
    FileLock = $b.FileLock
    WrapperExit = $b.ExitCode
  }

  $cleanOut = Join-Path $pf ('11_cycle' + $i.ToString('00') + '_clean_recovery_stdout.txt')
  $c = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $cleanOut -TimeoutSeconds 60 -StepName ('cycle' + $i + '_clean_recovery') -CommandText $cleanCmd

  $cGenerated = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
  $cRunOk = [bool](Select-String -Path $cleanOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
  $cNoLaunchError = -not [bool](Select-String -Path $cleanOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $cFailClosed = [bool](Select-String -Path $cleanOut -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
  $cPoisoned = [bool](Select-String -Path $cleanOut -Pattern 'final_status=BLOCKED|blocked_reason=TRUST_CHAIN_BLOCKED|runtime_trust_guard_failed' -ErrorAction SilentlyContinue)
  $cExitOk = ($c.ExitCode -eq 0)

  $cleanCycleResults += [pscustomobject]@{
    Cycle = $i
    OutFile = $cleanOut
    GeneratedInRun = $cGenerated
    FinalRunOk = $cRunOk
    NoLaunchError = $cNoLaunchError
    FailClosed = $cFailClosed
    NoPoisonedState = (-not $cPoisoned)
    ExitOk = $cExitOk
    TimedOut = $c.TimedOut
    FileLock = $c.FileLock
    WrapperExit = $c.ExitCode
  }
}

Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$blockedAllPass = (@($blockedCycleResults | Where-Object { -not ($_.GeneratedInRun -and $_.LaunchError -and $_.FinalBlocked -and $_.FailClosed -and $_.ReasonCoherent -and $_.ProcessExitOk -and (-not $_.TimedOut) -and (-not $_.FileLock)) }).Count -eq 0)
$cleanAllPass = (@($cleanCycleResults | Where-Object { -not ($_.GeneratedInRun -and $_.FinalRunOk -and $_.NoLaunchError -and $_.FailClosed -and $_.NoPoisonedState -and $_.ExitOk -and (-not $_.TimedOut) -and (-not $_.FileLock)) }).Count -eq 0)

$cleanExitSet = @($cleanCycleResults | ForEach-Object { [string]$_.WrapperExit } | Select-Object -Unique)
$blockedSummaryExitSet = @($blockedCycleResults | ForEach-Object { [string]$_.SummaryExitCode } | Select-Object -Unique)
$cleanExitConsistent = ($cleanExitSet.Count -eq 1)
$blockedSummaryExitConsistent = ($blockedSummaryExitSet.Count -eq 1)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $blockedAllPass) { $failed.Add('check_blocked_cycles_all_pass=NO') }
if (-not $cleanAllPass) { $failed.Add('check_clean_recovery_cycles_all_pass=NO') }
if (-not $cleanExitConsistent) { $failed.Add('check_clean_exit_consistency=NO') }
if (-not $blockedSummaryExitConsistent) { $failed.Add('check_blocked_summary_exit_consistency=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('proof_folder=' + $pfRel)
$rows.Add('cycles=' + $cycles)

for ($i = 0; $i -lt $cycles; $i++) {
  $b = $blockedCycleResults[$i]
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($b.OutFile))))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_generated_in_run=' + $(if ($b.GeneratedInRun) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_launch_error_present=' + $(if ($b.LaunchError) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_final_status_blocked=' + $(if ($b.FinalBlocked) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_fail_closed=' + $(if ($b.FailClosed) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_reason_coherent=' + $(if ($b.ReasonCoherent) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_process_exit_ok=' + $(if ($b.ProcessExitOk) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_summary_exit_code=' + $b.SummaryExitCode))
  $rows.Add(('cycle' + $b.Cycle.ToString('00') + '_blocked_no_hang=' + $(if (-not $b.TimedOut) { 'YES' } else { 'NO' })))

  $c = $cleanCycleResults[$i]
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($c.OutFile))))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_generated_in_run=' + $(if ($c.GeneratedInRun) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_final_status_run_ok=' + $(if ($c.FinalRunOk) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_no_launch_error=' + $(if ($c.NoLaunchError) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_fail_closed=' + $(if ($c.FailClosed) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_no_poisoned_state=' + $(if ($c.NoPoisonedState) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_exit_ok=' + $(if ($c.ExitOk) { 'YES' } else { 'NO' })))
  $rows.Add(('cycle' + $c.Cycle.ToString('00') + '_clean_no_hang=' + $(if (-not $c.TimedOut) { 'YES' } else { 'NO' })))
}

$rows.Add('check_blocked_cycles_all_pass=' + $(if ($blockedAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_recovery_cycles_all_pass=' + $(if ($cleanAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_exit_consistency=' + $(if ($cleanExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_summary_exit_consistency=' + $(if ($blockedSummaryExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('clean_unique_wrapper_exits=' + ($cleanExitSet -join ','))
$rows.Add('blocked_unique_summary_exit_codes=' + ($blockedSummaryExitSet -join ','))
$rows.Add('check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('widget_process_count_after_cycles=' + $widgetProcCount)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE65_4_WIDGET_OPERATOR_REPEATED_RECOVERY_CYCLE_VALIDATION',
  'objective=Validate repeated operator recovery cycles by executing blocked failure then immediate clean recovery across multiple cycles with no poisoned state accumulation.',
  'changes_introduced=tools/_tmp_phase65_4_widget_operator_repeated_recovery_cycle_runner.ps1 (execution repeated recovery cycle runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_4_folder=' + $pfRel)
Write-Output ('phase65_4_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_4_zip=' + $pfRel + '.zip')
